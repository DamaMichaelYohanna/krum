from django.db import models
from apps.core.models import TenantModel
class Expense(TenantModel):
    category=models.CharField(max_length=80); amount=models.DecimalField(max_digits=14,decimal_places=2); description=models.TextField(blank=True); occurred_at=models.DateField()
