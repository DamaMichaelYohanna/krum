from django.conf import settings
from django.db import models
from apps.core.models import TenantModel

class Expense(TenantModel):
    client_transaction_id = models.CharField(max_length=64, blank=True, default='', db_index=True)
    category = models.CharField(max_length=80)
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    description = models.TextField(blank=True)
    occurred_at = models.DateField()

class CashSession(TenantModel):
    class Status(models.TextChoices):
        OPEN = 'open', 'Open'
        CLOSED = 'closed', 'Closed'

    client_session_id = models.CharField(max_length=64, blank=True, default='', db_index=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='cash_sessions')
    opened_at = models.DateTimeField(auto_now_add=True)
    closed_at = models.DateTimeField(null=True, blank=True)
    opening_float = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    cash_sales = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    cash_debt_payments = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    cash_expenses = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    expected_cash = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    closing_cash_actual = models.DecimalField(max_digits=14, decimal_places=2, null=True, blank=True)
    difference = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.OPEN, db_index=True)
    opening_notes = models.TextField(blank=True)
    closing_notes = models.TextField(blank=True)

    class Meta:
        ordering = ['-opened_at']
