from django.contrib.auth import get_user_model
from django.db.models import Q


class EmailAuthBackend:
    """
    Allows authentication using an email address or username (case-insensitive).
    Ensures email can serve as the primary credential throughout the system.
    """
    def authenticate(self, request, username=None, password=None, email=None, **kwargs):
        User = get_user_model()
        identifier = email or username or kwargs.get('username')
        if not identifier or not password:
            return None

        identifier = str(identifier).strip().lower()
        try:
            user = User.objects.filter(
                Q(email__iexact=identifier) | Q(username__iexact=identifier)
            ).first()
            if user and user.check_password(password):
                return user
        except Exception:
            return None
        return None

    def get_user(self, user_id):
        User = get_user_model()
        try:
            return User.objects.get(pk=user_id)
        except User.DoesNotExist:
            return None
