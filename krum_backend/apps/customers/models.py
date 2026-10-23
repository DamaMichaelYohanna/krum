from decimal import Decimal
from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from apps.core.models import TenantModel
class Customer(TenantModel):
    name=models.CharField(max_length=140); phone=models.CharField(max_length=30,blank=True)
class CustomerPayment(TenantModel):
    customer=models.ForeignKey(Customer,on_delete=models.PROTECT,related_name='payments'); amount=models.DecimalField(max_digits=14,decimal_places=2,validators=[MinValueValidator(Decimal('0.01'))]); method=models.CharField(max_length=20,default='cash'); reference=models.CharField(max_length=80,blank=True); recorded_by=models.ForeignKey(settings.AUTH_USER_MODEL,null=True,on_delete=models.SET_NULL)
class CustomerPaymentAllocation(models.Model):
    payment=models.ForeignKey(CustomerPayment,on_delete=models.CASCADE,related_name='allocations'); sale=models.ForeignKey('sales.Sale',on_delete=models.PROTECT,related_name='customer_payment_allocations'); amount=models.DecimalField(max_digits=14,decimal_places=2,validators=[MinValueValidator(Decimal('0.01'))])
    class Meta: constraints = [models.UniqueConstraint(fields=['payment', 'sale'], name='customers_unique_payment_allocation')]
