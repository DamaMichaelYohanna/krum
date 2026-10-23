"""Compatibility imports for pre-modular callers.

New code must import directly from the owning package under ``apps``.
"""
from apps.customers.services import DebtService
from apps.inventory.services import InventoryService
from apps.purchasing.services import PurchaseService
from apps.sales.services import SalesService

__all__ = ["DebtService", "InventoryService", "PurchaseService", "SalesService"]
