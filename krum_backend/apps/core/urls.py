from django.urls import path
from store import views

urlpatterns = [
    path('auth/register/', views.register, name='register'),
    path('business/me/', views.business_me, name='business_me'),
]
