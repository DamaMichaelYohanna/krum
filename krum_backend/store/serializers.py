from decimal import Decimal
from django.contrib.auth.models import User
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from .models import (
    Business, Category, Customer, Expense, InventoryBalance,
    InventoryMovement, Membership, Product, ProductUnit,
    Purchase, PurchaseItem, Sale, SaleItem, SalePayment,
    Supplier, Unit
)

class EmailTokenObtainPairSerializer(TokenObtainPairSerializer):
    """
    Accepts email as the credential, allowing email to serve both username and email purposes.
    """
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['email'] = serializers.CharField(required=False)
        self.fields[self.username_field].required = False

    def validate(self, attrs):
        identifier = attrs.get('email') or attrs.get(self.username_field)
        if not identifier:
            raise serializers.ValidationError({'email': 'Email address is required.'})
        attrs[self.username_field] = str(identifier).strip().lower()
        return super().validate(attrs)

class RegisterSerializer(serializers.Serializer):
    business_name = serializers.CharField(max_length=160)
    email = serializers.EmailField(max_length=150, required=False)
    username = serializers.CharField(max_length=150, required=False)
    password = serializers.CharField(write_only=True, min_length=8)
    currency = serializers.CharField(max_length=3, default='NGN', required=False)
    phone = serializers.CharField(max_length=30, required=False, allow_blank=True)

    def to_internal_value(self, data):
        data = data.copy() if hasattr(data, 'copy') else dict(data)
        # Email serves both username and email purposes
        if 'email' not in data and 'username' in data:
            data['email'] = data['username']
        elif 'email' in data and 'username' not in data:
            data['username'] = data['email']
        return super().to_internal_value(data)

    def validate_email(self, value):
        normalized = value.strip().lower()
        if User.objects.filter(email__iexact=normalized).exists() or User.objects.filter(username__iexact=normalized).exists():
            raise serializers.ValidationError("An account with this email address already exists. Please log in.")
        return normalized

    def create(self, data):
        email = (data.get('email') or data.get('username') or '').strip().lower()
        user = User.objects.create_user(username=email, email=email, password=data['password'])
        business = Business.objects.create(
            name=data['business_name'],
            currency=data.get('currency', 'NGN'),
            phone=data.get('phone', '')
        )
        Membership.objects.create(user=user, business=business, role=Membership.Role.OWNER)

        # Seed initial default retail units
        default_units = [
            ('Piece', 'pcs'),
            ('Carton', 'ctn'),
            ('Pack', 'pk'),
            ('Bottle', 'btl'),
            ('Kg', 'kg'),
            ('Liter', 'L'),
        ]
        for name, sym in default_units:
            Unit.objects.create(business=business, name=name, symbol=sym)

        # Seed initial default categories
        default_categories = [
            'General Provisions',
            'Beverages & Drinks',
            'Packaged Foods',
            'Toiletries & Household',
        ]
        for name in default_categories:
            Category.objects.create(business=business, name=name)

        return user

class BusinessSerializer(serializers.ModelSerializer):
    class Meta:
        model = Business
        fields = ['id', 'name', 'currency', 'phone', 'created_at']

class CategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Category
        fields = ['id', 'name', 'created_at']

class UnitSerializer(serializers.ModelSerializer):
    class Meta:
        model = Unit
        fields = ['id', 'name', 'symbol', 'created_at']

class SupplierSerializer(serializers.ModelSerializer):
    class Meta:
        model = Supplier
        fields = ['id', 'name', 'phone']

class CustomerSerializer(serializers.ModelSerializer):
    outstanding = serializers.SerializerMethodField()

    class Meta:
        model = Customer
        fields = ['id', 'name', 'phone', 'outstanding']

    def get_outstanding(self, obj):
        due = sum((
            sale.total - sale.amount_paid - sum((alloc.amount for alloc in sale.customer_payment_allocations.all()), Decimal('0'))
            for sale in obj.sale_set.filter(status=Sale.Status.COMPLETED)
        ), Decimal('0'))
        return float(due)

class ProductUnitSerializer(serializers.ModelSerializer):
    unit_name = serializers.CharField(source='unit.name', read_only=True)

    class Meta:
        model = ProductUnit
        fields = ['id', 'unit', 'unit_name', 'conversion_to_base', 'cost_price', 'selling_price', 'minimum_price']

    def validate(self, attrs):
        if attrs.get('minimum_price', 0) > attrs.get('selling_price', 0):
            raise serializers.ValidationError('Minimum price cannot exceed selling price.')
        return attrs

class ProductSerializer(serializers.ModelSerializer):
    units = ProductUnitSerializer(many=True, read_only=True)
    stock = serializers.DecimalField(source='inventory.quantity_base', max_digits=16, decimal_places=3, read_only=True)
    average_cost = serializers.DecimalField(source='inventory.average_cost', max_digits=14, decimal_places=2, read_only=True)
    base_unit_name = serializers.CharField(source='base_unit.name', read_only=True)
    category_name = serializers.CharField(source='category.name', read_only=True)
    preferred_supplier_name = serializers.CharField(source='preferred_supplier.name', read_only=True)

    # Allow setting initial unit prices and opening stock on creation
    selling_price = serializers.DecimalField(max_digits=14, decimal_places=2, write_only=True, required=False)
    cost_price = serializers.DecimalField(max_digits=14, decimal_places=2, write_only=True, required=False)
    opening_stock = serializers.DecimalField(max_digits=16, decimal_places=3, write_only=True, required=False)

    class Meta:
        model = Product
        fields = [
            'id', 'name', 'sku', 'barcode', 'category', 'category_name',
            'base_unit', 'base_unit_name', 'brand', 'reorder_level',
            'preferred_supplier', 'preferred_supplier_name',
            'active', 'stock', 'average_cost', 'units',
            'selling_price', 'cost_price', 'opening_stock'
        ]
        extra_kwargs = {
            'barcode': {'required': False, 'allow_blank': True},
            'preferred_supplier': {'required': False, 'allow_null': True}
        }

    def create(self, validated_data):
        selling_price = validated_data.pop('selling_price', None)
        cost_price = validated_data.pop('cost_price', Decimal('0'))
        opening_stock = validated_data.pop('opening_stock', None)
        product = super().create(validated_data)

        # Automatically create base ProductUnit if selling_price is provided
        if selling_price is not None:
            ProductUnit.objects.create(
                product=product,
                unit=product.base_unit,
                conversion_to_base=Decimal('1.000'),
                cost_price=cost_price or Decimal('0'),
                selling_price=selling_price,
                minimum_price=cost_price or Decimal('0')
            )

        # Automatically initialize InventoryBalance & opening stock if provided
        balance, _ = InventoryBalance.objects.get_or_create(product=product)
        if opening_stock and Decimal(str(opening_stock)) > 0:
            from apps.inventory.services import InventoryService
            InventoryService.adjust(
                business=product.business,
                product=product,
                quantity_delta=Decimal(str(opening_stock)),
                reason=InventoryMovement.Reason.OPENING,
                actor=None,
                reference='Initial product creation'
            )
            if cost_price:
                balance.average_cost = Decimal(str(cost_price))
                balance.save(update_fields=['average_cost'])

        return product

class TransactionSerializer(serializers.Serializer):
    client_transaction_id = serializers.UUIDField()
    customer = serializers.IntegerField(required=False, allow_null=True)
    supplier = serializers.IntegerField(required=False, allow_null=True)
    amount_paid = serializers.DecimalField(max_digits=14, decimal_places=2, default=0)
    discount = serializers.DecimalField(max_digits=14, decimal_places=2, default=0)
    reference = serializers.CharField(required=False, allow_blank=True)
    items = serializers.ListField(child=serializers.DictField(), min_length=1)

class ExpenseSerializer(serializers.ModelSerializer):
    class Meta:
        model = Expense
        fields = ['id', 'client_transaction_id', 'category', 'amount', 'description', 'occurred_at', 'created_at']

class CustomerPaymentSerializer(serializers.Serializer):
    customer = serializers.IntegerField()
    amount = serializers.DecimalField(max_digits=14, decimal_places=2)
    method = serializers.CharField(default='cash')
    reference = serializers.CharField(required=False, allow_blank=True)

class StockAdjustmentSerializer(serializers.Serializer):
    product = serializers.IntegerField()
    quantity_delta = serializers.DecimalField(max_digits=16, decimal_places=3)
    reason = serializers.ChoiceField(choices=[
        'opening', 'adjustment', 'damaged', 'expired',
        'missing', 'physical_count', 'return', 'other'
    ])
    reference = serializers.CharField(required=False, allow_blank=True)

class SaleItemSerializer(serializers.ModelSerializer):
    product_name = serializers.CharField(source='product_unit.product.name', read_only=True)
    unit_name = serializers.CharField(source='product_unit.unit.name', read_only=True)

    class Meta:
        model = SaleItem
        fields = ['id', 'product_unit', 'product_name', 'unit_name', 'quantity', 'unit_price', 'cogs']

class SaleSerializer(serializers.ModelSerializer):
    items = SaleItemSerializer(many=True, read_only=True)
    customer_name = serializers.CharField(source='customer.name', read_only=True)

    class Meta:
        model = Sale
        fields = [
            'id', 'client_transaction_id', 'customer', 'customer_name',
            'subtotal', 'discount', 'total', 'amount_paid',
            'status', 'completed_at', 'items'
        ]

class PurchaseItemSerializer(serializers.ModelSerializer):
    product_name = serializers.CharField(source='product_unit.product.name', read_only=True)
    unit_name = serializers.CharField(source='product_unit.unit.name', read_only=True)

    class Meta:
        model = PurchaseItem
        fields = ['id', 'product_unit', 'product_name', 'unit_name', 'quantity', 'unit_cost']

class PurchaseSerializer(serializers.ModelSerializer):
    items = PurchaseItemSerializer(many=True, read_only=True)
    supplier_name = serializers.CharField(source='supplier.name', read_only=True)

    class Meta:
        model = Purchase
        fields = [
            'id', 'client_transaction_id', 'supplier', 'supplier_name',
            'reference', 'total', 'amount_paid', 'completed_at', 'items'
        ]

class InventoryMovementSerializer(serializers.ModelSerializer):
    product_name = serializers.CharField(source='product.name', read_only=True)
    actor_name = serializers.CharField(source='actor.username', read_only=True)

    class Meta:
        model = InventoryMovement
        fields = ['id', 'product', 'product_name', 'quantity_base', 'unit_cost', 'reason', 'reference', 'actor_name', 'created_at']
