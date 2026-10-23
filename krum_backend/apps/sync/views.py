from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from store.permissions import HasBusiness, business_for
from .services import SyncService

@api_view(['GET'])
@permission_classes([HasBusiness])
def sync_pull(request):
    """Pulls current catalog, debtors, units, and inventory balances for offline caching."""
    business = business_for(request)
    data = SyncService.pull_catalog(business=business)
    return Response(data)

@api_view(['POST'])
@permission_classes([HasBusiness])
def sync_push(request):
    """Pushes a batch of offline transactions to the server."""
    business = business_for(request)
    payload = request.data
    results = SyncService.push_batch(business=business, actor=request.user, payload=payload)
    return Response(results, status=status.HTTP_200_OK)
