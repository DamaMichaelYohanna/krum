from decimal import Decimal
from django.db import transaction
from apps.common.audit import write_audit
from store.models import CustomerPayment, CustomerPaymentAllocation, Sale


class DebtService:
    @staticmethod
    @transaction.atomic
    def record_payment(*, business, customer, amount, method="cash", reference="", actor=None):
        amount = Decimal(str(amount))
        sales = list(Sale.objects.select_for_update().filter(business=business, customer=customer, status=Sale.Status.COMPLETED).prefetch_related("customer_payment_allocations").order_by("completed_at"))
        outstanding = sum((sale.total - sale.amount_paid - sum((allocation.amount for allocation in sale.customer_payment_allocations.all()), Decimal("0")) for sale in sales), Decimal("0"))
        if amount > outstanding:
            raise ValueError("Payment cannot exceed the customer's outstanding balance.")
        payment = CustomerPayment.objects.create(business=business, customer=customer, amount=amount, method=method, reference=reference, recorded_by=actor)
        remaining = amount
        for sale in sales:
            paid = sale.amount_paid + sum((allocation.amount for allocation in sale.customer_payment_allocations.all()), Decimal("0"))
            allocation = min(remaining, sale.total - paid)
            if allocation > 0:
                CustomerPaymentAllocation.objects.create(payment=payment, sale=sale, amount=allocation)
                remaining -= allocation
            if not remaining:
                break
        write_audit(business=business, actor=actor, action="customer_payment.recorded", entity=payment, metadata={"amount": str(amount)})
        return payment
