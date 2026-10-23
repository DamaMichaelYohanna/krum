from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import BasePermission
from .models import Membership

class HasBusiness(BasePermission):
    def has_permission(self, request, view):
        return Membership.objects.filter(user=request.user).exists()

def business_for(request):
    memberships = Membership.objects.select_related("business").filter(user=request.user)
    requested_id = request.headers.get("X-Business-ID")
    if requested_id:
        membership = memberships.filter(business_id=requested_id).first()
        if not membership: raise PermissionDenied("You do not have access to this business.")
        return membership.business
    membership = memberships.first()
    if not membership: raise PermissionDenied("No business is assigned to this user.")
    return membership.business

def require_role(request, *roles):
    membership = Membership.objects.filter(user=request.user, business=business_for(request)).first()
    if not membership or membership.role not in roles:
        raise PermissionDenied("You do not have permission to perform this action.")
    return membership
