class Business {
  final int id;
  final String name;
  final String currency;
  final String phone;

  Business({
    required this.id,
    required this.name,
    this.currency = 'NGN',
    this.phone = '',
  });

  factory Business.fromJson(Map<String, dynamic> json) => Business(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? 'My Shop',
        currency: json['currency'] as String? ?? 'NGN',
        phone: json['phone'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'currency': currency,
        'phone': phone,
      };

  Business copyWith({
    int? id,
    String? name,
    String? currency,
    String? phone,
  }) {
    return Business(
      id: id ?? this.id,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      phone: phone ?? this.phone,
    );
  }
}

class Category {
  final int id;
  final String name;

  Category({required this.id, required this.name});

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class Unit {
  final int id;
  final String name;
  final String symbol;

  Unit({required this.id, required this.name, this.symbol = ''});

  factory Unit.fromJson(Map<String, dynamic> json) => Unit(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        symbol: json['symbol'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'symbol': symbol};
}

class ProductUnit {
  final int id;
  final int unitId;
  final String unitName;
  final double conversionToBase;
  double costPrice;
  double sellingPrice;
  final double minimumPrice;

  ProductUnit({
    required this.id,
    required this.unitId,
    required this.unitName,
    required this.conversionToBase,
    required this.costPrice,
    required this.sellingPrice,
    required this.minimumPrice,
  });

  factory ProductUnit.fromJson(Map<String, dynamic> json) => ProductUnit(
        id: json['id'] as int? ?? 0,
        unitId: json['unit'] is int
            ? json['unit'] as int
            : (json['unit_id'] as int? ?? 0),
        unitName: json['unit_name'] as String? ?? 'Unit',
        conversionToBase: (json['conversion_to_base'] as num?)?.toDouble() ?? 1.0,
        costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0.0,
        sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0.0,
        minimumPrice: (json['minimum_price'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'unit_id': unitId,
        'unit_name': unitName,
        'conversion_to_base': conversionToBase,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'minimum_price': minimumPrice,
      };

  ProductUnit copyWith({
    int? id,
    int? unitId,
    String? unitName,
    double? conversionToBase,
    double? costPrice,
    double? sellingPrice,
    double? minimumPrice,
  }) =>
      ProductUnit(
        id: id ?? this.id,
        unitId: unitId ?? this.unitId,
        unitName: unitName ?? this.unitName,
        conversionToBase: conversionToBase ?? this.conversionToBase,
        costPrice: costPrice ?? this.costPrice,
        sellingPrice: sellingPrice ?? this.sellingPrice,
        minimumPrice: minimumPrice ?? this.minimumPrice,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductUnit &&
          runtimeType == other.runtimeType &&
          ((id != 0 && other.id != 0 && id == other.id) ||
           (unitId != 0 && other.unitId != 0 && unitId == other.unitId) ||
           (unitName.isNotEmpty && unitName.toLowerCase() == other.unitName.toLowerCase()));

  @override
  int get hashCode => (unitId != 0 ? unitId : (id != 0 ? id : unitName.hashCode));
}

class Product {
  final int id;
  final String name;
  final String sku;
  final String barcode;
  final int? categoryId;
  final String? categoryName;
  final int baseUnitId;
  final String baseUnitName;
  final String brand;
  final double reorderLevel;
  final bool active;
  final int? preferredSupplierId;
  final String? preferredSupplierName;
  double stockBase;
  double averageCost;
  final List<ProductUnit> units;

  Product({
    required this.id,
    required this.name,
    this.sku = '',
    this.barcode = '',
    this.categoryId,
    this.categoryName,
    this.baseUnitId = 0,
    this.baseUnitName = 'Piece',
    this.brand = '',
    this.reorderLevel = 0.0,
    this.active = true,
    this.preferredSupplierId,
    this.preferredSupplierName,
    this.stockBase = 0.0,
    this.averageCost = 0.0,
    this.units = const [],
  });

  Product copyWith({
    int? id,
    String? name,
    String? sku,
    String? barcode,
    int? categoryId,
    String? categoryName,
    int? baseUnitId,
    String? baseUnitName,
    String? brand,
    double? reorderLevel,
    bool? active,
    int? preferredSupplierId,
    String? preferredSupplierName,
    double? stockBase,
    double? averageCost,
    List<ProductUnit>? units,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      baseUnitId: baseUnitId ?? this.baseUnitId,
      baseUnitName: baseUnitName ?? this.baseUnitName,
      brand: brand ?? this.brand,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      active: active ?? this.active,
      preferredSupplierId: preferredSupplierId ?? this.preferredSupplierId,
      preferredSupplierName: preferredSupplierName ?? this.preferredSupplierName,
      stockBase: stockBase ?? this.stockBase,
      averageCost: averageCost ?? this.averageCost,
      units: units ?? this.units,
    );
  }

  bool get isOutOfStock => stockBase <= 0;
  bool get isLowStock => stockBase > 0 && stockBase <= reorderLevel;
  bool get needsRestock => isOutOfStock || isLowStock;
  double get targetHealthyStock => (reorderLevel > 0 ? reorderLevel * 2 : 10.0);
  double get suggestedReorderQty => (targetHealthyStock - stockBase).clamp(1.0, double.infinity);
  double get estimatedRestockCost => suggestedReorderQty * (baseUnit.costPrice > 0 ? baseUnit.costPrice : (averageCost > 0 ? averageCost : 0.0));
  double get basePrice => baseUnit.sellingPrice;

  List<ProductUnit> get allUnits {
    if (units.isEmpty) {
      return [baseUnit];
    }
    final hasBase = units.any(
      (u) =>
          (baseUnitId != 0 && u.unitId == baseUnitId) ||
          u.conversionToBase == 1.0 ||
          u.unitName.toLowerCase() == baseUnitName.toLowerCase(),
    );
    if (!hasBase) {
      return [baseUnit, ...units];
    }
    return units;
  }

  ProductUnit get baseUnit {
    return units.firstWhere(
      (u) => u.unitId == baseUnitId || u.conversionToBase == 1.0,
      orElse: () => units.isNotEmpty
          ? units.first
          : ProductUnit(
              id: 0,
              unitId: baseUnitId,
              unitName: baseUnitName,
              conversionToBase: 1.0,
              costPrice: averageCost,
              sellingPrice: 0.0,
              minimumPrice: 0.0,
            ),
    );
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final rawUnits = (json['units'] as List<dynamic>?) ?? [];
    return Product(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      barcode: json['barcode'] as String? ?? '',
      categoryId: json['category'] is int
          ? json['category'] as int
          : (json['category_id'] as int?),
      categoryName: json['category_name'] as String?,
      baseUnitId: json['base_unit'] is int
          ? json['base_unit'] as int
          : (json['base_unit_id'] as int? ?? 0),
      baseUnitName: json['base_unit_name'] as String? ?? 'Piece',
      brand: json['brand'] as String? ?? '',
      reorderLevel: (json['reorder_level'] as num?)?.toDouble() ?? 0.0,
      active: json['active'] as bool? ?? true,
      preferredSupplierId: json['preferred_supplier'] is int
          ? json['preferred_supplier'] as int
          : (json['preferred_supplier_id'] as int?),
      preferredSupplierName: json['preferred_supplier_name'] as String?,
      stockBase: (json['stock'] ?? json['stock_base'] as num?)?.toDouble() ?? 0.0,
      averageCost: (json['average_cost'] as num?)?.toDouble() ?? 0.0,
      units: rawUnits.map((u) => ProductUnit.fromJson(u as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sku': sku,
        'barcode': barcode,
        'category_id': categoryId,
        'category_name': categoryName,
        'base_unit_id': baseUnitId,
        'base_unit_name': baseUnitName,
        'brand': brand,
        'reorder_level': reorderLevel,
        'active': active,
        'preferred_supplier_id': preferredSupplierId,
        'preferred_supplier_name': preferredSupplierName,
        'stock_base': stockBase,
        'average_cost': averageCost,
        'units': units.map((u) => u.toJson()).toList(),
      };
}

class CartItem {
  final Product product;
  ProductUnit selectedUnit;
  double quantity;
  double customUnitPrice;

  CartItem({
    required this.product,
    required this.selectedUnit,
    this.quantity = 1.0,
    double? customUnitPrice,
  }) : customUnitPrice = customUnitPrice ?? selectedUnit.sellingPrice;

  double get unitPrice => customUnitPrice;
  double get total => quantity * unitPrice;
  double get requiredBaseQuantity => quantity * selectedUnit.conversionToBase;
}

class Customer {
  final int id;
  final String name;
  final String phone;
  double outstanding;

  Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.outstanding = 0.0,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        outstanding: (json['outstanding'] as num?)?.toDouble() ?? 0.0,
      );

  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    double? outstanding,
  }) =>
      Customer(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        outstanding: outstanding ?? this.outstanding,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'outstanding': outstanding,
      };
}

class Supplier {
  final int id;
  final String name;
  final String phone;

  Supplier({
    required this.id,
    required this.name,
    this.phone = '',
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
      };
}

class Expense {
  final int? id;
  final String? clientTransactionId;
  final String category;
  final double amount;
  final String description;
  final String occurredAt;
  final String? createdAt;

  Expense({
    this.id,
    this.clientTransactionId,
    required this.category,
    required this.amount,
    this.description = '',
    required this.occurredAt,
    this.createdAt,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    String date = (json['occurred_at'] as String?) ?? '';
    if (date.isEmpty) {
      final created = json['created_at'] as String?;
      if (created != null && created.length >= 10) {
        date = created.substring(0, 10);
      }
    }
    if (date.isEmpty) {
      date = DateTime.now().toIso8601String().substring(0, 10);
    }

    return Expense(
      id: json['id'] as int?,
      clientTransactionId: json['client_transaction_id'] as String?,
      category: json['category'] as String? ?? 'Other',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String? ?? '',
      occurredAt: date,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (clientTransactionId != null) 'client_transaction_id': clientTransactionId,
        'category': category,
        'amount': amount,
        'description': description,
        'occurred_at': occurredAt,
        if (createdAt != null) 'created_at': createdAt,
      };
}

class TopProduct {
  final int productId;
  final String productName;
  final double quantity;
  final double totalSales;

  TopProduct({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.totalSales,
  });

  factory TopProduct.fromJson(Map<String, dynamic> json) => TopProduct(
        productId: json['product_id'] as int? ?? 0,
        productName: json['product_name'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
        totalSales: (json['total_sales'] as num?)?.toDouble() ?? 0.0,
      );
}

class SoldItemSummary {
  final int productId;
  final String productName;
  final String unitName;
  final double quantitySold;
  final double totalRevenue;
  final int transactionCount;
  final double averagePrice;

  SoldItemSummary({
    required this.productId,
    required this.productName,
    required this.unitName,
    required this.quantitySold,
    required this.totalRevenue,
    required this.transactionCount,
    required this.averagePrice,
  });
}

class DashboardData {
  final String currency;
  final String period;
  final double todaySales;
  final double grossProfit;
  final double cogs;
  final double expenses;
  final double netProfit;
  final int transactions;
  final int lowStock;
  final int outOfStock;
  final double stockValue;
  final double outstandingDebt;
  final List<TopProduct> topProducts;

  DashboardData({
    this.currency = 'NGN',
    this.period = 'today',
    this.todaySales = 0.0,
    this.grossProfit = 0.0,
    this.cogs = 0.0,
    this.expenses = 0.0,
    this.netProfit = 0.0,
    this.transactions = 0,
    this.lowStock = 0,
    this.outOfStock = 0,
    this.stockValue = 0.0,
    this.outstandingDebt = 0.0,
    this.topProducts = const [],
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    final rawTop = (json['top_products'] as List<dynamic>?) ?? [];
    return DashboardData(
      currency: json['currency'] as String? ?? 'NGN',
      period: json['period'] as String? ?? 'today',
      todaySales: (json['today_sales'] as num?)?.toDouble() ?? 0.0,
      grossProfit: (json['gross_profit'] as num?)?.toDouble() ?? 0.0,
      cogs: (json['cogs'] as num?)?.toDouble() ?? 0.0,
      expenses: (json['expenses'] as num?)?.toDouble() ?? 0.0,
      netProfit: (json['net_profit'] as num?)?.toDouble() ?? 0.0,
      transactions: json['transactions'] as int? ?? 0,
      lowStock: json['low_stock'] as int? ?? 0,
      outOfStock: json['out_of_stock'] as int? ?? 0,
      stockValue: (json['stock_value'] as num?)?.toDouble() ?? 0.0,
      outstandingDebt: (json['outstanding_debt'] as num?)?.toDouble() ?? 0.0,
      topProducts: rawTop.map((item) => TopProduct.fromJson(item as Map<String, dynamic>)).toList(),
    );
  }
}

class ProfitLossData {
  final String period;
  final String currency;
  final double revenue;
  final double cogs;
  final double grossProfit;
  final double operatingExpenses;
  final double netProfit;
  final List<Map<String, dynamic>> expenseBreakdown;

  ProfitLossData({
    required this.period,
    this.currency = 'NGN',
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    required this.operatingExpenses,
    required this.netProfit,
    required this.expenseBreakdown,
  });

  factory ProfitLossData.fromJson(Map<String, dynamic> json) => ProfitLossData(
        period: json['period'] as String? ?? 'this_month',
        currency: json['currency'] as String? ?? 'NGN',
        revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
        cogs: (json['cogs'] as num?)?.toDouble() ?? 0.0,
        grossProfit: (json['gross_profit'] as num?)?.toDouble() ?? 0.0,
        operatingExpenses: (json['operating_expenses'] as num?)?.toDouble() ?? 0.0,
        netProfit: (json['net_profit'] as num?)?.toDouble() ?? 0.0,
        expenseBreakdown: (json['expense_breakdown'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [],
      );
}
