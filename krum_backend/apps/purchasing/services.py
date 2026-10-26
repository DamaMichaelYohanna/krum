from decimal import Decimal
from django.db import transaction
from apps.common.audit import write_audit
from apps.inventory.services import InventoryService
from store.models import InventoryMovement, ProductUnit, Purchase, PurchaseItem


class PurchaseService:
    @staticmethod
    @transaction.atomic
    def complete(*, business, supplier, items, amount_paid, client_transaction_id, actor=None, reference=""):
        existing = Purchase.objects.filter(business=business, client_transaction_id=client_transaction_id).first()
        if existing:
            return existing
        purchase = Purchase.objects.create(business=business, supplier=supplier, amount_paid=amount_paid, client_transaction_id=client_transaction_id, reference=reference)
        total = Decimal("0")
        for item in items:
            unit = ProductUnit.objects.get(id=item["product_unit"], product__business=business)
            quantity, cost = Decimal(str(item["quantity"])), Decimal(str(item["unit_cost"]))
            unit.cost_price = cost
            update_fields = ["cost_price"]
            if "selling_price" in item and item["selling_price"]:
                unit.selling_price = Decimal(str(item["selling_price"]))
                update_fields.append("selling_price")
            unit.save(update_fields=update_fields)
            PurchaseItem.objects.create(purchase=purchase, product_unit=unit, quantity=quantity, unit_cost=cost)
            total += quantity * cost
            InventoryService.receive(business=business, product_unit=unit, quantity=quantity, unit_cost=cost, reason=InventoryMovement.Reason.PURCHASE, actor=actor, reference=str(purchase.id))
            # Keep other units of the same product proportionally updated with new moving average cost
            from store.models import InventoryBalance
            balance = InventoryBalance.objects.filter(product=unit.product).first()
            if balance and balance.average_cost > 0:
                for other_unit in unit.product.units.exclude(id=unit.id):
                    other_unit.cost_price = (balance.average_cost * other_unit.conversion_to_base).quantize(Decimal("0.01"))
                    other_unit.save(update_fields=["cost_price"])
        purchase.total = total
        purchase.save(update_fields=["total"])
        write_audit(business=business, actor=actor, action="purchase.completed", entity=purchase, metadata={"total": str(total)})
        return purchase
