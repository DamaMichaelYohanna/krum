from django.urls import path
from store import views

urlpatterns = [
    path('categories/', views.CategoryView.as_view(), name='category_list_create'),
    path('categories/<int:pk>/', views.CategoryDetailView.as_view(), name='category_detail'),
    path('units/', views.UnitView.as_view(), name='unit_list_create'),
    path('units/<int:pk>/', views.UnitDetailView.as_view(), name='unit_detail'),
    path('products/', views.ProductView.as_view(), name='product_list_create'),
    path('products/<int:pk>/', views.ProductDetailView.as_view(), name='product_detail'),
    path('products/<int:product_id>/units/', views.add_product_unit, name='add_product_unit'),
    path('products/<int:product_id>/units/<int:unit_id>/', views.delete_product_unit, name='delete_product_unit'),
    path('products/barcode/<str:barcode>/', views.barcode_lookup, name='barcode_lookup'),
]
