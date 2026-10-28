from django.contrib import admin
from django.urls import include, path
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from store import landing_views

urlpatterns = [
    path('', landing_views.landing_page, name='landing_page'),
    path('about/', landing_views.about_page, name='about_page'),
    path('pricing/', landing_views.pricing_page, name='pricing_page'),
    path('contact/', landing_views.contact_page, name='contact_page'),
    path('privacy/', landing_views.privacy_page, name='privacy_page'),
    path('terms/', landing_views.terms_page, name='terms_page'),
    path('health/', landing_views.health_check, name='health_check'),
    path('download/krum.apk', landing_views.download_apk, name='download_apk'),
    path('download/apk/', landing_views.download_apk, name='download_apk_alt'),
    path('admin/', admin.site.urls),
    path('api/', include('apps.api.urls')),
    path('api/auth/login/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/auth/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
]
