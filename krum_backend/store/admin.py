from django.contrib import admin
from .models import AuditLog, Business, Category, Customer, CustomerPayment, Expense, InventoryBalance, InventoryMovement, Membership, Product, ProductUnit, Purchase, Sale, Supplier, Unit
admin.site.register([AuditLog, Business, Membership, Category, Unit, Product, ProductUnit, InventoryBalance, InventoryMovement, Supplier, Customer, CustomerPayment, Purchase, Sale, Expense])
