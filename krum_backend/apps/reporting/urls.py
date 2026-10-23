from django.urls import path
from store import views

urlpatterns = [
    path('dashboard/', views.dashboard, name='dashboard'),
    path('reports/profit-loss/', views.profit_loss_report, name='profit_loss_report'),
    path('reports/sales/', views.sales_report, name='sales_report'),
    path('reports/inventory/', views.inventory_report, name='inventory_report'),
    path('reports/export/', views.export_report_csv, name='export_report_csv'),
]
