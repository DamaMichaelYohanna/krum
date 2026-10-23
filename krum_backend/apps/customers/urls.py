from django.urls import path
from store import views

urlpatterns = [
    path('customers/', views.CustomerView.as_view(), name='customer_list_create'),
    path('customers/<int:pk>/', views.CustomerDetailView.as_view(), name='customer_detail'),
    path('customers/<int:pk>/ledger/', views.customer_ledger, name='customer_ledger'),
    path('customers/debtors/', views.debtors, name='debtors_list'),
    path('customer-payments/', views.record_customer_payment, name='record_customer_payment'),
]
