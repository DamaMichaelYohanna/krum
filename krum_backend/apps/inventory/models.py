from django.conf import settings
from django.db import models
from apps.catalog.models import Product
from apps.core.models import TenantModel
class InventoryBalance(models.Model):
    product=models.OneToOneField(Product,on_delete=models.CASCADE,related_name='inventory'); quantity_base=models.DecimalField(max_digits=16,decimal_places=3,default=0); average_cost=models.DecimalField(max_digits=14,decimal_places=2,default=0)
class InventoryMovement(TenantModel):
    class Reason(models.TextChoices):
        OPENING = 'opening', 'Opening stock'
        PURCHASE = 'purchase', 'Purchase'
        SALE = 'sale', 'Sale'
        REVERSAL = 'reversal', 'Sale reversal'
        ADJUSTMENT = 'adjustment', 'Adjustment'
        DAMAGED = 'damaged', 'Damaged goods'
        EXPIRED = 'expired', 'Expired goods'
        MISSING = 'missing', 'Missing goods'
        PHYSICAL_COUNT = 'physical_count', 'Physical count adjustment'
        RETURN = 'return', 'Return'
        OTHER = 'other', 'Other'
    product=models.ForeignKey(Product,on_delete=models.PROTECT); quantity_base=models.DecimalField(max_digits=16,decimal_places=3); unit_cost=models.DecimalField(max_digits=14,decimal_places=2,default=0); reason=models.CharField(max_length=32,choices=Reason.choices); reference=models.CharField(max_length=80,blank=True); actor=models.ForeignKey(settings.AUTH_USER_MODEL,null=True,on_delete=models.SET_NULL)
