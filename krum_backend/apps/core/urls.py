from django.urls import path
from store import views

urlpatterns = [
    path('auth/register/', views.register, name='register'),
    path('business/me/', views.business_me, name='business_me'),
    path('staff/', views.staff_list_create, name='staff_list_create'),
    path('staff/<int:membership_id>/', views.staff_detail, name='staff_detail'),
]
