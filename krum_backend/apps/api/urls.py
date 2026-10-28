from django.urls import include, path
from store import landing_views

urlpatterns = [
    path('', landing_views.api_root, name='api_root'),
    path('health/', landing_views.health_check, name='api_health_check'),
    path('', include('apps.core.urls')),
    path('', include('apps.catalog.urls')),
    path('', include('apps.inventory.urls')),
    path('', include('apps.purchasing.urls')),
    path('', include('apps.sales.urls')),
    path('', include('apps.customers.urls')),
    path('', include('apps.finance.urls')),
    path('', include('apps.reporting.urls')),
    path('', include('apps.sync.urls')),
]
