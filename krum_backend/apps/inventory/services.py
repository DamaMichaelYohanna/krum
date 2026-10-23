from decimal import Decimal
from django.db import transaction
from store.models import InventoryBalance, InventoryMovement
from apps.common.audit import write_audit


class InventoryService:
    """The sole writer for inventory balances and ledger movements."""

    @staticmethod
    def receive(*, business, product_unit, quantity, unit_cost, reason, actor=None, reference=""):
        quantity_base = Decimal(str(quantity)) * product_unit.conversion_to_base
        with transaction.atomic():
            balance, _ = InventoryBalance.objects.select_for_update().get_or_create(product=product_unit.product)
            old_value = balance.quantity_base * balance.average_cost
            new_value = quantity_base * Decimal(str(unit_cost)) / product_unit.conversion_to_base
            balance.quantity_base += quantity_base
            balance.average_cost = (old_value + new_value) / balance.quantity_base if balance.quantity_base else Decimal("0")
            balance.save(update_fields=["quantity_base", "average_cost"])
            return InventoryMovement.objects.create(business=business, product=product_unit.product, quantity_base=quantity_base, unit_cost=unit_cost, reason=reason, actor=actor, reference=reference)

    @staticmethod
    @transaction.atomic
    def adjust(*, business, product, quantity_delta, reason, actor, reference=""):
        """Correct physical stock while preserving a complete ledger record."""
        delta = Decimal(str(quantity_delta))
        if not delta:
            raise ValueError("Adjustment quantity cannot be zero.")
        balance, _ = InventoryBalance.objects.select_for_update().get_or_create(product=product)
        if balance.quantity_base + delta < 0:
            raise ValueError("Stock adjustment cannot reduce inventory below zero.")
        balance.quantity_base += delta
        balance.save(update_fields=["quantity_base"])
        movement = InventoryMovement.objects.create(business=business, product=product, quantity_base=delta, unit_cost=balance.average_cost, reason=reason, actor=actor, reference=reference)
        write_audit(business=business, actor=actor, action="inventory.adjusted", entity=movement, metadata={"quantity_delta": str(delta), "reason": reason})
        return movement
