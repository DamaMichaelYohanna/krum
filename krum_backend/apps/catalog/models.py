from decimal import Decimal
from django.core.validators import MinValueValidator
from django.db import models
from apps.core.models import TenantModel
class Category(TenantModel):
    name=models.CharField(max_length=80)
    class Meta: constraints = [models.UniqueConstraint(fields=['business', 'name'], name='catalog_unique_category')]
class Unit(TenantModel):
    name=models.CharField(max_length=60); symbol=models.CharField(max_length=12,blank=True)
    class Meta: constraints = [models.UniqueConstraint(fields=['business', 'name'], name='catalog_unique_unit')]
class Product(TenantModel):
    name=models.CharField(max_length=180); sku=models.CharField(max_length=64,blank=True); barcode=models.CharField(max_length=64,blank=True); category=models.ForeignKey(Category,null=True,blank=True,on_delete=models.SET_NULL); base_unit=models.ForeignKey(Unit,on_delete=models.PROTECT); brand=models.CharField(max_length=80,blank=True); reorder_level=models.DecimalField(max_digits=14,decimal_places=3,default=0); active=models.BooleanField(default=True)
    class Meta:
        indexes = [models.Index(fields=['business', 'name']), models.Index(fields=['business', 'barcode'])]
        constraints = [models.UniqueConstraint(fields=['business', 'barcode'], condition=~models.Q(barcode=''), name='catalog_unique_barcode')]
class ProductUnit(models.Model):
    product=models.ForeignKey(Product,on_delete=models.CASCADE,related_name='units'); unit=models.ForeignKey(Unit,on_delete=models.PROTECT); conversion_to_base=models.DecimalField(max_digits=14,decimal_places=3,validators=[MinValueValidator(Decimal('0.001'))]); cost_price=models.DecimalField(max_digits=14,decimal_places=2,default=0); selling_price=models.DecimalField(max_digits=14,decimal_places=2); minimum_price=models.DecimalField(max_digits=14,decimal_places=2,default=0)
    class Meta: constraints = [models.UniqueConstraint(fields=['product', 'unit'], name='catalog_unique_product_unit')]
