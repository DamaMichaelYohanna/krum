import uuid
from django.db import models
from apps.catalog.models import ProductUnit
from apps.core.models import TenantModel
class Sale(TenantModel):
    class Status(models.TextChoices): COMPLETED='completed','Completed'; REVERSED='reversed','Reversed'
    client_transaction_id=models.UUIDField(default=uuid.uuid4); customer=models.ForeignKey('customers.Customer',null=True,blank=True,on_delete=models.SET_NULL); subtotal=models.DecimalField(max_digits=14,decimal_places=2,default=0); discount=models.DecimalField(max_digits=14,decimal_places=2,default=0); total=models.DecimalField(max_digits=14,decimal_places=2,default=0); amount_paid=models.DecimalField(max_digits=14,decimal_places=2,default=0); status=models.CharField(max_length=16,choices=Status.choices,default=Status.COMPLETED); completed_at=models.DateTimeField(auto_now_add=True)
    class Meta: constraints = [models.UniqueConstraint(fields=['business', 'client_transaction_id'], name='sales_unique_transaction')]
class SaleItem(models.Model):
    sale=models.ForeignKey(Sale,on_delete=models.CASCADE,related_name='items'); product_unit=models.ForeignKey(ProductUnit,on_delete=models.PROTECT); quantity=models.DecimalField(max_digits=14,decimal_places=3); unit_price=models.DecimalField(max_digits=14,decimal_places=2); cogs=models.DecimalField(max_digits=14,decimal_places=2)
class SalePayment(models.Model):
    sale=models.ForeignKey(Sale,on_delete=models.CASCADE,related_name='payments'); amount=models.DecimalField(max_digits=14,decimal_places=2); method=models.CharField(max_length=20,default='cash')
