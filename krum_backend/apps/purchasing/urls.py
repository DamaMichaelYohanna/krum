from django.urls import path
from store import views

urlpatterns = [
    path('suppliers/', views.SupplierView.as_view(), name='supplier_list_create'),
    path('suppliers/<int:pk>/', views.SupplierDetailView.as_view(), name='supplier_detail'),
    path('purchases/', views.purchase_list, name='purchase_list'),
    path('purchases/complete/', views.complete_purchase, name='complete_purchase'),
]
