from django.conf import settings
from django.db import models
class Business(models.Model):
    name=models.CharField(max_length=160); currency=models.CharField(max_length=3, default='NGN'); phone=models.CharField(max_length=30, blank=True); created_at=models.DateTimeField(auto_now_add=True)
class Membership(models.Model):
    class Role(models.TextChoices): OWNER='owner','Owner'; MANAGER='manager','Manager'; SALES='sales','Sales staff'
    business=models.ForeignKey(Business,on_delete=models.CASCADE,related_name='memberships'); user=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name='business_memberships'); role=models.CharField(max_length=16,choices=Role.choices,default=Role.SALES)
class TenantModel(models.Model):
    business=models.ForeignKey(Business,on_delete=models.CASCADE); created_at=models.DateTimeField(auto_now_add=True); updated_at=models.DateTimeField(auto_now=True)
    class Meta: abstract=True
class AuditLog(TenantModel):
    actor=models.ForeignKey(settings.AUTH_USER_MODEL,null=True,on_delete=models.SET_NULL); action=models.CharField(max_length=80); entity_type=models.CharField(max_length=80); entity_id=models.CharField(max_length=80); metadata=models.JSONField(default=dict,blank=True)
    class Meta:
        indexes = [models.Index(fields=['business', 'created_at']), models.Index(fields=['entity_type', 'entity_id'])]
