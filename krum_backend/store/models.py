"""Deprecated compatibility imports. Domain models are owned by ``apps``."""
from apps.catalog.models import Category, Product, ProductUnit, Unit
from apps.core.models import AuditLog, Business, ContactInquiry, Membership, TenantModel
from apps.customers.models import Customer, CustomerPayment, CustomerPaymentAllocation
from apps.finance.models import CashSession, Expense
from apps.inventory.models import InventoryBalance, InventoryMovement
from apps.purchasing.models import Purchase, PurchaseItem, Supplier
from apps.sales.models import Sale, SaleItem, SalePayment

__all__ = [
    'AuditLog', 'Business', 'Membership', 'TenantModel', 'ContactInquiry',
    'Category', 'Product', 'ProductUnit', 'Unit',
    'Customer', 'CustomerPayment', 'CustomerPaymentAllocation',
    'CashSession', 'Expense',
    'InventoryBalance', 'InventoryMovement',
    'Purchase', 'PurchaseItem', 'Supplier',
    'Sale', 'SaleItem', 'SalePayment'
]
