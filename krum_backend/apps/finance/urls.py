from django.urls import path
from store import views

urlpatterns = [
    path('expenses/', views.ExpenseView.as_view(), name='expense_list_create'),
    path('expenses/<int:pk>/', views.ExpenseDetailView.as_view(), name='expense_detail'),
    path('cash-sessions/current/', views.current_cash_session, name='current_cash_session'),
    path('cash-sessions/start/', views.start_cash_session, name='start_cash_session'),
    path('cash-sessions/<str:session_id>/close/', views.close_cash_session, name='close_cash_session'),
    path('cash-sessions/', views.list_cash_sessions, name='list_cash_sessions'),
]
