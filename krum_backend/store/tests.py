from decimal import Decimal
import uuid
from django.contrib.auth.models import User
from django.test import TestCase
from .models import AuditLog, Business, Customer, Expense, Membership, Product, ProductUnit, Sale, Supplier, Unit, InventoryMovement
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
        self.user = User.objects.create_user('manager_user', password='password123')
        self.business = Business.objects.create(name='Super Provision Store', currency='NGN', phone='08011112222')
        Membership.objects.create(user=self.user, business=self.business, role='manager')
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
