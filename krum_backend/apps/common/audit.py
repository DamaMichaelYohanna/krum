from store.models import AuditLog


def write_audit(*, business, actor, action, entity, metadata=None):
    """Write an immutable business audit event from a service boundary."""
    return AuditLog.objects.create(
        business=business,
        actor=actor,
        action=action,
        entity_type=entity.__class__.__name__,
        entity_id=str(entity.pk),
        metadata=metadata or {},
    )
