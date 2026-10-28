from django.urls import path
from store import views
urlpatterns = [
    path('inventory/adjustments/', views.stock_adjustment),
    path('inventory/movements/', views.inventory_movements),
    path('inventory/low-stock/', views.low_stock_alerts, name='low_stock_alerts'),
]
