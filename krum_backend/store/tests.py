from decimal import Decimal
import uuid
from django.contrib.auth.models import User
from django.test import TestCase
from .models import (
    AuditLog, Business, CashSession, Category, Customer, Expense, Membership, Product,
    ProductUnit, Sale, Supplier, Unit, InventoryMovement, InventoryBalance
)
from apps.inventory.services import InventoryService
from apps.customers.services import DebtService
from apps.purchasing.services import PurchaseService
from apps.sales.services import SalesService
from apps.sync.services import SyncService


class InventoryServiceTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user('owner', password='password123')
        self.business = Business.objects.create(name='Krum Test Shop')
        Membership.objects.create(user=self.user, business=self.business, role='owner')
        self.unit = Unit.objects.create(business=self.business, name='Piece')
        self.product = Product.objects.create(business=self.business, name='Milo', base_unit=self.unit, reorder_level=2)
        self.product_unit = ProductUnit.objects.create(product=self.product, unit=self.unit, conversion_to_base=1, selling_price=1500, minimum_price=1000)

    def test_purchase_then_sale_updates_stock_and_cogs(self):
        purchase = PurchaseService.complete(business=self.business, supplier=None, amount_paid=10000, client_transaction_id='a5f1c4b2-9024-4ca2-a710-111111111111', actor=self.user, items=[{'product_unit': self.product_unit.id, 'quantity': 10, 'unit_cost': 1000}])
        self.assertEqual(purchase.total, Decimal('10000'))
        sale = SalesService.complete(business=self.business, customer=None, amount_paid=3000, discount=0, client_transaction_id='a5f1c4b2-9024-4ca2-a710-222222222222', actor=self.user, items=[{'product_unit': self.product_unit.id, 'quantity': 2}])
        self.product.refresh_from_db()
        self.assertEqual(self.product.inventory.quantity_base, Decimal('8'))
        self.assertEqual(sale.items.first().cogs, Decimal('2000'))

    def test_sale_cannot_exceed_stock(self):
        with self.assertRaisesMessage(ValueError, "don't have enough Milo"):
            SalesService.complete(business=self.business, customer=None, amount_paid=0, discount=0, client_transaction_id='a5f1c4b2-9024-4ca2-a710-333333333333', actor=self.user, items=[{'product_unit': self.product_unit.id, 'quantity': 1}])

    def test_reversing_a_sale_restores_stock_and_is_audited(self):
        PurchaseService.complete(business=self.business, supplier=None, amount_paid=10000, client_transaction_id='a5f1c4b2-9024-4ca2-a710-444444444444', actor=self.user, items=[{'product_unit': self.product_unit.id, 'quantity': 10, 'unit_cost': 1000}])
        sale = SalesService.complete(business=self.business, customer=None, amount_paid=1500, discount=0, client_transaction_id='a5f1c4b2-9024-4ca2-a710-555555555555', actor=self.user, items=[{'product_unit': self.product_unit.id, 'quantity': 1}])
        SalesService.reverse(sale=sale, actor=self.user)
        self.product.refresh_from_db()
        self.assertEqual(self.product.inventory.quantity_base, Decimal('10'))
        self.assertTrue(AuditLog.objects.filter(action='sale.reversed', entity_id=str(sale.id)).exists())

    def test_adjustment_is_ledger_backed_and_cannot_create_negative_stock(self):
        movement = InventoryService.adjust(business=self.business, product=self.product, quantity_delta=5, reason=InventoryMovement.Reason.OPENING, actor=self.user)
        self.assertEqual(movement.quantity_base, Decimal('5'))
        self.product.refresh_from_db()
        self.assertEqual(self.product.inventory.quantity_base, Decimal('5'))
        with self.assertRaisesMessage(ValueError, 'below zero'):
            InventoryService.adjust(business=self.business, product=self.product, quantity_delta=-6, reason=InventoryMovement.Reason.ADJUSTMENT, actor=self.user)


class UnitConversionAndPricingTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user('owner2', password='password123')
        self.business = Business.objects.create(name='Drinks Shop')
        Membership.objects.create(user=self.user, business=self.business, role='owner')
        self.bottle = Unit.objects.create(business=self.business, name='Bottle')
        self.crate = Unit.objects.create(business=self.business, name='Crate')
        self.product = Product.objects.create(business=self.business, name='Coca-Cola', base_unit=self.bottle, reorder_level=5)
        # 1 bottle = 1 base, selling 300
        self.pu_bottle = ProductUnit.objects.create(product=self.product, unit=self.bottle, conversion_to_base=Decimal('1.000'), selling_price=300, minimum_price=250)
        # 1 crate = 12 bottles, selling 3500
        self.pu_crate = ProductUnit.objects.create(product=self.product, unit=self.crate, conversion_to_base=Decimal('12.000'), selling_price=3500, minimum_price=3000)

    def test_purchase_crate_and_sell_bottles(self):
        # Buy 5 crates at 3000 each = 60 bottles
        PurchaseService.complete(
            business=self.business, supplier=None, amount_paid=15000,
            client_transaction_id=str(uuid.uuid4()), actor=self.user,
            items=[{'product_unit': self.pu_crate.id, 'quantity': 5, 'unit_cost': 3000}]
        )
        self.product.refresh_from_db()
        self.assertEqual(self.product.inventory.quantity_base, Decimal('60.000'))
        # Each bottle cost = 3000 / 12 = 250
        self.assertEqual(self.product.inventory.average_cost, Decimal('250.00'))

        # Sell 1 crate and 3 bottles
        sale = SalesService.complete(
            business=self.business, customer=None, amount_paid=4400, discount=0,
            client_transaction_id=str(uuid.uuid4()), actor=self.user,
            items=[
                {'product_unit': self.pu_crate.id, 'quantity': 1},
                {'product_unit': self.pu_bottle.id, 'quantity': 3}
            ]
        )
        self.product.refresh_from_db()
        # 60 - 12 - 3 = 45 bottles remaining
        self.assertEqual(self.product.inventory.quantity_base, Decimal('45.000'))
        # Total = 3500 + 3*300 = 4400
        self.assertEqual(sale.total, Decimal('4400.00'))


class CustomerDebtTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user('owner3', password='password123')
        self.business = Business.objects.create(name='Credit Store')
        Membership.objects.create(user=self.user, business=self.business, role='owner')
        self.customer = Customer.objects.create(business=self.business, name='Chidi', phone='08012345678')
        self.unit = Unit.objects.create(business=self.business, name='Piece')
        self.product = Product.objects.create(business=self.business, name='Bread', base_unit=self.unit)
        self.pu = ProductUnit.objects.create(product=self.product, unit=self.unit, conversion_to_base=1, selling_price=1000)
        InventoryService.adjust(business=self.business, product=self.product, quantity_delta=20, reason=InventoryMovement.Reason.OPENING, actor=self.user)

    def test_credit_sale_and_debt_repayment(self):
        # Sale of 5 loaves = 5000, paid 2000, owes 3000
        sale = SalesService.complete(
            business=self.business, customer=self.customer, amount_paid=2000, discount=0,
            client_transaction_id=str(uuid.uuid4()), actor=self.user,
            items=[{'product_unit': self.pu.id, 'quantity': 5}]
        )
        self.assertEqual(sale.total, Decimal('5000'))
        self.assertEqual(sale.amount_paid, Decimal('2000'))

        # Check outstanding debt
        debt_payment = DebtService.record_payment(
            business=self.business, customer=self.customer, amount=3000, method='cash', actor=self.user
        )
        self.assertEqual(debt_payment.amount, Decimal('3000'))
        self.assertEqual(debt_payment.allocations.first().amount, Decimal('3000'))

        # Overpayment must fail
        with self.assertRaisesMessage(ValueError, 'outstanding balance'):
            DebtService.record_payment(business=self.business, customer=self.customer, amount=500, actor=self.user)


class SyncServiceTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user('sync_user', password='password123')
        self.business = Business.objects.create(name='Sync Market')
        Membership.objects.create(user=self.user, business=self.business, role='owner')
        self.unit = Unit.objects.create(business=self.business, name='Pack')
        self.product = Product.objects.create(business=self.business, name='Indomie', base_unit=self.unit, barcode='112233')
        self.pu = ProductUnit.objects.create(product=self.product, unit=self.unit, conversion_to_base=1, cost_price=400, selling_price=500)
        InventoryService.adjust(business=self.business, product=self.product, quantity_delta=50, reason=InventoryMovement.Reason.OPENING, actor=self.user)
        self.customer = Customer.objects.create(business=self.business, name='Emeka', phone='08099887766')

    def test_pull_catalog(self):
        data = SyncService.pull_catalog(business=self.business)
        self.assertEqual(data['business']['name'], 'Sync Market')
        self.assertEqual(len(data['products']), 1)
        self.assertEqual(data['products'][0]['barcode'], '112233')
        self.assertEqual(data['products'][0]['stock_base'], 50.0)

    def test_push_batch_and_idempotency(self):
        sale_cid = str(uuid.uuid4())
        expense_cid = str(uuid.uuid4())
        payload = {
            'sales': [{
                'client_transaction_id': sale_cid,
                'customer_id': self.customer.id,
                'items': [{'product_unit': self.pu.id, 'quantity': 4}],
                'amount_paid': 2000,
                'discount': 0
            }],
            'expenses': [{
                'client_transaction_id': expense_cid,
                'category': 'Transport',
                'amount': 1200,
                'description': 'Market run'
            }]
        }
        res = SyncService.push_batch(business=self.business, actor=self.user, payload=payload)
        self.assertEqual(res['sales']['processed'], 1)
        self.assertEqual(res['expenses']['processed'], 1)

        self.product.refresh_from_db()
        self.assertEqual(self.product.inventory.quantity_base, Decimal('46.000'))
        self.assertEqual(Expense.objects.filter(business=self.business).count(), 1)

        # Re-sending the same sale_cid and expense_cid must not duplicate
        res2 = SyncService.push_batch(business=self.business, actor=self.user, payload=payload)
        self.assertEqual(res2['sales']['processed'], 1)
        self.assertEqual(res2['expenses']['processed'], 1)
        self.product.refresh_from_db()
        self.assertEqual(self.product.inventory.quantity_base, Decimal('46.000'))
        self.assertEqual(Expense.objects.filter(business=self.business).count(), 1)

    def test_push_batch_allows_negative_stock_for_offline_sales(self):
        # Physical shop sold 60 packs offline before recording incoming shipment
        sale_cid = str(uuid.uuid4())
        payload = {
            'sales': [{
                'client_transaction_id': sale_cid,
                'customer_id': self.customer.id,
                'items': [{'product_unit': self.pu.id, 'quantity': 60}],
                'amount_paid': 30000,
                'discount': 0
            }]
        }
        res = SyncService.push_batch(business=self.business, actor=self.user, payload=payload)
        self.assertEqual(res['sales']['processed'], 1)
        self.product.refresh_from_db()
        # 50 - 60 = -10
        self.assertEqual(self.product.inventory.quantity_base, Decimal('-10.000'))

    def test_pull_catalog_includes_recent_sales_and_expenses(self):
        Expense.objects.create(
            business=self.business,
            client_transaction_id='exp-111',
            category='Utilities',
            amount=Decimal('4500.00'),
            description='Electricity',
            occurred_at='2026-10-25'
        )
        SalesService.complete(
            business=self.business,
            customer=self.customer,
            items=[{'product_unit': self.pu.id, 'quantity': 2}],
            amount_paid=Decimal('1000.00'),
            discount=0,
            client_transaction_id=str(uuid.uuid4()),
            actor=self.user,
            allow_negative=True
        )
        data = SyncService.pull_catalog(business=self.business)
        self.assertIn('expenses', data)
        self.assertIn('sales', data)
        self.assertTrue(any(e['category'] == 'Utilities' for e in data['expenses']))
        self.assertTrue(len(data['sales']) >= 1)
        self.assertIn('items', data['sales'][0])


class RestockingAndBusinessTests(TestCase):
    def setUp(self):
        from rest_framework.test import APIClient
        self.client = APIClient()
        self.user = User.objects.create_user('owner_user', password='password123')
        self.business = Business.objects.create(name='Super Provision Store', currency='NGN', phone='08011112222')
        Membership.objects.create(user=self.user, business=self.business, role='owner')
        self.client.force_authenticate(user=self.user)

        self.piece = Unit.objects.create(business=self.business, name='Piece')
        self.carton = Unit.objects.create(business=self.business, name='Carton')
        self.product = Product.objects.create(business=self.business, name='Biscuits', base_unit=self.piece)
        self.pu_piece = ProductUnit.objects.create(
            product=self.product, unit=self.piece, conversion_to_base=Decimal('1.000'),
            cost_price=Decimal('100.00'), selling_price=Decimal('150.00')
        )
        self.pu_carton = ProductUnit.objects.create(
            product=self.product, unit=self.carton, conversion_to_base=Decimal('10.000'),
            cost_price=Decimal('1000.00'), selling_price=Decimal('1400.00')
        )

    def test_purchase_restock_updates_cost_prices_proportionally(self):
        # Restock 5 cartons at new cost of 1200 each (120 per piece) with new selling price 1600
        PurchaseService.complete(
            business=self.business,
            supplier=None,
            items=[{
                'product_unit': self.pu_carton.id,
                'quantity': 5,
                'unit_cost': 1200,
                'selling_price': 1600
            }],
            amount_paid=6000,
            client_transaction_id=str(uuid.uuid4()),
            actor=self.user
        )
        self.pu_carton.refresh_from_db()
        self.pu_piece.refresh_from_db()
        self.product.refresh_from_db()

        self.assertEqual(self.pu_carton.cost_price, Decimal('1200.00'))
        self.assertEqual(self.pu_carton.selling_price, Decimal('1600.00'))
        # Product average cost per base piece is 120.00
        self.assertEqual(self.product.inventory.average_cost, Decimal('120.00'))
        # Other unit (Piece) cost price was updated proportionally to 120.00
        self.assertEqual(self.pu_piece.cost_price, Decimal('120.00'))

    def test_business_profile_patch_and_export_csv(self):
        # PATCH business name
        res = self.client.patch('/api/business/me/', {'name': 'New Store Name', 'phone': '09099998888'}, format='json')
        self.assertEqual(res.status_code, 200)
        self.business.refresh_from_db()
        self.assertEqual(self.business.name, 'New Store Name')
        self.assertEqual(self.business.phone, '09099998888')

        # Create expense and export CSV
        Expense.objects.create(
            business=self.business,
            category='Rent',
            amount=Decimal('50000.00'),
            description='Shop rent',
            occurred_at='2026-10-01'
        )
        csv_res = self.client.get('/api/reports/export/?type=expenses&period=all')
        self.assertEqual(csv_res.status_code, 200)
        self.assertIn('text/csv', csv_res['Content-Type'])
        content = csv_res.content.decode('utf-8')
        self.assertIn('Expense ID', content)
        self.assertIn('Rent', content)
        self.assertIn('50000.00', content)

    def test_reverse_sale_by_uuid_and_numeric_id(self):
        sale_cid = str(uuid.uuid4())
        InventoryService.adjust(business=self.business, product=self.product, quantity_delta=20, reason=InventoryMovement.Reason.OPENING, actor=self.user)
        sale = SalesService.complete(
            business=self.business,
            customer=None,
            items=[{'product_unit': self.pu_piece.id, 'quantity': 5}],
            amount_paid=750,
            discount=0,
            client_transaction_id=sale_cid,
            actor=self.user
        )
        self.product.refresh_from_db()
        self.assertEqual(self.product.inventory.quantity_base, Decimal('15.000'))

        # Reverse via UUID string in URL
        res = self.client.post(f'/api/sales/{sale_cid}/reverse/')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data['status'], 'reversed')

        self.product.refresh_from_db()
        # Stock restored to 20
        self.assertEqual(self.product.inventory.quantity_base, Decimal('20.000'))

    def test_staff_management_and_role_restrictions(self):
        # 1. Owner creates a cashier (sales)
        res = self.client.post('/api/staff/', {
            'username': 'cashier_mary',
            'password': 'password123',
            'role': 'sales',
        }, format='json')
        self.assertEqual(res.status_code, 201)
        cashier_id = res.data['id']
        cashier_user_id = res.data['user_id']
        self.assertEqual(res.data['role'], 'sales')

        # 2. Owner lists staff members
        list_res = self.client.get('/api/staff/')
        self.assertEqual(list_res.status_code, 200)
        self.assertEqual(len(list_res.data), 2)  # Owner + Cashier

        # 3. Role restrictions: Switch to cashier
        cashier_user = User.objects.get(id=cashier_user_id)
        self.client.force_authenticate(user=cashier_user)

        # Cashier is blocked from reports
        rep_res = self.client.get('/api/reports/sales/')
        self.assertEqual(rep_res.status_code, 403)

        # Cashier is blocked from CSV export
        exp_res = self.client.get('/api/reports/export/?type=sales')
        self.assertEqual(exp_res.status_code, 403)

        # Cashier is blocked from staff management
        staff_res = self.client.get('/api/staff/')
        self.assertEqual(staff_res.status_code, 403)

        # 4. Owner updates cashier to manager
        self.client.force_authenticate(user=self.user)
        patch_res = self.client.patch(f'/api/staff/{cashier_id}/', {'role': 'manager'}, format='json')
        self.assertEqual(patch_res.status_code, 200)
        self.assertEqual(patch_res.data['role'], 'manager')

        # 5. Manager can create sales cashier, but CANNOT create another manager
        self.client.force_authenticate(user=cashier_user)
        mgr_create_mgr = self.client.post('/api/staff/', {
            'username': 'manager_two',
            'password': 'password123',
            'role': 'manager',
        }, format='json')
        self.assertEqual(mgr_create_mgr.status_code, 403)

        mgr_create_sales = self.client.post('/api/staff/', {
            'username': 'cashier_peter',
            'password': 'password123',
            'role': 'sales',
        }, format='json')
        self.assertEqual(mgr_create_sales.status_code, 201)
        peter_membership_id = mgr_create_sales.data['id']

        # 6. Owner deletes cashier and cannot delete self
        self.client.force_authenticate(user=self.user)
        owner_membership = Membership.objects.get(user=self.user, business=self.business)
        del_self = self.client.delete(f'/api/staff/{owner_membership.id}/')
        self.assertEqual(del_self.status_code, 400)

        del_peter = self.client.delete(f'/api/staff/{peter_membership_id}/')
        self.assertEqual(del_peter.status_code, 200)
        self.assertFalse(Membership.objects.filter(id=peter_membership_id).exists())

    def test_cash_session_lifecycle_and_reconciliation(self):
        # 1. Initially no session is active
        curr = self.client.get('/api/cash-sessions/current/')
        self.assertEqual(curr.status_code, 200)
        self.assertIsNone(curr.data['session'])

        # 2. Start shift with 5000 opening float
        start_res = self.client.post('/api/cash-sessions/start/', {
            'opening_float': 5000,
            'opening_notes': 'Morning shift float',
        }, format='json')
        self.assertEqual(start_res.status_code, 201)
        session_id = start_res.data['id']
        self.assertEqual(start_res.data['status'], 'open')
        self.assertEqual(start_res.data['expected_cash'], 5000.0)

        # 3. Cannot start another session while open
        dup_res = self.client.post('/api/cash-sessions/start/', {'opening_float': 1000}, format='json')
        self.assertEqual(dup_res.status_code, 400)

        # 4. Make a cash sale of 1500 (10 pieces of Biscuits)
        InventoryService.adjust(business=self.business, product=self.product, quantity_delta=50, reason=InventoryMovement.Reason.OPENING, actor=self.user)
        SalesService.complete(
            business=self.business,
            customer=None,
            items=[{'product_unit': self.pu_piece.id, 'quantity': 10}],
            amount_paid=1500,
            discount=0,
            client_transaction_id=str(uuid.uuid4()),
            actor=self.user,
            payment_method='cash',
        )

        # 5. Record an expense of 500
        Expense.objects.create(
            business=self.business,
            category='Fuel',
            amount=Decimal('500.00'),
            description='Generator fuel for shift',
            occurred_at='2026-10-27',
        )

        # 6. Check live session metrics: expected = 5000 float + 1500 sale - 500 exp = 6000
        live_res = self.client.get('/api/cash-sessions/current/')
        self.assertEqual(live_res.status_code, 200)
        s_data = live_res.data['session']
        self.assertEqual(s_data['cash_sales'], 1500.0)
        self.assertEqual(s_data['cash_expenses'], 500.0)
        self.assertEqual(s_data['expected_cash'], 6000.0)

        # 7. Close session with actual counted cash = 5800 (200 shortage)
        close_res = self.client.post(f'/api/cash-sessions/{session_id}/close/', {
            'closing_cash_actual': 5800,
            'closing_notes': '200 short due to change shortage',
        }, format='json')
        self.assertEqual(close_res.status_code, 200)
        self.assertEqual(close_res.data['status'], 'closed')
        self.assertEqual(close_res.data['expected_cash'], 6000.0)
        self.assertEqual(close_res.data['closing_cash_actual'], 5800.0)
        self.assertEqual(close_res.data['difference'], -200.0)

        # 8. Listing sessions includes this closed session
        list_res = self.client.get('/api/cash-sessions/')
        self.assertEqual(list_res.status_code, 200)
        self.assertEqual(len(list_res.data), 1)
        self.assertEqual(list_res.data[0]['id'], session_id)
        self.assertEqual(list_res.data[0]['difference'], -200.0)

    def test_low_stock_alerts_and_restock_generation(self):
        # 1. Create a supplier
        supplier = Supplier.objects.create(business=self.business, name='Dangote Distributors', phone='08012345678')

        # 2. Assign supplier and reorder level to product (reorder_level = 15)
        self.product.preferred_supplier = supplier
        self.product.reorder_level = Decimal('15.000')
        self.product.save()

        # Currently inventory has 0 pieces (out of stock)
        res = self.client.get('/api/inventory/low-stock/')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data['total_low_stock'], 1)
        self.assertEqual(res.data['out_of_stock_count'], 1)
        item = res.data['items'][0]
        self.assertEqual(item['id'], self.product.id)
        self.assertEqual(item['is_out_of_stock'], True)
        self.assertEqual(item['deficit'], 15.0)
        # target_stock = 15 * 2 = 30 -> suggested_order_qty = 30
        self.assertEqual(item['suggested_reorder_qty'], 30.0)
        self.assertEqual(item['preferred_supplier_name'], 'Dangote Distributors')

        # 3. Filter by supplier
        res_sup = self.client.get(f'/api/inventory/low-stock/?supplier={supplier.id}')
        self.assertEqual(res_sup.status_code, 200)
        self.assertEqual(res_sup.data['total_low_stock'], 1)

        res_none = self.client.get('/api/inventory/low-stock/?supplier=9999')
        self.assertEqual(res_none.status_code, 200)
        self.assertEqual(res_none.data['total_low_stock'], 0)

        # 4. Restock 20 pieces via PurchaseService (now stock is 20 > 15 reorder level)
        PurchaseService.complete(
            business=self.business,
            supplier=supplier,
            items=[{
                'product_unit': self.pu_piece.id,
                'quantity': 20,
                'unit_cost': 100,
            }],
            amount_paid=2000,
            client_transaction_id=str(uuid.uuid4()),
            actor=self.user
        )

        # 5. Check low stock endpoint now reports 0 items
        res_after = self.client.get('/api/inventory/low-stock/')
        self.assertEqual(res_after.status_code, 200)
        self.assertEqual(res_after.data['total_low_stock'], 0)


class LandingAndRootViewsTests(TestCase):
    def setUp(self):
        from rest_framework.test import APIClient
        self.client = APIClient()

    def test_root_landing_page_html(self):
        res = self.client.get('/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('text/html', res['Content-Type'])
        content = res.content.decode('utf-8')
        self.assertIn('Krum', content)
        self.assertIn('Operational', content)
        self.assertIn('/download/krum.apk', content)

    def test_root_landing_page_json(self):
        res = self.client.get('/', HTTP_ACCEPT='application/json')
        self.assertEqual(res.status_code, 200)
        self.assertIn('application/json', res['Content-Type'])
        self.assertEqual(res.data['name'], 'Krum Cloud API')
        self.assertEqual(res.data['status'], 'operational')
        self.assertTrue(len(res.data['endpoints']) > 0)

    def test_api_root_endpoint(self):
        res = self.client.get('/api/')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data['name'], 'Krum Cloud API')
        self.assertEqual(res.data['status'], 'operational')

    def test_health_check_endpoints(self):
        res1 = self.client.get('/health/')
        self.assertEqual(res1.status_code, 200)
        self.assertEqual(res1.data['status'], 'healthy')
        self.assertEqual(res1.data['database'], 'connected')

        res2 = self.client.get('/api/health/')
        self.assertEqual(res2.status_code, 200)
        self.assertEqual(res2.data['status'], 'healthy')

    def test_download_apk_endpoint(self):
        res = self.client.get('/download/krum.apk')
        # Either 200 (file stream) or 302 (redirect to github raw)
        self.assertIn(res.status_code, [200, 302])

    def test_about_page_html(self):
        res = self.client.get('/about/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('text/html', res['Content-Type'])
        content = res.content.decode('utf-8')
        self.assertIn('About Product', content)
        self.assertIn('Offline-First Mobile POS', content)

    def test_pricing_page_html(self):
        res = self.client.get('/pricing/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('text/html', res['Content-Type'])
        content = res.content.decode('utf-8')
        self.assertIn('Starter Solo', content)
        self.assertIn('Pro Supermarket', content)
        self.assertIn('Enterprise Multi-Store', content)

    def test_contact_page_get(self):
        res = self.client.get('/contact/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('text/html', res['Content-Type'])
        content = res.content.decode('utf-8')
        self.assertIn('Talk to the Krum team', content)
        self.assertIn('Contact Us', content)

    def test_contact_page_post_submission(self):
        from apps.core.models import ContactInquiry
        initial_count = ContactInquiry.objects.count()

        payload = {
            'name': 'Emeka Obi',
            'email': 'emeka@superstore.ng',
            'phone': '+2348012345678',
            'store_name': 'Emeka Grand Supermarket',
            'subject': 'Pro Supermarket Plan',
            'message': 'We have 4 cashiers and need barcode scanners and cloud sync setup.'
        }
        res = self.client.post('/contact/', data=payload)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(ContactInquiry.objects.count(), initial_count + 1)
        inquiry = ContactInquiry.objects.first()
        self.assertEqual(inquiry.name, 'Emeka Obi')
        self.assertEqual(inquiry.store_name, 'Emeka Grand Supermarket')
        content = res.content.decode('utf-8')
        self.assertIn('Inquiry Received Successfully', content)
        self.assertIn(f'KRM-INQ-{inquiry.id:04d}', content)

    def test_privacy_page_html(self):
        res = self.client.get('/privacy/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('text/html', res['Content-Type'])
        content = res.content.decode('utf-8')
        self.assertIn('Privacy Policy', content)
        self.assertIn('Offline-First Storage Principles', content)

    def test_terms_page_html(self):
        res = self.client.get('/terms/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('text/html', res['Content-Type'])
        content = res.content.decode('utf-8')
        self.assertIn('Terms & Conditions', content)
        self.assertIn('Software License', content)


class StoreDashboardTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username='merchant_owner@krum.ng', email='merchant_owner@krum.ng', password='secretpassword123')
        self.business = Business.objects.create(name='Krum Mega Supermarket', currency='NGN', phone='+2348011122233')
        Membership.objects.create(user=self.user, business=self.business, role=Membership.Role.OWNER)
        
        # Create a unit, product, and stock
        self.unit = Unit.objects.create(business=self.business, name='Pcs')
        self.product = Product.objects.create(business=self.business, name='Cornflakes 500g', base_unit=self.unit, reorder_level=5)
        self.product_unit = ProductUnit.objects.create(product=self.product, unit=self.unit, conversion_to_base=1, selling_price=2200, minimum_price=2000)
        self.balance = InventoryBalance.objects.create(product=self.product, quantity_base=25, average_cost=1800)

    def test_anonymous_redirected_to_login(self):
        res = self.client.get('/dashboard/')
        self.assertEqual(res.status_code, 302)
        self.assertIn('/dashboard/login/', res['Location'])

    def test_login_page_renders(self):
        res = self.client.get('/dashboard/login/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('Store Admin Portal', res.content.decode('utf-8'))

    def test_login_post_success(self):
        res = self.client.post('/dashboard/login/', {
            'email': 'merchant_owner@krum.ng',
            'password': 'secretpassword123'
        })
        self.assertEqual(res.status_code, 302)
        self.assertEqual(res['Location'], '/dashboard/')

    def test_api_login_with_email(self):
        res = self.client.post('/api/auth/login/', {
            'email': 'merchant_owner@krum.ng',
            'password': 'secretpassword123'
        })
        self.assertEqual(res.status_code, 200)
        self.assertIn('access', res.data)
        self.assertIn('refresh', res.data)

    def test_dashboard_overview_authenticated(self):
        self.client.force_login(self.user)
        res = self.client.get('/dashboard/')
        self.assertEqual(res.status_code, 200)
        content = res.content.decode('utf-8')
        self.assertIn('Executive Dashboard', content)
        self.assertIn('Krum Mega Supermarket', content)
        self.assertIn('Gross Revenue', content)
        self.assertIn('Inventory Valuation', content)

    def test_dashboard_sales_ledger_and_csv(self):
        self.client.force_login(self.user)
        res = self.client.get('/dashboard/sales/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('Sales Ledger & Receipts', res.content.decode('utf-8'))

        # CSV Export
        csv_res = self.client.get('/dashboard/sales/?export=csv')
        self.assertEqual(csv_res.status_code, 200)
        self.assertEqual(csv_res['Content-Type'], 'text/csv')

    def test_dashboard_inventory_catalog(self):
        self.client.force_login(self.user)
        res = self.client.get('/dashboard/inventory/')
        self.assertEqual(res.status_code, 200)
        content = res.content.decode('utf-8')
        self.assertIn('Inventory & Multi-Unit Catalog', content)
        self.assertIn('Cornflakes 500g', content)
        self.assertIn('Healthy Stock', content)

    def test_dashboard_shifts_auditing(self):
        self.client.force_login(self.user)
        CashSession.objects.create(
            business=self.business,
            user=self.user,
            opening_float=Decimal('10000'),
            expected_cash=Decimal('15000'),
            status=CashSession.Status.OPEN
        )
        res = self.client.get('/dashboard/shifts/')
        self.assertEqual(res.status_code, 200)
        content = res.content.decode('utf-8')
        self.assertIn('Cash Drawer & Shift Auditing', content)
        self.assertIn('Active Shifts', content)

    def test_dashboard_customers_debts(self):
        self.client.force_login(self.user)
        Customer.objects.create(business=self.business, name='Chief Okon', phone='+2348099887766')
        res = self.client.get('/dashboard/customers/')
        self.assertEqual(res.status_code, 200)
        content = res.content.decode('utf-8')
        self.assertIn('Customer Credit & Debts', content)
        self.assertIn('Chief Okon', content)

    def test_dashboard_staff_roles(self):
        self.client.force_login(self.user)
        res = self.client.get('/dashboard/staff/')
        self.assertEqual(res.status_code, 200)
        content = res.content.decode('utf-8')
        self.assertIn('Staff & Role Permissions', content)
        self.assertIn('merchant_owner', content)
        self.assertIn('Store Owner', content)

    def test_dashboard_settings_get_and_post(self):
        self.client.force_login(self.user)
        res = self.client.get('/dashboard/settings/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('Store Profile & Settings', res.content.decode('utf-8'))

        post_res = self.client.post('/dashboard/settings/', {
            'name': 'Krum Grand Retail Chain',
            'phone': '+2348099998888',
            'currency': 'NGN'
        })
        self.assertEqual(post_res.status_code, 302)
        self.business.refresh_from_db()
        self.assertEqual(self.business.name, 'Krum Grand Retail Chain')
        self.assertEqual(self.business.phone, '+2348099998888')

    def test_dashboard_logout(self):
        self.client.login(username='merchant_owner', password='secretpassword123')
        res = self.client.get('/dashboard/logout/')
        self.assertEqual(res.status_code, 302)
        self.assertIn('/dashboard/login/', res['Location'])

    def test_dashboard_register_get(self):
        res = self.client.get('/dashboard/register/')
        self.assertEqual(res.status_code, 200)
        self.assertIn('Create an account', res.content.decode('utf-8'))

    def test_dashboard_register_post_success(self):
        res = self.client.post('/dashboard/register/', {
            'business_name': 'Greenfield Retail Hub',
            'email': 'boss@greenfield.com',
            'currency': 'NGN',
            'phone': '08099887766',
            'password': 'strongpassword123',
            'confirm_password': 'strongpassword123'
        })
        self.assertEqual(res.status_code, 302)
        self.assertEqual(res['Location'], '/dashboard/')

        # Verify User and Business created with email serving as both
        new_user = User.objects.get(email='boss@greenfield.com')
        self.assertEqual(new_user.username, 'boss@greenfield.com')
        new_biz = Business.objects.get(name='Greenfield Retail Hub')
        self.assertEqual(new_biz.currency, 'NGN')
        membership = Membership.objects.get(user=new_user, business=new_biz)
        self.assertEqual(membership.role, 'owner')

        # Verify initial units and categories seeded
        self.assertTrue(Unit.objects.filter(business=new_biz, name='Piece').exists())
        self.assertTrue(Unit.objects.filter(business=new_biz, name='Carton').exists())
        self.assertTrue(Category.objects.filter(business=new_biz, name='General Provisions').exists())

    def test_dashboard_register_password_mismatch(self):
        res = self.client.post('/dashboard/register/', {
            'business_name': 'Greenfield Retail Hub',
            'email': 'mismatch@example.com',
            'password': 'password12345',
            'confirm_password': 'password99999'
        })
        self.assertEqual(res.status_code, 200)
        self.assertIn('Passwords do not match', res.content.decode('utf-8'))




