from django.urls import path
from . import dashboard_views

urlpatterns = [
    path('', dashboard_views.dashboard_overview, name='dashboard_overview'),
    path('sales/', dashboard_views.dashboard_sales, name='dashboard_sales'),
    path('inventory/', dashboard_views.dashboard_inventory, name='dashboard_inventory'),
    path('shifts/', dashboard_views.dashboard_shifts, name='dashboard_shifts'),
    path('customers/', dashboard_views.dashboard_customers, name='dashboard_customers'),
    path('staff/', dashboard_views.dashboard_staff, name='dashboard_staff'),
    path('settings/', dashboard_views.dashboard_settings, name='dashboard_settings'),
    path('login/', dashboard_views.dashboard_login, name='dashboard_login'),
    path('logout/', dashboard_views.dashboard_logout, name='dashboard_logout'),
    path('switch-store/<int:business_id>/', dashboard_views.switch_store, name='dashboard_switch_store'),
]
