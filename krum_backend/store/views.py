import csv
from datetime import timedelta
from decimal import Decimal
from django.contrib.auth import get_user_model
from django.db.models import F, Sum, Q
from django.db.models.functions import Coalesce
from django.http import HttpResponse
from django.utils import timezone
from rest_framework import generics, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from .models import (
    AuditLog, Business, Category, Customer, CustomerPayment, Expense,
    CashSession, InventoryBalance, InventoryMovement, Membership, Product,
    ProductUnit, Purchase, PurchaseItem, Sale, SaleItem, SalePayment,
    Supplier, Unit
)
from .permissions import HasBusiness, business_for, require_role
from .serializers import (
    BusinessSerializer, CategorySerializer, CustomerPaymentSerializer,
    CustomerSerializer, ExpenseSerializer, InventoryMovementSerializer,
    ProductSerializer, ProductUnitSerializer, PurchaseSerializer,
    RegisterSerializer, SaleSerializer, StockAdjustmentSerializer,
    SupplierSerializer, TransactionSerializer, UnitSerializer
)
from apps.inventory.services import InventoryService
from apps.customers.services import DebtService
from apps.purchasing.services import PurchaseService
from apps.sales.services import SalesService

# --- Base Tenant Views ---

class TenantListCreate(generics.ListCreateAPIView):
    permission_classes = [HasBusiness]
    def get_queryset(self):
        return self.queryset.filter(business=business_for(self.request))
    def perform_create(self, serializer):
        serializer.save(business=business_for(self.request))

class TenantRetrieveUpdateDestroy(generics.RetrieveUpdateDestroyAPIView):
    permission_classes = [HasBusiness]
    def get_queryset(self):
        return self.queryset.filter(business=business_for(self.request))

# --- Categories & Units ---

class CategoryView(TenantListCreate):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer

class CategoryDetailView(TenantRetrieveUpdateDestroy):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer

class UnitView(TenantListCreate):
    queryset = Unit.objects.all()
    serializer_class = UnitSerializer

class UnitDetailView(TenantRetrieveUpdateDestroy):
    queryset = Unit.objects.all()
    serializer_class = UnitSerializer

# --- Suppliers & Customers ---

class SupplierView(TenantListCreate):
    queryset = Supplier.objects.all()
    serializer_class = SupplierSerializer

class SupplierDetailView(TenantRetrieveUpdateDestroy):
    queryset = Supplier.objects.all()
    serializer_class = SupplierSerializer

class CustomerView(TenantListCreate):
    queryset = Customer.objects.all()
    serializer_class = CustomerSerializer

class CustomerDetailView(TenantRetrieveUpdateDestroy):
    queryset = Customer.objects.all()
    serializer_class = CustomerSerializer

@api_view(['GET'])
@permission_classes([HasBusiness])
def customer_ledger(request, pk):
    business = business_for(request)
    customer = Customer.objects.filter(id=pk, business=business).first()
    if not customer:
        return Response({'detail': 'Customer not found.'}, status=status.HTTP_404_NOT_FOUND)
    
    sales = Sale.objects.filter(customer=customer, business=business).order_by('-completed_at')[:50]
    payments = CustomerPayment.objects.filter(customer=customer, business=business).order_by('-created_at')[:50]

    return Response({
        'customer': CustomerSerializer(customer).data,
        'sales': SaleSerializer(sales, many=True).data,
        'payments': [
            {
                'id': p.id,
                'amount': float(p.amount),
                'method': p.method,
                'reference': p.reference,
                'date': p.created_at
            } for p in payments
        ]
    })

# --- Expenses ---

def _get_date_range(period, request):
    today = timezone.localdate()
    if period == 'yesterday':
        start = today - timedelta(days=1)
        end = start
    elif period == 'this_week':
        start = today - timedelta(days=today.weekday())
        end = today
    elif period == 'this_month':
        start = today.replace(day=1)
        end = today
    elif period == 'custom':
        start_str = request.query_params.get('start_date')
        end_str = request.query_params.get('end_date')
        start = timezone.datetime.strptime(start_str, '%Y-%m-%d').date() if start_str else today
        end = timezone.datetime.strptime(end_str, '%Y-%m-%d').date() if end_str else today
    elif period == 'all':
        start = timezone.datetime(2000, 1, 1).date()
        end = today + timedelta(days=3650)
    else:  # today
        start = today
        end = today
    return start, end

class ExpenseView(TenantListCreate):
    queryset = Expense.objects.all().order_by('-occurred_at', '-id')
    serializer_class = ExpenseSerializer

    def get_queryset(self):
        qs = super().get_queryset()
        period = self.request.query_params.get('period')
        start_date = self.request.query_params.get('start_date')
        end_date = self.request.query_params.get('end_date')
        category = self.request.query_params.get('category')

        if period and period.lower() != 'all':
            start, end = _get_date_range(period.lower(), self.request)
            qs = qs.filter(occurred_at__gte=start, occurred_at__lte=end)
        else:
            if start_date:
                qs = qs.filter(occurred_at__gte=start_date)
            if end_date:
                qs = qs.filter(occurred_at__lte=end_date)

        if category and category.lower() != 'all':
            qs = qs.filter(category__iexact=category)

        return qs

    def perform_create(self, serializer):
        require_role(self.request, 'owner', 'manager')
        super().perform_create(serializer)

class ExpenseDetailView(TenantRetrieveUpdateDestroy):
    queryset = Expense.objects.all()
    serializer_class = ExpenseSerializer

    def perform_destroy(self, instance):
        require_role(self.request, 'owner', 'manager')
        super().perform_destroy(instance)

# --- Products ---

class ProductView(TenantListCreate):
    queryset = Product.objects.select_related('inventory', 'base_unit', 'category').prefetch_related('units__unit')
    serializer_class = ProductSerializer

    def get_queryset(self):
        qs = super().get_queryset()
        query = self.request.query_params.get('q', '').strip()
        category_id = self.request.query_params.get('category')
        if category_id:
            qs = qs.filter(category_id=category_id)
        if query:
            qs = qs.filter(Q(name__icontains=query) | Q(barcode__icontains=query) | Q(sku__icontains=query))
        return qs.order_by('name')

    def perform_create(self, serializer):
        require_role(self.request, 'owner', 'manager')
        super().perform_create(serializer)

class ProductDetailView(TenantRetrieveUpdateDestroy):
    queryset = Product.objects.select_related('inventory', 'base_unit', 'category').prefetch_related('units__unit')
    serializer_class = ProductSerializer

    def perform_update(self, serializer):
        require_role(self.request, 'owner', 'manager')
        super().perform_update(serializer)

    def perform_destroy(self, instance):
        require_role(self.request, 'owner', 'manager')
        instance.active = False
        instance.save(update_fields=['active'])

@api_view(['POST'])
@permission_classes([HasBusiness])
def add_product_unit(request, product_id):
    require_role(request, 'owner', 'manager')
    business = business_for(request)
    product = Product.objects.filter(id=product_id, business=business).first()
    if not product:
        return Response({'detail': 'Product not found.'}, status=status.HTTP_404_NOT_FOUND)
    serializer = ProductUnitSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    unit = Unit.objects.filter(id=serializer.validated_data['unit'].id, business=business).first()
    if not unit:
        return Response({'detail': 'Unit not found.'}, status=status.HTTP_400_BAD_REQUEST)
    if ProductUnit.objects.filter(product=product, unit=unit).exists():
        return Response({'detail': 'This unit is already configured for the product.'}, status=status.HTTP_400_BAD_REQUEST)
    product_unit = serializer.save(product=product)
    return Response(ProductUnitSerializer(product_unit).data, status=status.HTTP_201_CREATED)

@api_view(['DELETE'])
@permission_classes([HasBusiness])
def delete_product_unit(request, product_id, unit_id):
    require_role(request, 'owner', 'manager')
    business = business_for(request)
    pu = ProductUnit.objects.filter(id=unit_id, product_id=product_id, product__business=business).first()
    if not pu:
        return Response({'detail': 'Unit configuration not found.'}, status=status.HTTP_404_NOT_FOUND)
    if pu.unit_id == pu.product.base_unit_id:
        return Response({'detail': 'Cannot delete the base unit configuration.'}, status=status.HTTP_400_BAD_REQUEST)
    pu.delete()
    return Response(status=status.HTTP_204_NO_CONTENT)

@api_view(['GET'])
@permission_classes([HasBusiness])
def barcode_lookup(request, barcode):
    product = Product.objects.select_related('inventory', 'base_unit', 'category').prefetch_related('units__unit').filter(
        business=business_for(request), barcode=barcode, active=True
    ).first()
    if not product:
        return Response({'detail': 'Product not found.'}, status=status.HTTP_404_NOT_FOUND)
    return Response(ProductSerializer(product).data)

# --- Authentication & Business Profile ---

@api_view(['POST'])
@permission_classes([AllowAny])
def register(request):
    serializer = RegisterSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    user = serializer.save()
    return Response({'id': user.id, 'username': user.username}, status=status.HTTP_201_CREATED)

@api_view(['GET', 'PATCH'])
@permission_classes([HasBusiness])
def business_me(request):
    business = business_for(request)
    membership = Membership.objects.filter(business=business, user=request.user).first()
    role = membership.role if membership else 'sales'

    if request.method == 'PATCH':
        require_role(request, 'owner', 'manager')
        serializer = BusinessSerializer(business, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response({**serializer.data, 'role': role, 'username': request.user.username})

    data = BusinessSerializer(business).data
    data['role'] = role
    data['username'] = request.user.username
    return Response(data)

# --- Staff & Cashier Management ---

@api_view(['GET', 'POST'])
@permission_classes([HasBusiness])
def staff_list_create(request):
    business = business_for(request)

    if request.method == 'GET':
        require_role(request, 'owner', 'manager')
        memberships = Membership.objects.filter(business=business).select_related('user').order_by('id')
        data = [
            {
                'id': m.id,
                'user_id': m.user.id,
                'username': m.user.username,
                'role': m.role,
                'date_joined': m.user.date_joined.isoformat() if m.user.date_joined else None,
                'is_active': m.user.is_active,
            }
            for m in memberships
        ]
        return Response(data)

    elif request.method == 'POST':
        caller_membership = require_role(request, 'owner', 'manager')
        username = (request.data.get('username') or '').strip()
        password = (request.data.get('password') or '').strip()
        role = (request.data.get('role') or 'sales').strip().lower()

        if not username:
            return Response({'detail': 'Username is required.'}, status=status.HTTP_400_BAD_REQUEST)
        if len(password) < 6:
            return Response({'detail': 'Password must be at least 6 characters long.'}, status=status.HTTP_400_BAD_REQUEST)

        if role not in ['sales', 'manager']:
            return Response({'detail': 'Role must be either "sales" or "manager".'}, status=status.HTTP_400_BAD_REQUEST)

        if caller_membership.role == 'manager' and role != 'sales':
            return Response({'detail': 'Store managers can only create sales/cashier accounts.'}, status=status.HTTP_403_FORBIDDEN)

        User = get_user_model()
        if User.objects.filter(username__iexact=username).exists():
            return Response({'detail': f'Username "{username}" is already in use. Please choose another.'}, status=status.HTTP_400_BAD_REQUEST)

        user = User.objects.create_user(username=username, password=password)
        membership = Membership.objects.create(business=business, user=user, role=role)
        AuditLog.objects.create(
            business=business,
            actor=request.user,
            action='staff.created',
            entity_type='membership',
            entity_id=str(membership.id),
            metadata={'username': username, 'role': role}
        )

        return Response({
            'id': membership.id,
            'user_id': user.id,
            'username': user.username,
            'role': membership.role,
            'date_joined': user.date_joined.isoformat() if user.date_joined else None,
            'is_active': user.is_active,
        }, status=status.HTTP_201_CREATED)


@api_view(['PATCH', 'DELETE'])
@permission_classes([HasBusiness])
def staff_detail(request, membership_id):
    business = business_for(request)
    membership = Membership.objects.filter(id=membership_id, business=business).select_related('user').first()
    if not membership:
        return Response({'detail': 'Staff member not found.'}, status=status.HTTP_404_NOT_FOUND)

    if request.method == 'PATCH':
        require_role(request, 'owner')
        if membership.role == 'owner' and membership.user == request.user:
            return Response({'detail': 'Cannot modify the store owner role.'}, status=status.HTTP_400_BAD_REQUEST)

        new_role = request.data.get('role')
        if new_role is not None:
            new_role = str(new_role).strip().lower()
            if new_role not in ['sales', 'manager']:
                return Response({'detail': 'Role must be either "sales" or "manager".'}, status=status.HTTP_400_BAD_REQUEST)
            membership.role = new_role

        if 'is_active' in request.data:
            membership.user.is_active = bool(request.data['is_active'])
            membership.user.save(update_fields=['is_active'])

        membership.save(update_fields=['role'])
        AuditLog.objects.create(
            business=business,
            actor=request.user,
            action='staff.updated',
            entity_type='membership',
            entity_id=str(membership.id),
            metadata={'role': membership.role, 'is_active': membership.user.is_active}
        )

        return Response({
            'id': membership.id,
            'user_id': membership.user.id,
            'username': membership.user.username,
            'role': membership.role,
            'date_joined': membership.user.date_joined.isoformat() if membership.user.date_joined else None,
            'is_active': membership.user.is_active,
        })

    elif request.method == 'DELETE':
        require_role(request, 'owner')
        if membership.user == request.user:
            return Response({'detail': 'You cannot remove your own ownership account.'}, status=status.HTTP_400_BAD_REQUEST)
        if membership.role == 'owner':
            return Response({'detail': 'Cannot delete an owner account.'}, status=status.HTTP_400_BAD_REQUEST)

        staff_user = membership.user
        staff_username = staff_user.username
        membership.delete()
        staff_user.is_active = False
        staff_user.save(update_fields=['is_active'])

        AuditLog.objects.create(
            business=business,
            actor=request.user,
            action='staff.deleted',
            entity_type='membership',
            entity_id=str(membership_id),
            metadata={'username': staff_username}
        )

        return Response({'detail': 'Staff member removed successfully.'}, status=status.HTTP_200_OK)

# --- Sales ---

@api_view(['POST'])
@permission_classes([HasBusiness])
def complete_sale(request):
    serializer = TransactionSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data
    business = business_for(request)
    customer = Customer.objects.filter(id=data.get('customer'), business=business).first() if data.get('customer') else None
    try:
        sale = SalesService.complete(
            business=business,
            customer=customer,
            items=data['items'],
            amount_paid=data['amount_paid'],
            discount=data['discount'],
            client_transaction_id=data['client_transaction_id'],
            actor=request.user
        )
    except ValueError as error:
        return Response({'detail': str(error)}, status=status.HTTP_400_BAD_REQUEST)
    return Response({'id': sale.id, 'total': sale.total, 'amount_paid': sale.amount_paid, 'status': sale.status})

@api_view(['GET'])
@permission_classes([HasBusiness])
def sale_list(request):
    business = business_for(request)
    qs = Sale.objects.filter(business=business).select_related('customer').prefetch_related('items__product_unit__product', 'items__product_unit__unit').order_by('-completed_at')
    
    period = request.query_params.get('period')
    start_date = request.query_params.get('start_date')
    end_date = request.query_params.get('end_date')

    if period and period.lower() != 'all':
        start, end = _get_date_range(period.lower(), request)
        qs = qs.filter(completed_at__date__gte=start, completed_at__date__lte=end)
    else:
        if start_date:
            qs = qs.filter(completed_at__date__gte=start_date)
        if end_date:
            qs = qs.filter(completed_at__date__lte=end_date)

    return Response(SaleSerializer(qs[:200], many=True).data)

@api_view(['POST'])
@permission_classes([HasBusiness])
def reverse_sale(request, sale_id):
    require_role(request, 'owner', 'manager')
    business = business_for(request)
    sale = None
    if str(sale_id).isdigit():
        sale = Sale.objects.filter(id=int(sale_id), business=business).first()
    if not sale:
        sale = Sale.objects.filter(client_transaction_id=sale_id, business=business).first()
    if not sale:
        return Response({'detail': 'Sale not found.'}, status=status.HTTP_404_NOT_FOUND)
    SalesService.reverse(sale=sale, actor=request.user)
    return Response({'id': sale.id, 'client_transaction_id': str(sale.client_transaction_id), 'status': sale.status})

# --- Purchases ---

@api_view(['POST'])
@permission_classes([HasBusiness])
def complete_purchase(request):
    require_role(request, 'owner', 'manager')
    serializer = TransactionSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data
    business = business_for(request)
    supplier = Supplier.objects.filter(id=data.get('supplier'), business=business).first() if data.get('supplier') else None
    purchase = PurchaseService.complete(
        business=business,
        supplier=supplier,
        items=data['items'],
        amount_paid=data['amount_paid'],
        client_transaction_id=data['client_transaction_id'],
        actor=request.user,
        reference=data.get('reference', '')
    )
    return Response({'id': purchase.id, 'total': purchase.total})

@api_view(['GET'])
@permission_classes([HasBusiness])
def purchase_list(request):
    business = business_for(request)
    purchases = Purchase.objects.filter(business=business).select_related('supplier').prefetch_related('items__product_unit__product', 'items__product_unit__unit').order_by('-completed_at')[:100]
    return Response(PurchaseSerializer(purchases, many=True).data)

# --- Inventory Adjustments & Ledger ---

@api_view(['POST'])
@permission_classes([HasBusiness])
def stock_adjustment(request):
    require_role(request, 'owner', 'manager')
    serializer = StockAdjustmentSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data
    business = business_for(request)
    product = Product.objects.filter(id=data['product'], business=business).first()
    if not product:
        return Response({'detail': 'Product not found.'}, status=status.HTTP_404_NOT_FOUND)
    try:
        movement = InventoryService.adjust(
            business=business,
            product=product,
            quantity_delta=data['quantity_delta'],
            reason=data['reason'],
            actor=request.user,
            reference=data.get('reference', '')
        )
    except ValueError as error:
        return Response({'detail': str(error)}, status=status.HTTP_400_BAD_REQUEST)
    return Response({'id': movement.id, 'quantity_base': movement.quantity_base, 'reason': movement.reason}, status=status.HTTP_201_CREATED)

@api_view(['GET'])
@permission_classes([HasBusiness])
def inventory_movements(request):
    business = business_for(request)
    product_id = request.query_params.get('product')
    movements = InventoryMovement.objects.select_related('product', 'actor').filter(business=business)
    if product_id:
        movements = movements.filter(product_id=product_id)
    movements = movements.order_by('-created_at')[:200]
    return Response(InventoryMovementSerializer(movements, many=True).data)

# --- Debtors & Customer Payments ---

@api_view(['POST'])
@permission_classes([HasBusiness])
def record_customer_payment(request):
    serializer = CustomerPaymentSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data
    business = business_for(request)
    customer = Customer.objects.filter(id=data['customer'], business=business).first()
    if not customer:
        return Response({'detail': 'Customer not found.'}, status=status.HTTP_404_NOT_FOUND)
    try:
        payment = DebtService.record_payment(
            business=business,
            customer=customer,
            amount=data['amount'],
            method=data['method'],
            reference=data.get('reference', ''),
            actor=request.user
        )
    except ValueError as error:
        return Response({'detail': str(error)}, status=status.HTTP_400_BAD_REQUEST)
    return Response({'id': payment.id, 'amount': payment.amount})

@api_view(['GET'])
@permission_classes([HasBusiness])
def debtors(request):
    business = business_for(request)
    result = []
    for customer in Customer.objects.filter(business=business):
        due = sum((
            sale.total - sale.amount_paid - sum((alloc.amount for alloc in sale.customer_payment_allocations.all()), Decimal('0'))
            for sale in customer.sale_set.filter(status=Sale.Status.COMPLETED)
        ), Decimal('0'))
        if due > 0:
            result.append({
                'id': customer.id,
                'name': customer.name,
                'phone': customer.phone,
                'outstanding': float(due)
            })
    return Response(result)

# --- Dashboard & Reports ---

@api_view(['GET'])
@permission_classes([HasBusiness])
def dashboard(request):
    business = business_for(request)
    period = request.query_params.get('period', 'today').lower()
    start_date, end_date = _get_date_range(period, request)

    sales = Sale.objects.filter(
        business=business,
        completed_at__date__gte=start_date,
        completed_at__date__lte=end_date,
        status=Sale.Status.COMPLETED
    )
    revenue = float(sales.aggregate(value=Coalesce(Sum('total'), Decimal('0')))['value'])
    cogs = float(sales.aggregate(value=Coalesce(Sum('items__cogs'), Decimal('0')))['value'])
    gross_profit = revenue - cogs

    expenses = float(Expense.objects.filter(
        business=business,
        occurred_at__gte=start_date,
        occurred_at__lte=end_date
    ).aggregate(value=Coalesce(Sum('amount'), Decimal('0')))['value'])

    net_profit = gross_profit - expenses
    transaction_count = sales.count()

    # Stock metrics
    balances = InventoryBalance.objects.filter(product__business=business, product__active=True)
    low_stock = balances.filter(quantity_base__lte=F('product__reorder_level'), quantity_base__gt=0).count()
    out_of_stock = balances.filter(quantity_base__lte=0).count()
    stock_value = sum((float(b.quantity_base * b.average_cost) for b in balances), 0.0)

    # Debt metrics
    outstanding_debt = sum((
        float(sale.total - sale.amount_paid - sum((alloc.amount for alloc in sale.customer_payment_allocations.all()), Decimal('0')))
        for sale in Sale.objects.filter(business=business, status=Sale.Status.COMPLETED)
    ), 0.0)

    # Top selling products in the selected period
    top_items = SaleItem.objects.filter(
        sale__in=sales
    ).values(
        'product_unit__product__id',
        'product_unit__product__name'
    ).annotate(
        total_quantity=Sum('quantity'),
        total_sales=Sum(F('quantity') * F('unit_price'))
    ).order_by('-total_sales')[:5]

    top_products = [
        {
            'product_id': item['product_unit__product__id'],
            'product_name': item['product_unit__product__name'],
            'quantity': float(item['total_quantity']),
            'total_sales': float(item['total_sales'])
        }
        for item in top_items
    ]

    return Response({
        'currency': business.currency,
        'period': period,
        'start_date': start_date.isoformat(),
        'end_date': end_date.isoformat(),
        'today_sales': revenue,
        'gross_profit': gross_profit,
        'cogs': cogs,
        'expenses': expenses,
        'net_profit': net_profit,
        'transactions': transaction_count,
        'low_stock': low_stock,
        'out_of_stock': out_of_stock,
        'stock_value': stock_value,
        'outstanding_debt': max(0.0, outstanding_debt),
        'top_products': top_products
    })

@api_view(['GET'])
@permission_classes([HasBusiness])
def profit_loss_report(request):
    require_role(request, 'owner', 'manager')
    business = business_for(request)
    period = request.query_params.get('period', 'this_month').lower()
    start_date, end_date = _get_date_range(period, request)

    sales = Sale.objects.filter(
        business=business,
        completed_at__date__gte=start_date,
        completed_at__date__lte=end_date,
        status=Sale.Status.COMPLETED
    )
    revenue = float(sales.aggregate(value=Coalesce(Sum('total'), Decimal('0')))['value'])
    cogs = float(sales.aggregate(value=Coalesce(Sum('items__cogs'), Decimal('0')))['value'])
    gross_profit = revenue - cogs

    expense_qs = Expense.objects.filter(
        business=business,
        occurred_at__gte=start_date,
        occurred_at__lte=end_date
    )
    total_expenses = float(expense_qs.aggregate(value=Coalesce(Sum('amount'), Decimal('0')))['value'])

    # Breakdown by category
    expense_breakdown = list(expense_qs.values('category').annotate(total=Sum('amount')).order_by('-total'))
    for item in expense_breakdown:
        item['total'] = float(item['total'])

    return Response({
        'period': period,
        'start_date': start_date.isoformat(),
        'end_date': end_date.isoformat(),
        'currency': business.currency,
        'revenue': revenue,
        'cogs': cogs,
        'gross_profit': gross_profit,
        'operating_expenses': total_expenses,
        'net_profit': gross_profit - total_expenses,
        'expense_breakdown': expense_breakdown
    })

@api_view(['GET'])
@permission_classes([HasBusiness])
def sales_report(request):
    require_role(request, 'owner', 'manager')
    business = business_for(request)
    period = request.query_params.get('period', 'this_month').lower()
    start_date, end_date = _get_date_range(period, request)

    items = SaleItem.objects.select_related('sale', 'product_unit__product', 'product_unit__unit').filter(
        sale__business=business,
        sale__status=Sale.Status.COMPLETED,
        sale__completed_at__date__gte=start_date,
        sale__completed_at__date__lte=end_date
    ).order_by('-sale__completed_at')[:1000]

    return Response([
        {
            'sale_id': item.sale_id,
            'date': item.sale.completed_at,
            'product': item.product_unit.product.name,
            'unit': item.product_unit.unit.name,
            'quantity': float(item.quantity),
            'unit_price': float(item.unit_price),
            'revenue': float(item.quantity * item.unit_price),
            'cogs': float(item.cogs),
            'gross_profit': float(item.quantity * item.unit_price - item.cogs)
        }
        for item in items
    ])

@api_view(['GET'])
@permission_classes([HasBusiness])
def inventory_report(request):
    require_role(request, 'owner', 'manager')
    business = business_for(request)
    products = Product.objects.select_related('base_unit', 'inventory', 'category').filter(
        business=business, active=True
    ).order_by('name')

    return Response([
        {
            'id': p.id,
            'name': p.name,
            'category': p.category.name if p.category else 'Uncategorized',
            'unit': p.base_unit.name,
            'stock_base': float(p.inventory.quantity_base) if hasattr(p, 'inventory') else 0.0,
            'average_cost': float(p.inventory.average_cost) if hasattr(p, 'inventory') else 0.0,
            'stock_value': float(p.inventory.quantity_base * p.inventory.average_cost) if hasattr(p, 'inventory') else 0.0,
            'reorder_level': float(p.reorder_level),
            'is_low_stock': (p.inventory.quantity_base <= p.reorder_level) if hasattr(p, 'inventory') else True
        }
        for p in products
    ])

@api_view(['GET'])
@permission_classes([HasBusiness])
def export_report_csv(request):
    require_role(request, 'owner', 'manager')
    business = business_for(request)
    report_type = request.query_params.get('type', 'sales').lower()
    period = request.query_params.get('period', 'this_month').lower()
    start_date, end_date = _get_date_range(period, request)

    response = HttpResponse(content_type='text/csv')
    response['Content-Disposition'] = f'attachment; filename="krum_{report_type}_{period}.csv"'
    writer = csv.writer(response)

    if report_type == 'sales':
        writer.writerow(['Sale ID', 'Date', 'Product', 'Unit', 'Quantity', 'Unit Price', 'Revenue', 'COGS', 'Gross Profit'])
        items = SaleItem.objects.select_related('sale', 'product_unit__product', 'product_unit__unit').filter(
            sale__business=business,
            sale__status=Sale.Status.COMPLETED,
            sale__completed_at__date__gte=start_date,
            sale__completed_at__date__lte=end_date
        ).order_by('-sale__completed_at')
        for item in items:
            rev = item.quantity * item.unit_price
            writer.writerow([item.sale_id, item.sale.completed_at.strftime('%Y-%m-%d %H:%M'), item.product_unit.product.name, item.product_unit.unit.name, item.quantity, item.unit_price, rev, item.cogs, rev - item.cogs])

    elif report_type == 'inventory':
        writer.writerow(['Product ID', 'Name', 'Category', 'Base Unit', 'Stock Quantity', 'Average Cost', 'Total Stock Value', 'Reorder Level'])
        products = Product.objects.select_related('base_unit', 'inventory', 'category').filter(business=business, active=True).order_by('name')
        for p in products:
            inv = getattr(p, 'inventory', None)
            qty = inv.quantity_base if inv else 0
            cost = inv.average_cost if inv else 0
            writer.writerow([p.id, p.name, p.category.name if p.category else '', p.base_unit.name, qty, cost, qty * cost, p.reorder_level])

    elif report_type == 'debtors':
        writer.writerow(['Customer ID', 'Name', 'Phone', 'Outstanding Debt'])
        for customer in Customer.objects.filter(business=business):
            due = sum((sale.total - sale.amount_paid - sum((a.amount for a in sale.customer_payment_allocations.all()), Decimal('0')) for sale in customer.sale_set.filter(status=Sale.Status.COMPLETED)), Decimal('0'))
            if due > 0:
                writer.writerow([customer.id, customer.name, customer.phone, due])

    elif report_type == 'expenses':
        writer.writerow(['Expense ID', 'Date', 'Category', 'Amount', 'Description'])
        expenses = Expense.objects.filter(
            business=business,
            occurred_at__gte=start_date,
            occurred_at__lte=end_date
        ).order_by('-occurred_at', '-id')
        for exp in expenses:
            writer.writerow([exp.id, exp.occurred_at.strftime('%Y-%m-%d'), exp.category, exp.amount, exp.description])

    return response

# --- Cash Drawer & Shift Sessions ---

@api_view(['GET'])
@permission_classes([HasBusiness])
def current_cash_session(request):
    business = business_for(request)
    session = CashSession.objects.filter(
        business=business,
        user=request.user,
        status=CashSession.Status.OPEN
    ).first()

    if not session:
        return Response({'session': None})

    cash_sales = SalePayment.objects.filter(
        sale__business=business,
        sale__status=Sale.Status.COMPLETED,
        sale__completed_at__gte=session.opened_at,
        method='cash'
    ).aggregate(total=Coalesce(Sum('amount'), Decimal('0')))['total']

    other_sales = SalePayment.objects.filter(
        sale__business=business,
        sale__status=Sale.Status.COMPLETED,
        sale__completed_at__gte=session.opened_at,
    ).exclude(method='cash').aggregate(total=Coalesce(Sum('amount'), Decimal('0')))['total']

    cash_debt_payments = CustomerPayment.objects.filter(
        business=business,
        method='cash',
        created_at__gte=session.opened_at
    ).aggregate(total=Coalesce(Sum('amount'), Decimal('0')))['total']

    cash_expenses = Expense.objects.filter(
        business=business,
        created_at__gte=session.opened_at
    ).aggregate(total=Coalesce(Sum('amount'), Decimal('0')))['total']

    expected_cash = session.opening_float + cash_sales + cash_debt_payments - cash_expenses

    return Response({
        'session': {
            'id': session.id,
            'client_session_id': session.client_session_id,
            'user_id': session.user.id,
            'cashier_name': session.user.username,
            'opened_at': session.opened_at.isoformat(),
            'opening_float': float(session.opening_float),
            'opening_notes': session.opening_notes,
            'status': session.status,
            'cash_sales': float(cash_sales),
            'other_sales': float(other_sales),
            'total_sales': float(cash_sales + other_sales),
            'cash_debt_payments': float(cash_debt_payments),
            'cash_expenses': float(cash_expenses),
            'expected_cash': float(expected_cash),
        }
    })

@api_view(['POST'])
@permission_classes([HasBusiness])
def start_cash_session(request):
    business = business_for(request)
    existing = CashSession.objects.filter(
        business=business,
        user=request.user,
        status=CashSession.Status.OPEN
    ).first()
    if existing:
        return Response({'detail': 'An active shift session is already open for this user.'}, status=status.HTTP_400_BAD_REQUEST)

    opening_float = Decimal(str(request.data.get('opening_float') or '0'))
    opening_notes = (request.data.get('opening_notes') or '').strip()
    client_session_id = (request.data.get('client_session_id') or '').strip()

    session = CashSession.objects.create(
        business=business,
        user=request.user,
        opening_float=opening_float,
        opening_notes=opening_notes,
        client_session_id=client_session_id,
        status=CashSession.Status.OPEN
    )

    AuditLog.objects.create(
        business=business,
        actor=request.user,
        action='cash_session.started',
        entity_type='cash_session',
        entity_id=str(session.id),
        metadata={'opening_float': str(opening_float)}
    )

    return Response({
        'id': session.id,
        'client_session_id': session.client_session_id,
        'user_id': session.user.id,
        'cashier_name': session.user.username,
        'opened_at': session.opened_at.isoformat(),
        'opening_float': float(session.opening_float),
        'opening_notes': session.opening_notes,
        'status': session.status,
        'cash_sales': 0.0,
        'other_sales': 0.0,
        'total_sales': 0.0,
        'cash_debt_payments': 0.0,
        'cash_expenses': 0.0,
        'expected_cash': float(session.opening_float),
    }, status=status.HTTP_201_CREATED)

@api_view(['POST'])
@permission_classes([HasBusiness])
def close_cash_session(request, session_id):
    business = business_for(request)
    session = CashSession.objects.filter(
        Q(id__exact=session_id if str(session_id).isdigit() else -1) | Q(client_session_id=session_id),
        business=business
    ).first()

    if not session:
        return Response({'detail': 'Cash session not found.'}, status=status.HTTP_404_NOT_FOUND)

    if session.status == CashSession.Status.CLOSED:
        return Response({'detail': 'This cash session is already closed.'}, status=status.HTTP_400_BAD_REQUEST)

    if 'closing_cash_actual' not in request.data:
        return Response({'detail': 'Actual counted cash amount is required to close shift.'}, status=status.HTTP_400_BAD_REQUEST)

    closing_cash_actual = Decimal(str(request.data['closing_cash_actual']))
    closing_notes = (request.data.get('closing_notes') or '').strip()

    cash_sales = SalePayment.objects.filter(
        sale__business=business,
        sale__status=Sale.Status.COMPLETED,
        sale__completed_at__gte=session.opened_at,
        method='cash'
    ).aggregate(total=Coalesce(Sum('amount'), Decimal('0')))['total']

    other_sales = SalePayment.objects.filter(
        sale__business=business,
        sale__status=Sale.Status.COMPLETED,
        sale__completed_at__gte=session.opened_at,
    ).exclude(method='cash').aggregate(total=Coalesce(Sum('amount'), Decimal('0')))['total']

    cash_debt_payments = CustomerPayment.objects.filter(
        business=business,
        method='cash',
        created_at__gte=session.opened_at
    ).aggregate(total=Coalesce(Sum('amount'), Decimal('0')))['total']

    cash_expenses = Expense.objects.filter(
        business=business,
        created_at__gte=session.opened_at
    ).aggregate(total=Coalesce(Sum('amount'), Decimal('0')))['total']

    expected_cash = session.opening_float + cash_sales + cash_debt_payments - cash_expenses
    difference = closing_cash_actual - expected_cash

    session.cash_sales = cash_sales
    session.cash_debt_payments = cash_debt_payments
    session.cash_expenses = cash_expenses
    session.expected_cash = expected_cash
    session.closing_cash_actual = closing_cash_actual
    session.difference = difference
    session.closed_at = timezone.now()
    session.status = CashSession.Status.CLOSED
    session.closing_notes = closing_notes
    session.save()

    AuditLog.objects.create(
        business=business,
        actor=request.user,
        action='cash_session.closed',
        entity_type='cash_session',
        entity_id=str(session.id),
        metadata={
            'expected_cash': str(expected_cash),
            'closing_cash_actual': str(closing_cash_actual),
            'difference': str(difference),
        }
    )

    return Response({
        'id': session.id,
        'client_session_id': session.client_session_id,
        'user_id': session.user.id,
        'cashier_name': session.user.username,
        'opened_at': session.opened_at.isoformat(),
        'closed_at': session.closed_at.isoformat(),
        'opening_float': float(session.opening_float),
        'cash_sales': float(session.cash_sales),
        'other_sales': float(other_sales),
        'total_sales': float(cash_sales + other_sales),
        'cash_debt_payments': float(session.cash_debt_payments),
        'cash_expenses': float(session.cash_expenses),
        'expected_cash': float(session.expected_cash),
        'closing_cash_actual': float(session.closing_cash_actual),
        'difference': float(session.difference),
        'status': session.status,
        'opening_notes': session.opening_notes,
        'closing_notes': session.closing_notes,
    })

@api_view(['GET'])
@permission_classes([HasBusiness])
def list_cash_sessions(request):
    business = business_for(request)
    sessions = CashSession.objects.filter(business=business).select_related('user').order_by('-opened_at')[:50]
    data = [
        {
            'id': s.id,
            'client_session_id': s.client_session_id,
            'user_id': s.user.id,
            'cashier_name': s.user.username,
            'opened_at': s.opened_at.isoformat(),
            'closed_at': s.closed_at.isoformat() if s.closed_at else None,
            'opening_float': float(s.opening_float),
            'cash_sales': float(s.cash_sales),
            'cash_debt_payments': float(s.cash_debt_payments),
            'cash_expenses': float(s.cash_expenses),
            'expected_cash': float(s.expected_cash),
            'closing_cash_actual': float(s.closing_cash_actual) if s.closing_cash_actual is not None else None,
            'difference': float(s.difference),
            'status': s.status,
            'opening_notes': s.opening_notes,
            'closing_notes': s.closing_notes,
        }
        for s in sessions
    ]
    return Response(data)

