from django.urls import path
from store import views

urlpatterns = [
    path('expenses/', views.ExpenseView.as_view(), name='expense_list_create'),
    path('expenses/<int:pk>/', views.ExpenseDetailView.as_view(), name='expense_detail'),
]
