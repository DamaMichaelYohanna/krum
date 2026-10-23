from decimal import Decimal
from django.db import transaction
from apps.common.audit import write_audit
from store.models import InventoryBalance, InventoryMovement, ProductUnit, Sale, SaleItem, SalePayment


class SalesService:
    @staticmethod
    @transaction.atomic
    def complete(*, business, customer, items, amount_paid, discount, client_transaction_id, actor=None):
        existing = Sale.objects.filter(business=business, client_transaction_id=client_transaction_id).first()
        if existing:
            return existing

        parsed, subtotal = [], Decimal("0")
        balances = {}

        for item in items:
            unit = ProductUnit.objects.select_related("product").get(id=item["product_unit"], product__business=business)
            quantity = Decimal(str(item["quantity"]))
            required = quantity * unit.conversion_to_base

            prod_id = unit.product_id
            if prod_id not in balances:
                bal, _ = InventoryBalance.objects.select_for_update().get_or_create(product=unit.product)
                balances[prod_id] = bal
            balance = balances[prod_id]

            if balance.quantity_base < required:
                raise ValueError(f"You don't have enough {unit.product.name} in stock to complete this sale.")

            price = Decimal(str(item.get("unit_price", unit.selling_price)))
            if price < unit.minimum_price:
                raise ValueError(f"{unit.product.name} cannot be sold below its minimum price.")

            # Decrement in-memory for subsequent items of the same product in this sale
            balance.quantity_base -= required
            parsed.append((unit, quantity, required, price, balance.average_cost))
            subtotal += quantity * price

        discount = Decimal(str(discount))
        total = subtotal - discount
        if total < 0:
            raise ValueError("Discount cannot exceed subtotal.")

        sale = Sale.objects.create(
            business=business,
            customer=customer,
            subtotal=subtotal,
            discount=discount,
            total=total,
            amount_paid=amount_paid,
            client_transaction_id=client_transaction_id
        )

        for unit, quantity, required, price, average_cost in parsed:
            cogs = required * average_cost
            SaleItem.objects.create(sale=sale, product_unit=unit, quantity=quantity, unit_price=price, cogs=cogs)
            InventoryMovement.objects.create(
                business=business,
                product=unit.product,
                quantity_base=-required,
                unit_cost=average_cost,
                reason=InventoryMovement.Reason.SALE,
                actor=actor,
                reference=str(sale.id)
            )

        # Save all updated balances
        for balance in balances.values():
            balance.save(update_fields=["quantity_base"])

        if amount_paid:
            SalePayment.objects.create(sale=sale, amount=amount_paid, method="cash")

        write_audit(business=business, actor=actor, action="sale.completed", entity=sale, metadata={"total": str(total)})
        return sale

    @staticmethod
    @transaction.atomic
    def reverse(*, sale, actor=None):
        if sale.status == Sale.Status.REVERSED:
            return sale
        for item in sale.items.select_related("product_unit__product"):
            balance, _ = InventoryBalance.objects.select_for_update().get_or_create(product=item.product_unit.product)
            restored = item.quantity * item.product_unit.conversion_to_base
            balance.quantity_base += restored
            balance.save(update_fields=["quantity_base"])
            InventoryMovement.objects.create(
                business=sale.business,
                product=item.product_unit.product,
                quantity_base=restored,
                unit_cost=balance.average_cost,
                reason=InventoryMovement.Reason.REVERSAL,
                actor=actor,
                reference=str(sale.id)
            )
        sale.status = Sale.Status.REVERSED
        sale.save(update_fields=["status"])
        write_audit(business=sale.business, actor=actor, action="sale.reversed", entity=sale)
        return sale
