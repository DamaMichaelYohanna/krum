import os
from pathlib import Path
from django.conf import settings
from django.db import connection
from django.http import FileResponse, HttpResponseRedirect, JsonResponse
from django.shortcuts import render
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from apps.core.models import ContactInquiry

API_ENDPOINTS_CATALOG = [
    {
        "category": "Authentication & Business",
        "method": "POST",
        "path": "/api/auth/login/",
        "auth": "Public",
        "desc": "Obtain JWT access & refresh tokens using username and password"
    },
    {
        "category": "Authentication & Business",
        "method": "POST",
        "path": "/api/auth/refresh/",
        "auth": "Public",
        "desc": "Refresh expired JWT access token"
    },
    {
        "category": "Authentication & Business",
        "method": "POST",
        "path": "/api/auth/register/",
        "auth": "Public",
        "desc": "Create a new store owner account & business profile"
    },
    {
        "category": "Authentication & Business",
        "method": "GET",
        "path": "/api/business/me/",
        "auth": "Bearer JWT",
        "desc": "Retrieve store profile, currency, timezone, and business settings"
    },
    {
        "category": "Authentication & Business",
        "method": "GET",
        "path": "/api/staff/",
        "auth": "Bearer JWT (Owner/Manager)",
        "desc": "List staff members, cashiers, roles, and access permissions"
    },
    {
        "category": "Sync Engine (Offline First)",
        "method": "GET",
        "path": "/api/sync/pull/",
        "auth": "Bearer JWT",
        "desc": "Delta pull of products, units, categories, sales, customers, and suppliers updated since last sync"
    },
    {
        "category": "Sync Engine (Offline First)",
        "method": "POST",
        "path": "/api/sync/push/",
        "auth": "Bearer JWT",
        "desc": "Batch push offline sales, payments, expenses, and inventory adjustments to cloud"
    },
    {
        "category": "Catalog & Inventory",
        "method": "GET",
        "path": "/api/products/",
        "auth": "Bearer JWT",
        "desc": "List all products with stock counts, unit pricing, barcodes, and preferred suppliers"
    },
    {
        "category": "Catalog & Inventory",
        "method": "GET",
        "path": "/api/products/barcode/<barcode>/",
        "auth": "Bearer JWT",
        "desc": "Instant product lookup for barcode scanner during checkout"
    },
    {
        "category": "Catalog & Inventory",
        "method": "GET",
        "path": "/api/inventory/low-stock/",
        "auth": "Bearer JWT",
        "desc": "Restock hub: items at or below reorder level, deficit calculation, and suggested supplier orders"
    },
    {
        "category": "Catalog & Inventory",
        "method": "POST",
        "path": "/api/inventory/adjustments/",
        "auth": "Bearer JWT",
        "desc": "Record stock loss, damage, recount, or shrinkage adjustments"
    },
    {
        "category": "Point of Sale (POS)",
        "method": "GET",
        "path": "/api/sales/",
        "auth": "Bearer JWT",
        "desc": "List sales history with itemized line items, payment methods, and timestamps"
    },
    {
        "category": "Point of Sale (POS)",
        "method": "POST",
        "path": "/api/sales/complete/",
        "auth": "Bearer JWT",
        "desc": "Checkout sale: deduct stock, apply unit conversion, record cash/transfer/POS, and update customer debt"
    },
    {
        "category": "Point of Sale (POS)",
        "method": "POST",
        "path": "/api/sales/<sale_id>/reverse/",
        "auth": "Bearer JWT (Manager)",
        "desc": "Void receipt, restore inventory stock, and reverse customer debt safely"
    },
    {
        "category": "Purchasing & Restock",
        "method": "GET",
        "path": "/api/suppliers/",
        "auth": "Bearer JWT",
        "desc": "List suppliers with contact numbers and purchase history"
    },
    {
        "category": "Purchasing & Restock",
        "method": "POST",
        "path": "/api/purchases/complete/",
        "auth": "Bearer JWT",
        "desc": "Receive supplier restock into inventory with weighted-average cost price recalculation"
    },
    {
        "category": "Customers & Debt Ledger",
        "method": "GET",
        "path": "/api/customers/debtors/",
        "auth": "Bearer JWT",
        "desc": "List customers with outstanding credit balances"
    },
    {
        "category": "Customers & Debt Ledger",
        "method": "POST",
        "path": "/api/customer-payments/",
        "auth": "Bearer JWT",
        "desc": "Record debt repayment with automated receipt & statement update"
    },
    {
        "category": "Finance & Cash Drawer",
        "method": "GET",
        "path": "/api/cash-sessions/current/",
        "auth": "Bearer JWT",
        "desc": "Get live cashier till metrics: opening float, cash sales, cash-in/out, expected in till"
    },
    {
        "category": "Finance & Cash Drawer",
        "method": "POST",
        "path": "/api/cash-sessions/start/",
        "auth": "Bearer JWT",
        "desc": "Open a new cashier shift session with starting drawer float"
    },
    {
        "category": "Finance & Cash Drawer",
        "method": "POST",
        "path": "/api/cash-sessions/<session_id>/close/",
        "auth": "Bearer JWT",
        "desc": "Reconcile counted cash, record variance discrepancy reason, and close shift"
    },
    {
        "category": "Reporting & Analytics",
        "method": "GET",
        "path": "/api/dashboard/",
        "auth": "Bearer JWT",
        "desc": "KPI overview: revenue, net profit, transaction count, low-stock count, and recent sales"
    },
    {
        "category": "Reporting & Analytics",
        "method": "GET",
        "path": "/api/reports/profit-loss/",
        "auth": "Bearer JWT",
        "desc": "Periodic P&L statement (sales, COGS, gross profit, operating expenses, net profit)"
    },
    {
        "category": "Reporting & Analytics",
        "method": "GET",
        "path": "/api/reports/export/?type=all",
        "auth": "Bearer JWT",
        "desc": "Export business data in CSV spreadsheet format"
    }
]


def check_db_health():
    try:
        connection.ensure_connection()
        return True, "connected"
    except Exception as e:
        return False, str(e)


@api_view(['GET'])
@permission_classes([AllowAny])
def health_check(request):
    """Health check endpoint for Vercel, monitors, and uptime probes."""
    db_ok, db_msg = check_db_health()
    status_code = 200 if db_ok else 503
    return Response({
        "status": "healthy" if db_ok else "degraded",
        "database": db_msg,
        "timestamp": timezone.now().isoformat(),
        "app": "Krum POS & Cloud Sync API",
        "version": "1.0.0",
        "environment": "production" if not settings.DEBUG else "development",
    }, status=status_code)


@api_view(['GET'])
@permission_classes([AllowAny])
def api_root(request):
    """API index returning all available endpoint routes and system status."""
    db_ok, _ = check_db_health()
    return Response({
        "name": "Krum Cloud API",
        "status": "operational" if db_ok else "maintenance",
        "version": "1.0.0",
        "description": "Enterprise POS, Multi-Unit Inventory, Restock Hub, and Offline Sync Engine",
        "documentation": "/",
        "health_check": "/health/",
        "admin_portal": "/admin/",
        "apk_download": "/download/krum.apk",
        "endpoints_count": len(API_ENDPOINTS_CATALOG),
        "endpoints": API_ENDPOINTS_CATALOG,
    })


def download_apk(request):
    """Direct download for the compiled Android release APK."""
    candidate_paths = [
        settings.BASE_DIR.parent / 'krum.apk',
        settings.BASE_DIR / 'krum.apk',
        settings.BASE_DIR / 'static' / 'krum.apk',
    ]

    for path in candidate_paths:
        if path.exists() and path.is_file():
            response = FileResponse(
                open(path, 'rb'),
                as_attachment=True,
                filename='krum.apk',
                content_type='application/vnd.android.package-archive'
            )
            response['Content-Length'] = path.stat().st_size
            return response

    # Fallback to direct raw download from GitHub main branch
    return HttpResponseRedirect("https://github.com/DamaMichaelYohanna/krum/raw/main/krum.apk")


def landing_page(request):
    """
    Rich modern landing page for Krum when visited via browser,
    or JSON status if requested via API client.
    """
    accept = request.headers.get('Accept', '')
    if 'application/json' in accept or request.GET.get('format') == 'json':
        return api_root(request)

    db_ok, db_msg = check_db_health()
    return render(request, 'landing.html', {
        'db_ok': db_ok,
        'db_msg': db_msg,
    })


def about_page(request):
    """About the Product page."""
    return render(request, 'about.html')


def pricing_page(request):
    """Pricing and plans comparison page."""
    return render(request, 'pricing.html')


def contact_page(request):
    """
    Contact us page with form submission handling and database persistence.
    """
    if request.method == 'POST':
        name = request.POST.get('name', '').strip()
        email = request.POST.get('email', '').strip()
        phone = request.POST.get('phone', '').strip()
        store_name = request.POST.get('store_name', '').strip()
        subject = request.POST.get('subject', 'General Inquiry').strip()
        message = request.POST.get('message', '').strip()

        if name and email and message:
            inquiry = ContactInquiry.objects.create(
                name=name,
                email=email,
                phone=phone,
                store_name=store_name,
                subject=subject,
                message=message,
            )
            ticket_id = f"KRM-INQ-{inquiry.id:04d}"

            if 'application/json' in request.headers.get('Accept', ''):
                return JsonResponse({
                    'status': 'success',
                    'ticket_id': ticket_id,
                    'message': 'Your inquiry has been received. Our team will contact you shortly.'
                })

            return render(request, 'contact.html', {
                'success_message': True,
                'ticket_id': ticket_id,
                'form_data': {},
            })
        else:
            return render(request, 'contact.html', {
                'error': 'Please provide your name, email, and message.',
                'form_data': request.POST,
            })

    return render(request, 'contact.html', {'form_data': {}})


def privacy_page(request):
    """Privacy Policy page."""
    return render(request, 'privacy.html')


def terms_page(request):
    """Terms and Conditions of Service page."""
    return render(request, 'terms.html')
