from decimal import Decimal
import logging
from django.db import transaction
from django.utils import timezone
from store.models import (
    Business, Category, Unit, Product, ProductUnit, Customer,
    Supplier, Expense, InventoryBalance, Sale
)
from apps.inventory.services import InventoryService
from apps.customers.services import DebtService
from apps.purchasing.services import PurchaseService
from apps.sales.services import SalesService

logger = logging.getLogger(__name__)

class SyncService:
    @staticmethod
    def pull_catalog(*, business):
        """Returns the full master catalog, debtors, and suppliers for local client hydration."""
        categories = list(Category.objects.filter(business=business).values('id', 'name'))
        units = list(Unit.objects.filter(business=business).values('id', 'name', 'symbol'))
        suppliers = list(Supplier.objects.filter(business=business).values('id', 'name', 'phone'))

        # Customers with outstanding balances
        customers = []
        for c in Customer.objects.filter(business=business):
            due = sum((
                sale.total - sale.amount_paid - sum((alloc.amount for alloc in sale.customer_payment_allocations.all()), Decimal('0'))
                for sale in c.sale_set.filter(status=Sale.Status.COMPLETED)
            ), Decimal('0'))
            customers.append({
                'id': c.id,
                'name': c.name,
                'phone': c.phone,
                'outstanding': float(due)
            })

        # Products with inventory and configured units
        products = []
        for p in Product.objects.filter(business=business, active=True).select_related('base_unit', 'inventory').prefetch_related('units__unit'):
            inv = getattr(p, 'inventory', None)
            stock = float(inv.quantity_base) if inv else 0.0
            cost = float(inv.average_cost) if inv else 0.0

            p_units = []
            for u in p.units.all():
                p_units.append({
                    'id': u.id,
                    'unit_id': u.unit_id,
                    'unit_name': u.unit.name,
                    'conversion_to_base': float(u.conversion_to_base),
                    'cost_price': float(u.cost_price),
                    'selling_price': float(u.selling_price),
                    'minimum_price': float(u.minimum_price)
                })

            products.append({
                'id': p.id,
                'name': p.name,
                'sku': p.sku,
                'barcode': p.barcode,
                'category_id': p.category_id,
                'base_unit_id': p.base_unit_id,
                'base_unit_name': p.base_unit.name if p.base_unit else '',
                'brand': p.brand,
                'reorder_level': float(p.reorder_level),
                'stock_base': stock,
                'average_cost': cost,
                'units': p_units
            })

        return {
            'business': {
                'id': business.id,
                'name': business.name,
                'currency': business.currency,
                'phone': business.phone
            },
            'categories': categories,
            'units': units,
            'products': products,
            'customers': customers,
            'suppliers': suppliers,
            'server_time': timezone.now().isoformat()
        }

    @staticmethod
    def push_batch(*, business, actor, payload):
        """Processes an offline batch of sales, purchases, customer payments, adjustments, and expenses."""
        results = {
            'sales': {'processed': 0, 'errors': []},
            'purchases': {'processed': 0, 'errors': []},
            'customer_payments': {'processed': 0, 'errors': []},
            'stock_adjustments': {'processed': 0, 'errors': []},
            'expenses': {'processed': 0, 'errors': []},
        }

        # 1. Sales
        for item in payload.get('sales', []):
            cid = item.get('client_transaction_id')
            try:
                cust = Customer.objects.filter(id=item.get('customer_id'), business=business).first() if item.get('customer_id') else None
                SalesService.complete(
                    business=business,
                    customer=cust,
                    items=item.get('items', []),
                    amount_paid=Decimal(str(item.get('amount_paid', 0))),
                    discount=Decimal(str(item.get('discount', 0))),
                    client_transaction_id=cid,
                    actor=actor
                )
                results['sales']['processed'] += 1
            except Exception as e:
                logger.warning("Failed to sync sale %s: %s", cid, e)
                results['sales']['errors'].append({'id': str(cid), 'error': str(e)})

        # 2. Purchases
        for item in payload.get('purchases', []):
            cid = item.get('client_transaction_id')
            try:
                supp = Supplier.objects.filter(id=item.get('supplier_id'), business=business).first() if item.get('supplier_id') else None
                PurchaseService.complete(
                    business=business,
                    supplier=supp,
                    items=item.get('items', []),
                    amount_paid=Decimal(str(item.get('amount_paid', 0))),
                    client_transaction_id=cid,
                    actor=actor,
                    reference=item.get('reference', '')
                )
                results['purchases']['processed'] += 1
            except Exception as e:
                logger.warning("Failed to sync purchase %s: %s", cid, e)
                results['purchases']['errors'].append({'id': str(cid), 'error': str(e)})

        # 3. Customer Payments
        for item in payload.get('customer_payments', []):
            try:
                cust = Customer.objects.filter(id=item.get('customer_id'), business=business).first()
                if not cust:
                    raise ValueError(f"Customer {item.get('customer_id')} not found")
                DebtService.record_payment(
                    business=business,
                    customer=cust,
                    amount=Decimal(str(item.get('amount', 0))),
                    method=item.get('method', 'cash'),
                    reference=item.get('reference', ''),
                    actor=actor
                )
                results['customer_payments']['processed'] += 1
            except Exception as e:
                results['customer_payments']['errors'].append({'customer_id': item.get('customer_id'), 'error': str(e)})

        # 4. Stock Adjustments
        for item in payload.get('stock_adjustments', []):
            try:
                prod = Product.objects.filter(id=item.get('product_id'), business=business).first()
                if not prod:
                    raise ValueError(f"Product {item.get('product_id')} not found")
                InventoryService.adjust(
                    business=business,
                    product=prod,
                    quantity_delta=Decimal(str(item.get('quantity_delta', 0))),
                    reason=item.get('reason', 'physical_count'),
                    actor=actor,
                    reference=item.get('reference', '')
                )
                results['stock_adjustments']['processed'] += 1
            except Exception as e:
                results['stock_adjustments']['errors'].append({'product_id': item.get('product_id'), 'error': str(e)})

        # 5. Expenses
        for item in payload.get('expenses', []):
            try:
                Expense.objects.create(
                    business=business,
                    category=item.get('category', 'Other'),
                    amount=Decimal(str(item.get('amount', 0))),
                    description=item.get('description', ''),
                    occurred_at=item.get('occurred_at') or timezone.localdate()
                )
                results['expenses']['processed'] += 1
            except Exception as e:
                results['expenses']['errors'].append({'error': str(e)})

        return results
