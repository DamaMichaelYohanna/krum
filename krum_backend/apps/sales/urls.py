from django.urls import path
from store import views

urlpatterns = [
    path('sales/', views.sale_list, name='sale_list'),
    path('sales/complete/', views.complete_sale, name='complete_sale'),
    path('sales/<int:sale_id>/reverse/', views.reverse_sale, name='reverse_sale'),
]
