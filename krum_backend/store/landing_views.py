import os
from pathlib import Path
from django.conf import settings
from django.db import connection
from django.http import FileResponse, HttpResponse, HttpResponseRedirect, JsonResponse
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

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
    now_wat = timezone.now().strftime("%Y-%m-%d %H:%M:%S UTC")

    # Render a modern, responsive, high-performance HTML landing page
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Krum — Smart POS & Cloud Inventory Management</title>
    <meta name="description" content="Next-generation offline-first Point of Sale, multi-unit inventory engine, restock management, and cloud sync for supermarkets and retail stores.">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800&family=Plus+Jakarta+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
    <style>
        :root {{
            --bg-primary: #07090E;
            --bg-secondary: #0D131F;
            --bg-card: rgba(18, 26, 43, 0.7);
            --bg-card-hover: rgba(26, 38, 64, 0.85);
            --border: rgba(255, 255, 255, 0.08);
            --border-highlight: rgba(99, 102, 241, 0.4);
            --primary: #4F46E5;
            --primary-light: #6366F1;
            --accent-cyan: #06B6D4;
            --accent-emerald: #10B981;
            --accent-amber: #F59E0B;
            --accent-rose: #F43F5E;
            --text-main: #F8FAFC;
            --text-muted: #94A3B8;
            --text-dim: #64748B;
            --glow: rgba(99, 102, 241, 0.18);
        }}

        * {{
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }}

        body {{
            background-color: var(--bg-primary);
            color: var(--text-main);
            font-family: 'Plus Jakarta Sans', sans-serif;
            line-height: 1.6;
            overflow-x: hidden;
            background-image: 
                radial-gradient(circle at 15% 20%, rgba(99, 102, 241, 0.15) 0%, transparent 45%),
                radial-gradient(circle at 85% 65%, rgba(6, 182, 212, 0.12) 0%, transparent 40%),
                radial-gradient(circle at 50% 90%, rgba(16, 185, 129, 0.10) 0%, transparent 50%);
            min-height: 100vh;
        }}

        /* Subtle grid background */
        body::before {{
            content: '';
            position: fixed;
            top: 0; left: 0; right: 0; bottom: 0;
            background-size: 40px 40px;
            background-image: 
                linear-gradient(to right, rgba(255, 255, 255, 0.02) 1px, transparent 1px),
                linear-gradient(to bottom, rgba(255, 255, 255, 0.02) 1px, transparent 1px);
            pointer-events: none;
            z-index: 0;
        }}

        .container {{
            max-width: 1200px;
            margin: 0 auto;
            padding: 0 24px;
            position: relative;
            z-index: 1;
        }}

        /* Header / Nav */
        header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 24px 0;
            border-bottom: 1px solid var(--border);
        }}

        .brand {{
            display: flex;
            align-items: center;
            gap: 12px;
            text-decoration: none;
        }}

        .logo-icon {{
            width: 42px;
            height: 42px;
            background: linear-gradient(135deg, #4F46E5, #06B6D4);
            border-radius: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-family: 'Outfit', sans-serif;
            font-weight: 800;
            font-size: 22px;
            color: #FFFFFF;
            box-shadow: 0 0 20px rgba(99, 102, 241, 0.4);
        }}

        .brand-text {{
            display: flex;
            flex-direction: column;
        }}

        .brand-name {{
            font-family: 'Outfit', sans-serif;
            font-size: 22px;
            font-weight: 700;
            color: var(--text-main);
            letter-spacing: -0.5px;
        }}

        .brand-badge {{
            font-size: 11px;
            color: var(--accent-cyan);
            font-weight: 600;
            letter-spacing: 0.5px;
            text-transform: uppercase;
        }}

        .status-pill {{
            display: inline-flex;
            align-items: center;
            gap: 8px;
            background: rgba(16, 185, 129, 0.12);
            border: 1px solid rgba(16, 185, 129, 0.3);
            padding: 6px 14px;
            border-radius: 9999px;
            font-size: 13px;
            font-weight: 600;
            color: #34D399;
        }}

        .pulse-dot {{
            width: 8px;
            height: 8px;
            background-color: #10B981;
            border-radius: 50%;
            box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.7);
            animation: pulse 2s infinite;
        }}

        @keyframes pulse {{
            0% {{ box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.7); }}
            70% {{ box-shadow: 0 0 0 8px rgba(16, 185, 129, 0); }}
            100% {{ box-shadow: 0 0 0 0 rgba(16, 185, 129, 0); }}
        }}

        /* Hero Section */
        .hero {{
            padding: 70px 0 40px;
            text-align: center;
            max-width: 840px;
            margin: 0 auto;
        }}

        .hero-tag {{
            display: inline-block;
            background: rgba(99, 102, 241, 0.15);
            border: 1px solid rgba(99, 102, 241, 0.35);
            color: #818CF8;
            font-size: 12px;
            font-weight: 700;
            letter-spacing: 1px;
            text-transform: uppercase;
            padding: 6px 16px;
            border-radius: 20px;
            margin-bottom: 20px;
        }}

        .hero-title {{
            font-family: 'Outfit', sans-serif;
            font-size: clamp(34px, 5.5vw, 56px);
            font-weight: 800;
            line-height: 1.15;
            letter-spacing: -1.5px;
            margin-bottom: 20px;
            background: linear-gradient(135deg, #FFFFFF 30%, #CBD5E1 70%, #818CF8 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }}

        .hero-subtitle {{
            font-size: clamp(16px, 2vw, 19px);
            color: var(--text-muted);
            margin-bottom: 36px;
            max-width: 720px;
            margin-left: auto;
            margin-right: auto;
        }}

        .hero-actions {{
            display: flex;
            flex-wrap: wrap;
            justify-content: center;
            gap: 16px;
            margin-bottom: 48px;
        }}

        .btn {{
            display: inline-flex;
            align-items: center;
            gap: 10px;
            padding: 14px 28px;
            border-radius: 12px;
            font-size: 15px;
            font-weight: 600;
            text-decoration: none;
            transition: all 0.2s ease;
            cursor: pointer;
            border: none;
        }}

        .btn-primary {{
            background: linear-gradient(135deg, #4F46E5, #6366F1);
            color: #FFFFFF;
            box-shadow: 0 4px 20px rgba(99, 102, 241, 0.4);
        }}

        .btn-primary:hover {{
            background: linear-gradient(135deg, #4338CA, #4F46E5);
            transform: translateY(-2px);
            box-shadow: 0 8px 25px rgba(99, 102, 241, 0.5);
        }}

        .btn-secondary {{
            background: rgba(255, 255, 255, 0.05);
            color: var(--text-main);
            border: 1px solid var(--border);
            backdrop-filter: blur(10px);
        }}

        .btn-secondary:hover {{
            background: rgba(255, 255, 255, 0.1);
            border-color: rgba(255, 255, 255, 0.2);
            transform: translateY(-2px);
        }}

        /* Metrics Bar */
        .metrics-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 16px;
            margin-bottom: 60px;
        }}

        .metric-card {{
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 16px;
            padding: 20px 24px;
            backdrop-filter: blur(12px);
            transition: border-color 0.2s ease, transform 0.2s ease;
        }}

        .metric-card:hover {{
            border-color: var(--border-highlight);
            transform: translateY(-2px);
        }}

        .metric-label {{
            font-size: 13px;
            font-weight: 500;
            color: var(--text-muted);
            margin-bottom: 6px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }}

        .metric-value {{
            font-family: 'Outfit', sans-serif;
            font-size: 24px;
            font-weight: 700;
            color: var(--text-main);
            display: flex;
            align-items: center;
            gap: 8px;
        }}

        .metric-sub {{
            font-size: 12px;
            color: var(--accent-emerald);
            font-weight: 500;
            margin-top: 4px;
        }}

        /* Features Section */
        .section-title {{
            font-family: 'Outfit', sans-serif;
            font-size: 28px;
            font-weight: 700;
            margin-bottom: 12px;
            letter-spacing: -0.5px;
        }}

        .section-desc {{
            color: var(--text-muted);
            margin-bottom: 32px;
            font-size: 16px;
        }}

        .features-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
            gap: 20px;
            margin-bottom: 60px;
        }}

        .feature-card {{
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 18px;
            padding: 26px;
            transition: all 0.25s ease;
            position: relative;
            overflow: hidden;
        }}

        .feature-card::before {{
            content: '';
            position: absolute;
            top: 0; left: 0; right: 0;
            height: 3px;
            background: linear-gradient(90deg, transparent, var(--border-highlight), transparent);
            opacity: 0;
            transition: opacity 0.3s ease;
        }}

        .feature-card:hover {{
            background: var(--bg-card-hover);
            border-color: var(--border-highlight);
            transform: translateY(-3px);
        }}

        .feature-card:hover::before {{
            opacity: 1;
        }}

        .feature-icon {{
            font-size: 32px;
            margin-bottom: 16px;
            display: inline-block;
        }}

        .feature-name {{
            font-family: 'Outfit', sans-serif;
            font-size: 19px;
            font-weight: 700;
            margin-bottom: 8px;
            color: #FFFFFF;
        }}

        .feature-text {{
            font-size: 14px;
            color: var(--text-muted);
            line-height: 1.55;
        }}

        /* Interactive Health Probe / Live Tester */
        .tester-box {{
            background: var(--bg-secondary);
            border: 1px solid var(--border);
            border-radius: 18px;
            padding: 28px;
            margin-bottom: 60px;
        }}

        .tester-header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 16px;
            margin-bottom: 20px;
        }}

        .code-display {{
            background: #05070B;
            border: 1px solid rgba(255, 255, 255, 0.05);
            border-radius: 12px;
            padding: 16px;
            font-family: 'JetBrains Mono', monospace;
            font-size: 13px;
            color: #A5B4FC;
            overflow-x: auto;
            white-space: pre-wrap;
            max-height: 280px;
        }}

        /* API Directory Table */
        .api-section {{
            margin-bottom: 70px;
        }}

        .api-controls {{
            display: flex;
            flex-wrap: wrap;
            justify-content: space-between;
            gap: 16px;
            margin-bottom: 20px;
        }}

        .search-input {{
            background: var(--bg-secondary);
            border: 1px solid var(--border);
            color: var(--text-main);
            padding: 10px 18px;
            border-radius: 10px;
            font-size: 14px;
            min-width: 280px;
            outline: none;
        }}

        .search-input:focus {{
            border-color: var(--primary-light);
        }}

        .table-wrap {{
            overflow-x: auto;
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 16px;
        }}

        table {{
            width: 100%;
            border-collapse: collapse;
            text-align: left;
            font-size: 14px;
        }}

        th {{
            background: rgba(255, 255, 255, 0.02);
            color: var(--text-dim);
            font-weight: 600;
            padding: 16px 20px;
            border-bottom: 1px solid var(--border);
            text-transform: uppercase;
            font-size: 12px;
            letter-spacing: 0.5px;
        }}

        td {{
            padding: 14px 20px;
            border-bottom: 1px solid rgba(255, 255, 255, 0.04);
            color: var(--text-muted);
        }}

        tr:last-child td {{
            border-bottom: none;
        }}

        tr:hover td {{
            background: rgba(255, 255, 255, 0.02);
        }}

        .badge-method {{
            font-family: 'JetBrains Mono', monospace;
            font-size: 11px;
            font-weight: 700;
            padding: 4px 8px;
            border-radius: 6px;
            display: inline-block;
        }}

        .method-get {{
            background: rgba(16, 185, 129, 0.15);
            color: #34D399;
            border: 1px solid rgba(16, 185, 129, 0.3);
        }}

        .method-post {{
            background: rgba(99, 102, 241, 0.15);
            color: #818CF8;
            border: 1px solid rgba(99, 102, 241, 0.3);
        }}

        .endpoint-path {{
            font-family: 'JetBrains Mono', monospace;
            color: #E2E8F0;
            font-weight: 600;
            cursor: pointer;
            transition: color 0.15s ease;
        }}

        .endpoint-path:hover {{
            color: var(--accent-cyan);
            text-decoration: underline;
        }}

        /* Footer */
        footer {{
            border-top: 1px solid var(--border);
            padding: 40px 0 60px;
            display: flex;
            flex-wrap: wrap;
            justify-content: space-between;
            align-items: center;
            gap: 20px;
            color: var(--text-dim);
            font-size: 14px;
        }}

        .footer-links {{
            display: flex;
            gap: 20px;
        }}

        .footer-links a {{
            color: var(--text-muted);
            text-decoration: none;
            transition: color 0.2s ease;
        }}

        .footer-links a:hover {{
            color: var(--text-main);
        }}
    </style>
</head>
<body>

<div class="container">
    <header>
        <a href="/" class="brand">
            <div class="logo-icon">K</div>
            <div class="brand-text">
                <span class="brand-name">Krum</span>
                <span class="brand-badge">Cloud Engine v1.0.0</span>
            </div>
        </a>

        <div class="status-pill">
            <span class="pulse-dot"></span>
            <span>API Operational</span>
        </div>
    </header>

    <main>
        <!-- Hero Section -->
        <section class="hero">
            <div class="hero-tag">Enterprise Retail POS & Inventory Platform</div>
            <h1 class="hero-title">High-Velocity Point of Sale & Cloud Inventory Sync</h1>
            <p class="hero-subtitle">
                Built for modern supermarkets, provision stores, and FMCG retailers. Offline-first local SQLite execution, multi-unit stock conversions, 1-tap restock procurement, and seamless cloud synchronization.
            </p>

            <div class="hero-actions">
                <a href="/download/krum.apk" class="btn btn-primary" id="btn-download-apk">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                        <polyline points="7 10 12 15 17 10"></polyline>
                        <line x1="12" y1="15" x2="12" y2="3"></line>
                    </svg>
                    <span>Download Android App</span>
                    <span style="font-size: 11px; opacity: 0.8; background: rgba(255,255,255,0.2); padding: 2px 6px; border-radius: 6px;">APK</span>
                </a>

                <a href="/admin/" class="btn btn-secondary">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                        <rect x="3" y="11" width="18" height="11" rx="2" ry="2"></rect>
                        <path d="M7 11V7a5 5 0 0 1 10 0v4"></path>
                    </svg>
                    <span>Admin Portal</span>
                </a>

                <a href="/api/" class="btn btn-secondary">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                        <polyline points="16 18 22 12 16 6"></polyline>
                        <polyline points="8 6 2 12 8 18"></polyline>
                    </svg>
                    <span>API JSON Index</span>
                </a>
            </div>
        </section>

        <!-- Live Server Status Bar -->
        <section class="metrics-grid">
            <div class="metric-card">
                <div class="metric-label">Backend Health</div>
                <div class="metric-value">
                    <span style="color: var(--accent-emerald);">●</span> { "Healthy" if db_ok else "Degraded" }
                </div>
                <div class="metric-sub">{db_msg}</div>
            </div>

            <div class="metric-card">
                <div class="metric-label">Cloud Sync Protocol</div>
                <div class="metric-value">Delta Sync</div>
                <div class="metric-sub">Offline SQLite Conflict-Free</div>
            </div>

            <div class="metric-card">
                <div class="metric-label">Catalog Architecture</div>
                <div class="metric-value">Multi-Unit</div>
                <div class="metric-sub">Pcs / Packs / Cartons / Crates</div>
            </div>

            <div class="metric-card">
                <div class="metric-label">Server Timestamp</div>
                <div class="metric-value" style="font-size: 18px; font-family: 'JetBrains Mono', monospace;">
                    {now_wat.split()[1]}
                </div>
                <div class="metric-sub">Africa/Lagos (WAT)</div>
            </div>
        </section>

        <!-- Core Feature Pillars -->
        <section>
            <h2 class="section-title">Engineered for Fast-Paced Retail</h2>
            <p class="section-desc">Key capabilities powering retail stores, supermarkets, and warehouse depots.</p>

            <div class="features-grid">
                <div class="feature-card">
                    <div class="feature-icon">⚡</div>
                    <div class="feature-name">Sub-Second Barcode POS</div>
                    <div class="feature-text">
                        Instant barcode lookup supporting multiple pack units (selling a single piece or full carton), tolerant search (handling leading zeros and SKUs), and receipt printing via Bluetooth & PDF.
                    </div>
                </div>

                <div class="feature-card">
                    <div class="feature-icon">📦</div>
                    <div class="feature-name">Low Stock & 1-Tap Restock Hub</div>
                    <div class="feature-text">
                        Automatic reorder level tracking, deficit calculation, and 1-tap WhatsApp purchase requisition generation formatted directly for preferred suppliers.
                    </div>
                </div>

                <div class="feature-card">
                    <div class="feature-icon">💰</div>
                    <div class="feature-name">Cash Drawer & Shift Auditing</div>
                    <div class="feature-text">
                        Cashier shift management with live float tracking, expected drawer balance computation, cash-in/cash-out logging, and end-of-shift variance discrepancy auditing.
                    </div>
                </div>

                <div class="feature-card">
                    <div class="feature-icon">👥</div>
                    <div class="feature-name">Customer Credit & Debtors Ledger</div>
                    <div class="feature-text">
                        Real-time customer debt balances, partial repayment recording, payment receipt sharing, and 1-tap WhatsApp statement summaries.
                    </div>
                </div>

                <div class="feature-card">
                    <div class="feature-icon">📈</div>
                    <div class="feature-name">Weighted Restocking & P&L</div>
                    <div class="feature-text">
                        Weighted Average Cost Price (WACP) inventory valuation recalculation on purchase receipt, periodic gross margin, and net profit analytics.
                    </div>
                </div>

                <div class="feature-card">
                    <div class="feature-icon">🔄</div>
                    <div class="feature-name">True Offline-First Resilience</div>
                    <div class="feature-text">
                        Cashiers never stop selling when the internet is down. Local SQLite store queues sync actions and automatically merges with the cloud upon reconnection.
                    </div>
                </div>
            </div>
        </section>

        <!-- Live API Health Probe Widget -->
        <section class="tester-box">
            <div class="tester-header">
                <div>
                    <h3 style="font-family: 'Outfit', sans-serif; font-size: 20px; font-weight: 700;">Live Endpoint Probe</h3>
                    <p style="font-size: 14px; color: var(--text-muted);">Test the live cloud API and verify latency right from your browser.</p>
                </div>
                <div style="display: flex; gap: 10px;">
                    <button class="btn btn-secondary" onclick="runProbe('/health/')" style="padding: 8px 16px; font-size: 13px;">Probe /health/</button>
                    <button class="btn btn-secondary" onclick="runProbe('/api/')" style="padding: 8px 16px; font-size: 13px;">Inspect /api/</button>
                </div>
            </div>
            <div class="code-display" id="probe-output">// Click a probe button above or wait for automatic ping...</div>
        </section>

        <!-- API Reference Directory -->
        <section class="api-section">
            <div class="api-controls">
                <div>
                    <h2 class="section-title">Cloud API Directory</h2>
                    <p style="color: var(--text-muted); font-size: 14px;">Available endpoints for mobile clients, webhooks, and third-party integrations.</p>
                </div>
                <input type="text" id="api-search" class="search-input" placeholder="Filter endpoints (e.g. sales, sync, stock)..." oninput="filterEndpoints()">
            </div>

            <div class="table-wrap">
                <table id="endpoints-table">
                    <thead>
                        <tr>
                            <th>Method</th>
                            <th>Endpoint Route</th>
                            <th>Category</th>
                            <th>Auth Requirement</th>
                            <th>Description</th>
                        </tr>
                    </thead>
                    <tbody id="endpoints-body">
"""

    for ep in API_ENDPOINTS_CATALOG:
        m = ep["method"]
        badge_cls = "method-get" if m == "GET" else "method-post"
        html += f"""
                        <tr class="ep-row" data-search="{ep['path'].lower()} {ep['category'].lower()} {ep['desc'].lower()}">
                            <td><span class="badge-method {badge_cls}">{m}</span></td>
                            <td><span class="endpoint-path" onclick="copyPath('{ep['path']}')">{ep['path']}</span></td>
                            <td><span style="color: #CBD5E1; font-size: 13px;">{ep['category']}</span></td>
                            <td><span style="color: var(--text-dim); font-size: 12px; font-family: monospace;">{ep['auth']}</span></td>
                            <td>{ep['desc']}</td>
                        </tr>
        """

    html += """
                    </tbody>
                </table>
            </div>
        </section>
    </main>

    <footer>
        <div>
            <strong>Krum</strong> — Retail Point of Sale & Cloud Sync Architecture
        </div>
        <div class="footer-links">
            <a href="/admin/">Django Admin</a>
            <a href="/health/">Health Probe</a>
            <a href="/api/">API Specs</a>
            <a href="/download/krum.apk">Mobile APK</a>
        </div>
    </footer>
</div>

<script>
    async function runProbe(url) {
        const out = document.getElementById('probe-output');
        out.textContent = `Probing ${url}...`;
        const startTime = performance.now();
        try {
            const res = await fetch(url, { headers: { 'Accept': 'application/json' } });
            const duration = Math.round(performance.now() - startTime);
            const data = await res.json();
            out.textContent = `HTTP ${res.status} OK (${duration}ms)\n` + JSON.stringify(data, null, 2);
        } catch (err) {
            out.textContent = `Probe Error: ${err.message}`;
        }
    }

    function filterEndpoints() {
        const query = document.getElementById('api-search').value.toLowerCase().trim();
        const rows = document.querySelectorAll('.ep-row');
        rows.forEach(r => {
            const text = r.getAttribute('data-search');
            r.style.display = text.includes(query) ? '' : 'none';
        });
    }

    function copyPath(path) {
        navigator.clipboard.writeText(path).then(() => {
            alert(`Copied endpoint route: ${path}`);
        });
    }

    // Auto-probe health on load
    window.addEventListener('DOMContentLoaded', () => {
        runProbe('/health/');
    });
</script>
</body>
</html>
"""
    return HttpResponse(html, content_type='text/html')
