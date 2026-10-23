import uuid
from django.db import models
from apps.catalog.models import ProductUnit
from apps.core.models import TenantModel
class Supplier(TenantModel):
    name=models.CharField(max_length=140); phone=models.CharField(max_length=30,blank=True)
class Purchase(TenantModel):
    client_transaction_id=models.UUIDField(default=uuid.uuid4); supplier=models.ForeignKey(Supplier,null=True,blank=True,on_delete=models.SET_NULL); reference=models.CharField(max_length=80,blank=True); total=models.DecimalField(max_digits=14,decimal_places=2,default=0); amount_paid=models.DecimalField(max_digits=14,decimal_places=2,default=0); completed_at=models.DateTimeField(auto_now_add=True)
    class Meta: constraints = [models.UniqueConstraint(fields=['business', 'client_transaction_id'], name='purchasing_unique_transaction')]
class PurchaseItem(models.Model):
    purchase=models.ForeignKey(Purchase,on_delete=models.CASCADE,related_name='items'); product_unit=models.ForeignKey(ProductUnit,on_delete=models.PROTECT); quantity=models.DecimalField(max_digits=14,decimal_places=3); unit_cost=models.DecimalField(max_digits=14,decimal_places=2)
