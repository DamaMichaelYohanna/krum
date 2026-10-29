"""
Krum Store Administrative Dashboard
Web-based management portal for store owners, managers, and administrators.
"""

import csv
from datetime import datetime, time, timedelta
from decimal import Decimal

from django.conf import settings
from django.contrib import messages
from django.contrib.auth import authenticate, login, logout
from django.contrib.auth.decorators import login_required
from django.core.paginator import Paginator
from django.db.models import DecimalField, F, Q, Sum
from django.db.models.functions import Coalesce
from django.http import HttpResponse, HttpResponseForbidden
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone

from apps.catalog.models import Category, Product, ProductUnit, Unit
from apps.core.models import Business, Membership
from apps.customers.models import Customer, CustomerPayment
from apps.finance.models import CashSession, Expense
from apps.inventory.models import InventoryBalance, InventoryMovement
from apps.sales.models import Sale, SaleItem, SalePayment


# --- Helper Decorator & Multi-Tenant Context ---

def get_user_business_context(request):
    """
    Resolves the active business and user role for the authenticated user.
    Supports multi-store switching via session variable.
    """
    user = request.user
    if not user.is_authenticated:
        return None, None, []

    # Get all memberships for the user
    memberships = Membership.objects.filter(user=user).select_related('business')
    user_businesses = [m.business for m in memberships]

    active_business = None
    role = 'sales'

    # Check if a specific store is selected in the session
    session_business_id = request.session.get('active_business_id')
    if session_business_id:
        active_business = next((b for b in user_businesses if str(b.id) == str(session_business_id)), None)

    if not active_business and user_businesses:
        active_business = user_businesses[0]

    # For superusers without memberships, provision or use any available business
    if not active_business and user.is_superuser:
        all_businesses = list(Business.objects.all())
        if all_businesses:
            if session_business_id:
                active_business = next((b for b in all_businesses if str(b.id) == str(session_business_id)), all_businesses[0])
            else:
                active_business = all_businesses[0]
            user_businesses = all_businesses
            role = 'owner'
        else:
            # Provision a default store for superusers if DB is blank
            active_business = Business.objects.create(
                name="Krum Flagship Supermarket",
                currency="NGN",
                phone="+234 800 000 0000"
            )
            Membership.objects.create(business=active_business, user=user, role=Membership.Role.OWNER)
            user_businesses = [active_business]
            role = 'owner'

    if active_business:
        request.session['active_business_id'] = str(active_business.id)
        if not user.is_superuser:
            membership = next((m for m in memberships if m.business_id == active_business.id), None)
            if membership:
                role = membership.role

    return active_business, role, user_businesses


def store_admin_required(view_func):
    """
    Ensures user is logged in and associated with a business before accessing the dashboard.
    """
    def wrapper(request, *args, **kwargs):
        if not request.user.is_authenticated:
            return redirect(f'/dashboard/login/?next={request.path}')

        business, role, businesses = get_user_business_context(request)
        if not business:
            return render(request, 'dashboard/no_store.html', {
                'user': request.user
            })

        request.business = business
        request.user_role = role
        request.user_businesses = businesses
        return view_func(request, *args, **kwargs)

    wrapper.__name__ = view_func.__name__
    wrapper.__doc__ = view_func.__doc__
    return wrapper


def _get_period_date_range(period):
    """
    Returns start_date and end_date datetimes for the requested period.
    """
    now = timezone.now()
    today_start = timezone.make_aware(datetime.combine(now.date(), time.min))
    today_end = timezone.make_aware(datetime.combine(now.date(), time.max))

    if period == 'yesterday':
        yesterday = now.date() - timedelta(days=1)
        return (
            timezone.make_aware(datetime.combine(yesterday, time.min)),
            timezone.make_aware(datetime.combine(yesterday, time.max))
        )
    elif period == 'week':
        start = today_start - timedelta(days=7)
        return start, today_end
    elif period == 'month':
        start = today_start.replace(day=1)
        return start, today_end
    elif period == 'all':
        return None, None
    else:  # default 'today'
        return today_start, today_end


# --- Authentication Views ---

def dashboard_login(request):
    """
    Branded login screen for store merchants and cashiers.
    """
    if request.user.is_authenticated:
        return redirect('/dashboard/')

    next_url = request.GET.get('next', '/dashboard/')
    error = None

    if request.method == 'POST':
        identifier = request.POST.get('username', '').strip()
        password = request.POST.get('password', '').strip()

        user = authenticate(request, username=identifier, password=password)
        if user is not None:
            login(request, user)
            return redirect(next_url)
        else:
            error = "Invalid username or password. Please verify your merchant credentials."

    return render(request, 'dashboard/login.html', {
        'error': error,
        'next_url': next_url
    })


def dashboard_logout(request):
    """
    Logs out the merchant and clears store session.
    """
    logout(request)
    return redirect('/dashboard/login/')


def switch_store(request, business_id):
    """
    Switches active store for owners managing multi-location stores.
    """
    if not request.user.is_authenticated:
        return redirect('/dashboard/login/')

    request.session['active_business_id'] = str(business_id)
    messages.success(request, "Switched active store.")
    return redirect('/dashboard/')


# --- Dashboard Pages ---

@store_admin_required
def dashboard_overview(request):
    """
    Executive overview with real-time sales KPIs, stock alerts, till status, and recent activity.
    """
    business = request.business
    period = request.GET.get('period', 'today').lower()
    start_date, end_date = _get_period_date_range(period)

    # Base query for completed sales
    sales_qs = Sale.objects.filter(business=business, status=Sale.Status.COMPLETED)
    if start_date and end_date:
        sales_qs = sales_qs.filter(completed_at__gte=start_date, completed_at__lte=end_date)

    # Aggregated Financial Metrics
    revenue = sales_qs.aggregate(val=Coalesce(Sum('total'), Decimal('0')))['val']
    cogs = sales_qs.aggregate(val=Coalesce(Sum('items__cogs'), Decimal('0')))['val']
    gross_profit = revenue - cogs
    gross_margin = (gross_profit / revenue * 100) if revenue > 0 else Decimal('0')

    # Expenses in period
    expenses_qs = Expense.objects.filter(business=business)
    if start_date and end_date:
        expenses_qs = expenses_qs.filter(occurred_at__gte=start_date.date(), occurred_at__lte=end_date.date())
    total_expenses = expenses_qs.aggregate(val=Coalesce(Sum('amount'), Decimal('0')))['val']
    net_profit = gross_profit - total_expenses

    transaction_count = sales_qs.count()
    average_basket = (revenue / transaction_count) if transaction_count > 0 else Decimal('0')

    # Cash in Active Till Sessions
    open_sessions = CashSession.objects.filter(business=business, status=CashSession.Status.OPEN)
    drawer_cash = open_sessions.aggregate(val=Coalesce(Sum('expected_cash'), Decimal('0')))['val']

    # Outstanding Customer Debt
    all_completed_sales = Sale.objects.filter(business=business, status=Sale.Status.COMPLETED)
    outstanding_debt = sum((
        float(s.total - s.amount_paid - sum((alloc.amount for alloc in s.customer_payment_allocations.all()), Decimal('0')))
        for s in all_completed_sales
    ), 0.0)

    # Inventory Metrics
    inventory_qs = InventoryBalance.objects.filter(product__business=business, product__active=True).select_related('product')
    low_stock_products = []
    out_of_stock_count = 0
    total_stock_value = Decimal('0')

    for bal in inventory_qs:
        total_stock_value += (bal.quantity_base * bal.average_cost)
        if bal.quantity_base <= 0:
            out_of_stock_count += 1
        elif bal.quantity_base <= bal.product.reorder_level:
            low_stock_products.append(bal)

    low_stock_count = len(low_stock_products)

    # Sales by Payment Method
    payment_breakdown = {}
    sales_in_period_ids = list(sales_qs.values_list('id', flat=True))
    if sales_in_period_ids:
        payments = SalePayment.objects.filter(sale_id__in=sales_in_period_ids).values('method').annotate(total_amount=Sum('amount'))
        for p in payments:
            method_key = p['method'].capitalize()
            payment_breakdown[method_key] = float(p['total_amount'])

    # Recent Transactions
    recent_sales = sales_qs.select_related('customer').prefetch_related('payments', 'items__product_unit__unit', 'items__product_unit__product').order_by('-completed_at')[:8]

    # Top Selling Products in Period
    top_items = SaleItem.objects.filter(sale__in=sales_qs).values(
        'product_unit__product__name', 'product_unit__unit__name'
    ).annotate(
        qty_sold=Sum('quantity'),
        total_rev=Sum(F('quantity') * F('unit_price'), output_field=DecimalField(max_digits=14, decimal_places=2))
    ).order_by('-qty_sold')[:5]

    context = {
        'active_tab': 'overview',
        'business': business,
        'user_role': request.user_role,
        'user_businesses': request.user_businesses,
        'period': period,
        'revenue': revenue,
        'gross_profit': gross_profit,
        'gross_margin': round(gross_margin, 1),
        'total_expenses': total_expenses,
        'net_profit': net_profit,
        'transaction_count': transaction_count,
        'average_basket': average_basket,
        'drawer_cash': drawer_cash,
        'open_sessions_count': open_sessions.count(),
        'outstanding_debt': round(Decimal(str(outstanding_debt)), 2),
        'low_stock_count': low_stock_count,
        'out_of_stock_count': out_of_stock_count,
        'total_stock_value': total_stock_value,
        'low_stock_products': low_stock_products[:5],
        'payment_breakdown': payment_breakdown,
        'recent_sales': recent_sales,
        'top_items': top_items,
    }
    return render(request, 'dashboard/overview.html', context)


@store_admin_required
def dashboard_sales(request):
    """
    Comprehensive sales receipt log with search, filters, item breakdown, and CSV export.
    """
    business = request.business
    period = request.GET.get('period', 'all').lower()
    method = request.GET.get('method', 'all').lower()
    query = request.GET.get('q', '').strip()

    sales_qs = Sale.objects.filter(business=business).select_related('customer').prefetch_related('payments', 'items__product_unit__unit', 'items__product_unit__product').order_by('-completed_at')

    # Date Filter
    if period != 'all':
        start_date, end_date = _get_period_date_range(period)
        if start_date and end_date:
            sales_qs = sales_qs.filter(completed_at__gte=start_date, completed_at__lte=end_date)

    # Payment Method Filter
    if method != 'all':
        sales_qs = sales_qs.filter(payments__method__iexact=method).distinct()

    # Text Search (Transaction ID or Customer Name)
    if query:
        sales_qs = sales_qs.filter(
            Q(client_transaction_id__icontains=query) |
            Q(customer__name__icontains=query)
        )

    # Check if CSV export requested
    if request.GET.get('export') == 'csv':
        response = HttpResponse(content_type='text/csv')
        response['Content-Disposition'] = f'attachment; filename="krum_sales_{business.name.lower().replace(" ", "_")}.csv"'
        writer = csv.writer(response)
        writer.writerow(['Receipt Reference', 'Completed At', 'Customer', 'Items Count', 'Subtotal', 'Discount', 'Total', 'Status', 'Payment Methods'])
        for s in sales_qs:
            methods = ", ".join([p.method for p in s.payments.all()])
            customer_name = s.customer.name if s.customer else "Walk-in Customer"
            writer.writerow([
                str(s.client_transaction_id)[:8].upper(),
                s.completed_at.strftime("%Y-%m-%d %H:%M:%S") if s.completed_at else "",
                customer_name,
                s.items.count(),
                s.subtotal,
                s.discount,
                s.total,
                s.status,
                methods
            ])
        return response

    paginator = Paginator(sales_qs, 20)
    page_number = request.GET.get('page', 1)
    page_obj = paginator.get_page(page_number)

    context = {
        'active_tab': 'sales',
        'business': business,
        'user_role': request.user_role,
        'user_businesses': request.user_businesses,
        'page_obj': page_obj,
        'period': period,
        'method': method,
        'query': query,
        'total_count': sales_qs.count(),
    }
    return render(request, 'dashboard/sales.html', context)


@store_admin_required
def dashboard_inventory(request):
    """
    Inventory and product management table with multi-unit packaging, stock health, and valuation.
    """
    business = request.business
    category_id = request.GET.get('category', 'all')
    stock_status = request.GET.get('status', 'all')
    query = request.GET.get('q', '').strip()

    products_qs = Product.objects.filter(business=business, active=True).select_related('category', 'base_unit', 'inventory').prefetch_related('units__unit').order_by('name')

    if category_id != 'all':
        products_qs = products_qs.filter(category_id=category_id)

    if query:
        products_qs = products_qs.filter(
            Q(name__icontains=query) |
            Q(barcode__icontains=query) |
            Q(sku__icontains=query)
        )

    # Post-filter on stock status if requested
    items = []
    total_valuation = Decimal('0')
    low_stock_count = 0
    out_of_stock_count = 0

    for p in products_qs:
        qty = p.inventory.quantity_base if hasattr(p, 'inventory') else Decimal('0')
        cost = p.inventory.average_cost if hasattr(p, 'inventory') else Decimal('0')
        val = qty * cost
        total_valuation += val

        status = 'in_stock'
        if qty <= 0:
            status = 'out_of_stock'
            out_of_stock_count += 1
        elif qty <= p.reorder_level:
            status = 'low_stock'
            low_stock_count += 1

        if stock_status == 'all' or stock_status == status:
            items.append({
                'product': p,
                'quantity': qty,
                'average_cost': cost,
                'valuation': val,
                'status': status,
                'units': p.units.all()
            })

    categories = Category.objects.filter(business=business).order_by('name')

    context = {
        'active_tab': 'inventory',
        'business': business,
        'user_role': request.user_role,
        'user_businesses': request.user_businesses,
        'items': items,
        'categories': categories,
        'selected_category': category_id,
        'selected_status': stock_status,
        'query': query,
        'total_count': len(items),
        'total_valuation': total_valuation,
        'low_stock_count': low_stock_count,
        'out_of_stock_count': out_of_stock_count,
    }
    return render(request, 'dashboard/inventory.html', context)


@store_admin_required
def dashboard_shifts(request):
    """
    Cash drawer session and till auditing with float, actual count, and over/short variance.
    """
    business = request.business
    status_filter = request.GET.get('status', 'all')

    sessions_qs = CashSession.objects.filter(business=business).select_related('user').order_by('-opened_at')
    if status_filter != 'all':
        sessions_qs = sessions_qs.filter(status=status_filter)

    open_sessions = CashSession.objects.filter(business=business, status=CashSession.Status.OPEN)
    total_open_float = open_sessions.aggregate(val=Coalesce(Sum('opening_float'), Decimal('0')))['val']
    total_open_cash = open_sessions.aggregate(val=Coalesce(Sum('expected_cash'), Decimal('0')))['val']

    context = {
        'active_tab': 'shifts',
        'business': business,
        'user_role': request.user_role,
        'user_businesses': request.user_businesses,
        'sessions': sessions_qs[:50],
        'status_filter': status_filter,
        'open_sessions_count': open_sessions.count(),
        'total_open_float': total_open_float,
        'total_open_cash': total_open_cash,
    }
    return render(request, 'dashboard/shifts.html', context)


@store_admin_required
def dashboard_customers(request):
    """
    Customer credit accounts, outstanding receivables, and payment history.
    """
    business = request.business
    query = request.GET.get('q', '').strip()

    customers_qs = Customer.objects.filter(business=business).prefetch_related('payments').order_by('name')
    if query:
        customers_qs = customers_qs.filter(
            Q(name__icontains=query) |
            Q(phone__icontains=query)
        )

    customer_list = []
    total_receivables = Decimal('0')

    for cust in customers_qs:
        # Calculate balance: total credit purchases - payments
        sales = Sale.objects.filter(customer=cust, business=business, status=Sale.Status.COMPLETED)
        total_purchases = sales.aggregate(val=Coalesce(Sum('total'), Decimal('0')))['val']
        total_paid_at_sale = sales.aggregate(val=Coalesce(Sum('amount_paid'), Decimal('0')))['val']
        
        # Debt payments recorded
        direct_payments = CustomerPayment.objects.filter(customer=cust, business=business).aggregate(val=Coalesce(Sum('amount'), Decimal('0')))['val']
        
        balance = total_purchases - (total_paid_at_sale + direct_payments)
        if balance > 0:
            total_receivables += balance

        customer_list.append({
            'customer': cust,
            'total_purchases': total_purchases,
            'total_paid': total_paid_at_sale + direct_payments,
            'balance': balance,
            'orders_count': sales.count(),
        })

    context = {
        'active_tab': 'customers',
        'business': business,
        'user_role': request.user_role,
        'user_businesses': request.user_businesses,
        'customer_list': customer_list,
        'total_receivables': total_receivables,
        'query': query,
    }
    return render(request, 'dashboard/customers.html', context)


@store_admin_required
def dashboard_staff(request):
    """
    Staff management and membership role permissions.
    """
    business = request.business
    memberships = Membership.objects.filter(business=business).select_related('user').order_by('role')

    context = {
        'active_tab': 'staff',
        'business': business,
        'user_role': request.user_role,
        'user_businesses': request.user_businesses,
        'memberships': memberships,
    }
    return render(request, 'dashboard/staff.html', context)


@store_admin_required
def dashboard_settings(request):
    """
    Store business profile and operational configurations.
    """
    business = request.business

    if request.method == 'POST' and request.user_role in ['owner', 'manager']:
        name = request.POST.get('name', '').strip()
        phone = request.POST.get('phone', '').strip()
        currency = request.POST.get('currency', 'NGN').strip().upper()

        if name:
            business.name = name
            business.phone = phone
            business.currency = currency
            business.save()
            messages.success(request, "Store configuration saved successfully.")
            return redirect('/dashboard/settings/')

    context = {
        'active_tab': 'settings',
        'business': business,
        'user_role': request.user_role,
        'user_businesses': request.user_businesses,
    }
    return render(request, 'dashboard/settings.html', context)
