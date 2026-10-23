from django.urls import path
from store import views
urlpatterns = [path('inventory/adjustments/', views.stock_adjustment), path('inventory/movements/', views.inventory_movements)]
