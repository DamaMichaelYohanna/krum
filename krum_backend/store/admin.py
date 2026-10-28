from django.contrib import admin
from .models import (
    AuditLog, Business, Category, ContactInquiry, Customer, CustomerPayment,
    Expense, InventoryBalance, InventoryMovement, Membership, Product,
    ProductUnit, Purchase, Sale, Supplier, Unit
)

@admin.register(ContactInquiry)
class ContactInquiryAdmin(admin.ModelAdmin):
    list_display = ('name', 'store_name', 'email', 'phone', 'subject', 'is_resolved', 'created_at')
    list_filter = ('is_resolved', 'subject', 'created_at')
    search_fields = ('name', 'store_name', 'email', 'phone', 'message')
    readonly_fields = ('created_at',)

admin.site.register([
    AuditLog, Business, Membership, Category, Unit, Product, ProductUnit,
    InventoryBalance, InventoryMovement, Supplier, Customer, CustomerPayment,
    Purchase, Sale, Expense
])
