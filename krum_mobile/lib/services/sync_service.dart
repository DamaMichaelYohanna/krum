import 'dart:convert';
import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'api_service.dart';

enum SyncStatus { synced, pending, syncing, failed }

class SyncService extends ChangeNotifier {
  final ApiService api;
  final _uuid = const Uuid();

  SyncStatus _status = SyncStatus.synced;
  String _errorMessage = '';
  DateTime? _lastSyncTime;

  // In-memory caches backed by local storage
  List<Product> products = [];
  List<Category> categories = [];
  List<Unit> units = [];
  List<Customer> customers = [];
  List<Supplier> suppliers = [];
  Business? currentBusiness;

  // Queued offline items
  final List<Map<String, dynamic>> _pendingSales = [];
  final List<Map<String, dynamic>> _pendingPurchases = [];
  final List<Map<String, dynamic>> _pendingPayments = [];
  final List<Map<String, dynamic>> _pendingAdjustments = [];
  final List<Map<String, dynamic>> _pendingExpenses = [];

  // Local history for offline dashboard & analytics
  final List<Map<String, dynamic>> _localSales = [];
  final List<Map<String, dynamic>> _localExpenses = [];

  SyncService({required this.api});

  SyncStatus get status => _status;
  String get errorMessage => _errorMessage;
  DateTime? get lastSyncTime => _lastSyncTime;
  List<Map<String, dynamic>> get pendingSales => _pendingSales;
  List<Map<String, dynamic>> get localSales => _localSales;
  List<Map<String, dynamic>> get pendingExpenses => _pendingExpenses;
  List<Map<String, dynamic>> get localExpenses => _localExpenses;
  int get pendingCount =>
      _pendingSales.length +
      _pendingPurchases.length +
      _pendingPayments.length +
      _pendingAdjustments.length +
      _pendingExpenses.length;

  Future<void> init() async {
    await _loadFromLocal();
    if (api.isAuthenticated) {
      await sync();
    }
  }

  // --- Offline Queuing ---

  Future<String> enqueueSale({
    int? customerId,
    required List<CartItem> cartItems,
    required double amountPaid,
    required double discount,
  }) async {
    final clientTransactionId = _uuid.v4();

    final itemsPayload = cartItems.map((item) {
      return {
        'product_id': item.product.id,
        'product_name': item.product.name,
        'product_unit': item.selectedUnit.id,
        'unit_name': item.selectedUnit.unitName,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'total': item.total,
        'cost_price': item.product.averageCost > 0 ? item.product.averageCost : item.selectedUnit.costPrice,
        'conversion_to_base': item.selectedUnit.conversionToBase,
      };
    }).toList();

    final totalSalesAmount = cartItems.fold<double>(0.0, (acc, item) => acc + item.total) - discount;
    final totalCogs = cartItems.fold<double>(0.0, (acc, item) {
      final unitCost = item.product.averageCost > 0 ? item.product.averageCost : item.selectedUnit.costPrice;
      return acc + (unitCost * item.requiredBaseQuantity);
    });

    String? customerName;
    if (customerId != null) {
      final cust = customers.firstWhere((c) => c.id == customerId, orElse: () => Customer(id: customerId, name: ''));
      if (cust.name.isNotEmpty) customerName = cust.name;
    }

    final salePayload = <String, dynamic>{
      'client_transaction_id': clientTransactionId,
      'customer_id': customerId,
      'customer_name': ?customerName,
      'items': itemsPayload,
      'total_amount': totalSalesAmount,
      'cogs': totalCogs,
      'amount_paid': amountPaid,
      'discount': discount,
      'created_at': DateTime.now().toIso8601String(),
    };

    _pendingSales.add(salePayload);
    _localSales.add(salePayload);

    // Apply immediate local stock deduction
    for (final item in cartItems) {
      final p = products.firstWhere((prod) => prod.id == item.product.id, orElse: () => item.product);
      p.stockBase -= item.requiredBaseQuantity;
    }

    // Apply immediate customer debt increment if partial payment
    if (customerId != null) {
      final total = cartItems.fold<double>(0.0, (acc, item) => acc + item.total) - discount;
      final remainingDebt = total - amountPaid;
      if (remainingDebt > 0) {
        final cust = customers.firstWhere((c) => c.id == customerId, orElse: () => Customer(id: customerId, name: ''));
        cust.outstanding += remainingDebt;
      }
    }

    await _saveLocal();
    _updateStatus(SyncStatus.pending);
    notifyListeners();

    // Trigger async sync in background
    sync();

    return clientTransactionId;
  }

  Future<String> enqueuePurchase({
    int? supplierId,
    required int productUnitId,
    required int productId,
    required double quantity,
    required double unitCost,
    required double amountPaid,
    double? newSellingPrice,
    String reference = '',
  }) async {
    final clientTransactionId = _uuid.v4();

    final purchasePayload = {
      'client_transaction_id': clientTransactionId,
      'supplier_id': supplierId,
      'items': [
        {
          'product_unit': productUnitId,
          'quantity': quantity,
          'unit_cost': unitCost,
          if (newSellingPrice != null && newSellingPrice > 0)
            'selling_price': newSellingPrice,
        }
      ],
      'amount_paid': amountPaid,
      'reference': reference,
      'created_at': DateTime.now().toIso8601String(),
    };

    _pendingPurchases.add(purchasePayload);

    // Apply immediate local stock addition and cost price updates
    final pIndex = products.indexWhere((prod) => prod.id == productId);
    if (pIndex != -1) {
      final p = products[pIndex];
      final uIndex = p.units.indexWhere((unit) => unit.id == productUnitId);
      final u = uIndex != -1 ? p.units[uIndex] : p.baseUnit;

      final quantityBase = quantity * u.conversionToBase;
      final costPerBase = u.conversionToBase > 0 ? (unitCost / u.conversionToBase) : unitCost;

      // Moving weighted average cost calculation
      if (p.stockBase > 0 && p.averageCost > 0) {
        final oldValue = p.stockBase * p.averageCost;
        final newValue = quantityBase * costPerBase;
        final newStock = p.stockBase + quantityBase;
        if (newStock > 0) {
          p.averageCost = (oldValue + newValue) / newStock;
        } else {
          p.averageCost = costPerBase;
        }
      } else {
        p.averageCost = costPerBase;
      }

      p.stockBase += quantityBase;

      // Update costPrice for all units of this product
      for (final unit in p.units) {
        if (unit.id == productUnitId) {
          unit.costPrice = unitCost;
        } else {
          unit.costPrice = p.averageCost * unit.conversionToBase;
        }
        if (newSellingPrice != null && newSellingPrice > 0 && unit.id == productUnitId) {
          unit.sellingPrice = newSellingPrice;
        }
      }
      if (uIndex == -1 && u.conversionToBase == 1.0) {
        u.costPrice = p.averageCost;
      }
    }

    await _saveLocal();
    _updateStatus(SyncStatus.pending);
    notifyListeners();

    sync();
    return clientTransactionId;
  }

  Future<void> enqueueCustomerPayment({
    required int customerId,
    required double amount,
    String method = 'cash',
    String reference = '',
  }) async {
    final paymentPayload = {
      'customer_id': customerId,
      'amount': amount,
      'method': method,
      'reference': reference,
      'created_at': DateTime.now().toIso8601String(),
    };

    _pendingPayments.add(paymentPayload);

    // Immediately decrease customer outstanding balance locally
    final cust = customers.firstWhere((c) => c.id == customerId, orElse: () => Customer(id: customerId, name: ''));
    cust.outstanding = (cust.outstanding - amount).clamp(0.0, double.infinity);

    await _saveLocal();
    _updateStatus(SyncStatus.pending);
    notifyListeners();

    sync();
  }

  Future<void> enqueueAdjustment({
    required int productId,
    required double quantityDelta,
    required String reason,
    String reference = '',
  }) async {
    final adjustmentPayload = {
      'product_id': productId,
      'quantity_delta': quantityDelta,
      'reason': reason,
      'reference': reference,
      'created_at': DateTime.now().toIso8601String(),
    };

    _pendingAdjustments.add(adjustmentPayload);

    // Immediately adjust product stock locally
    final p = products.firstWhere((prod) => prod.id == productId, orElse: () => Product(id: productId, name: '', baseUnitId: 0, baseUnitName: '', units: []));
    p.stockBase += quantityDelta;

    await _saveLocal();
    _updateStatus(SyncStatus.pending);
    notifyListeners();

    sync();
  }

  Future<void> enqueueExpense({
    required String category,
    required double amount,
    String description = '',
    String? occurredAt,
  }) async {
    final clientTransactionId = _uuid.v4();
    final expensePayload = {
      'client_transaction_id': clientTransactionId,
      'category': category,
      'amount': amount,
      'description': description,
      'occurred_at': occurredAt ?? DateTime.now().toIso8601String().substring(0, 10),
      'created_at': DateTime.now().toIso8601String(),
    };

    _pendingExpenses.add(expensePayload);
    _localExpenses.add(expensePayload);

    await _saveLocal();
    _updateStatus(SyncStatus.pending);
    notifyListeners();

    sync();
  }

  Future<void> deleteExpense({int? id, String? createdAt, String? occurredAt, double? amount}) async {
    _localExpenses.removeWhere((e) {
      if (id != null && e['id'] == id) return true;
      if (createdAt != null && e['created_at'] == createdAt) return true;
      if (occurredAt != null && amount != null && e['occurred_at'] == occurredAt && (e['amount'] as num?)?.toDouble() == amount) return true;
      return false;
    });
    _pendingExpenses.removeWhere((e) {
      if (id != null && e['id'] == id) return true;
      if (createdAt != null && e['created_at'] == createdAt) return true;
      if (occurredAt != null && amount != null && e['occurred_at'] == occurredAt && (e['amount'] as num?)?.toDouble() == amount) return true;
      return false;
    });
    await _saveLocal();
    notifyListeners();

    if (id != null && api.isAuthenticated) {
      try {
        await api.deleteExpense(id);
      } catch (_) {}
    }
  }

  void mergeRemoteExpenses(List<Map<String, dynamic>> remoteExpenses) {
    final Set<dynamic> existingIds = {};
    for (final e in _localExpenses) {
      if (e['id'] != null) existingIds.add(e['id']);
    }

    for (final item in remoteExpenses) {
      if (item['id'] != null && !existingIds.contains(item['id'])) {
        _localExpenses.add(item);
        existingIds.add(item['id']);
      }
    }
    _saveLocal();
    notifyListeners();
  }

  void mergeRemoteSales(List<Map<String, dynamic>> remoteSales) {
    final Set<String> existingKeys = {};
    for (final s in _localSales) {
      final txId = s['client_transaction_id']?.toString();
      if (txId != null && txId.isNotEmpty) existingKeys.add(txId);
      final id = s['id']?.toString();
      if (id != null) existingKeys.add('id_$id');
    }

    for (final sale in remoteSales) {
      final txId = sale['client_transaction_id']?.toString();
      final id = sale['id']?.toString();
      final hasTx = txId != null && existingKeys.contains(txId);
      final hasId = id != null && existingKeys.contains('id_$id');

      if (!hasTx && !hasId) {
        _localSales.add(sale);
        if (txId != null) existingKeys.add(txId);
        if (id != null) existingKeys.add('id_$id');
      }
    }
    _saveLocal();
    notifyListeners();
  }

  Future<bool> reverseSaleLocally(Map<String, dynamic> sale) async {
    final txId = sale['client_transaction_id']?.toString();
    final saleId = sale['id'];
    final lookupKey = saleId != null ? saleId.toString() : txId;

    // 1. Mark status as reversed in _localSales
    for (final s in _localSales) {
      if ((txId != null && txId.isNotEmpty && s['client_transaction_id']?.toString() == txId) ||
          (saleId != null && s['id'] == saleId)) {
        s['status'] = 'reversed';
      }
    }

    // 2. If it was pending in _pendingSales, remove it from queue so it's not pushed as completed
    _pendingSales.removeWhere((s) {
      if (txId != null && txId.isNotEmpty && s['client_transaction_id']?.toString() == txId) return true;
      if (saleId != null && s['id'] == saleId) return true;
      return false;
    });

    // 3. Restore product stock locally
    final rawItems = sale['items'] as List<dynamic>? ?? [];
    for (final it in rawItems) {
      if (it is! Map) continue;
      final m = it as Map<String, dynamic>;
      final pId = m['product_id'] ?? (m['product'] is Map ? m['product']['id'] : m['product']);
      final qty = (m['quantity'] as num?)?.toDouble() ?? 0.0;
      final conv = (m['conversion_to_base'] as num?)?.toDouble() ?? 1.0;
      final puId = m['product_unit'] is int ? m['product_unit'] as int : (m['product_unit'] is Map ? m['product_unit']['id'] as int? : null);

      Product? targetProduct;
      if (pId != null) {
        targetProduct = products.firstWhere((prod) => prod.id == pId, orElse: () => Product(id: 0, name: '', baseUnitId: 0, baseUnitName: '', units: []));
      }
      if (targetProduct == null || targetProduct.id == 0) {
        if (puId != null) {
          for (final p in products) {
            if (p.units.any((u) => u.id == puId) || p.baseUnitId == puId) {
              targetProduct = p;
              break;
            }
          }
        }
      }

      if (targetProduct != null && targetProduct.id != 0) {
        targetProduct.stockBase += (qty * conv);
      }
    }

    // 4. If customer debt was created, deduct debt from customer locally
    final customerId = sale['customer_id'] ?? (sale['customer'] is Map ? sale['customer']['id'] : sale['customer']);
    final total = (sale['total_amount'] ?? sale['total'] as num?)?.toDouble() ?? 0.0;
    final amountPaid = (sale['amount_paid'] as num?)?.toDouble() ?? 0.0;
    final debt = total - amountPaid;
    if (customerId != null && debt > 0) {
      final cust = customers.firstWhere((c) => c.id == customerId, orElse: () => Customer(id: 0, name: ''));
      if (cust.id != 0) {
        cust.outstanding = (cust.outstanding - debt).clamp(0.0, double.infinity);
      }
    }

    await _saveLocal();
    notifyListeners();

    // 5. If online, notify server
    if (api.isAuthenticated && lookupKey != null) {
      try {
        await api.reverseSale(lookupKey);
      } catch (_) {}
    }

    return true;
  }

  Future<void> updateBusinessLocally({required String name, String? phone, String? currency}) async {
    if (currentBusiness != null) {
      currentBusiness = currentBusiness!.copyWith(
        name: name,
        phone: phone ?? currentBusiness!.phone,
        currency: currency ?? currentBusiness!.currency,
      );
    } else {
      currentBusiness = Business(
        id: 1,
        name: name,
        phone: phone ?? '',
        currency: currency ?? 'NGN',
      );
    }
    await _saveLocal();
    notifyListeners();

    if (api.isAuthenticated) {
      try {
        final res = await api.updateBusinessProfile({
          'name': name,
          if (phone != null) 'phone': phone,
          if (currency != null) 'currency': currency,
        });
        currentBusiness = Business.fromJson(res);
        await _saveLocal();
        notifyListeners();
      } catch (_) {}
    }
  }

  // --- Synchronization Engine ---

  Future<bool> sync() async {
    if (!api.isAuthenticated) return false;
    if (_status == SyncStatus.syncing) return false;

    _updateStatus(SyncStatus.syncing);

    try {
      // 1. Push any queued transactions
      if (pendingCount > 0) {
        final pushPayload = {
          'sales': List<Map<String, dynamic>>.from(_pendingSales),
          'purchases': List<Map<String, dynamic>>.from(_pendingPurchases),
          'customer_payments': List<Map<String, dynamic>>.from(_pendingPayments),
          'stock_adjustments': List<Map<String, dynamic>>.from(_pendingAdjustments),
          'expenses': List<Map<String, dynamic>>.from(_pendingExpenses),
        };

        await api.syncPush(pushPayload);

        // Remove successfully processed items
        _pendingSales.clear();
        _pendingPurchases.clear();
        _pendingPayments.clear();
        _pendingAdjustments.clear();
        _pendingExpenses.clear();
      }

      // 2. Pull fresh catalog, balances, and debtors
      final pullData = await api.syncPull();
      _hydrateFromPull(pullData);

      _lastSyncTime = DateTime.now();
      _errorMessage = '';
      _updateStatus(pendingCount == 0 ? SyncStatus.synced : SyncStatus.pending);
      await _saveLocal();
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _updateStatus(SyncStatus.failed);
      notifyListeners();
      return false;
    }
  }

  void _hydrateFromPull(Map<String, dynamic> data) {
    if (data.containsKey('business')) {
      currentBusiness = Business.fromJson(data['business'] as Map<String, dynamic>);
    }

    if (data.containsKey('categories')) {
      categories = (data['categories'] as List<dynamic>)
          .map((c) => Category.fromJson(c as Map<String, dynamic>))
          .toList();
    }

    if (data.containsKey('units')) {
      units = (data['units'] as List<dynamic>)
          .map((u) => Unit.fromJson(u as Map<String, dynamic>))
          .toList();
    }

    if (data.containsKey('products')) {
      products = (data['products'] as List<dynamic>)
          .map((p) => Product.fromJson(p as Map<String, dynamic>))
          .toList();
    }

    if (data.containsKey('customers')) {
      customers = (data['customers'] as List<dynamic>)
          .map((c) => Customer.fromJson(c as Map<String, dynamic>))
          .toList();
    }

    if (data.containsKey('suppliers')) {
      suppliers = (data['suppliers'] as List<dynamic>)
          .map((s) => Supplier.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    if (data.containsKey('expenses')) {
      final list = (data['expenses'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      mergeRemoteExpenses(list);
    }

    if (data.containsKey('sales')) {
      final list = (data['sales'] as List<dynamic>)
          .map((s) => s as Map<String, dynamic>)
          .toList();
      mergeRemoteSales(list);
    }
  }

  void _updateStatus(SyncStatus newStatus) {
    _status = newStatus;
  }

  // --- Local Persistence (Offline Storage) ---

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();

    if (currentBusiness != null) {
      await prefs.setString('cached_business', jsonEncode(currentBusiness!.toJson()));
    }
    await prefs.setString('cached_categories', jsonEncode(categories.map((c) => c.toJson()).toList()));
    await prefs.setString('cached_units', jsonEncode(units.map((u) => u.toJson()).toList()));
    await prefs.setString('cached_products', jsonEncode(products.map((p) => p.toJson()).toList()));
    await prefs.setString('cached_customers', jsonEncode(customers.map((c) => c.toJson()).toList()));
    await prefs.setString('cached_suppliers', jsonEncode(suppliers.map((s) => s.toJson()).toList()));

    // Queues
    await prefs.setStringList('queue_sales', _pendingSales.map(jsonEncode).toList());
    await prefs.setStringList('queue_purchases', _pendingPurchases.map(jsonEncode).toList());
    await prefs.setStringList('queue_payments', _pendingPayments.map(jsonEncode).toList());
    await prefs.setStringList('queue_adjustments', _pendingAdjustments.map(jsonEncode).toList());
    await prefs.setStringList('queue_expenses', _pendingExpenses.map(jsonEncode).toList());

    // Local History
    await prefs.setStringList('local_sales_history', _localSales.map(jsonEncode).toList());
    await prefs.setStringList('local_expenses_history', _localExpenses.map(jsonEncode).toList());
  }

  Future<void> _loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();

    final rawBiz = prefs.getString('cached_business');
    if (rawBiz != null) {
      currentBusiness = Business.fromJson(jsonDecode(rawBiz) as Map<String, dynamic>);
    }

    final rawCats = prefs.getString('cached_categories');
    if (rawCats != null) {
      categories = (jsonDecode(rawCats) as List<dynamic>)
          .map((c) => Category.fromJson(c as Map<String, dynamic>))
          .toList();
    }

    final rawUnits = prefs.getString('cached_units');
    if (rawUnits != null) {
      units = (jsonDecode(rawUnits) as List<dynamic>)
          .map((u) => Unit.fromJson(u as Map<String, dynamic>))
          .toList();
    }

    final rawProds = prefs.getString('cached_products');
    if (rawProds != null) {
      products = (jsonDecode(rawProds) as List<dynamic>)
          .map((p) => Product.fromJson(p as Map<String, dynamic>))
          .toList();
    }

    final rawCusts = prefs.getString('cached_customers');
    if (rawCusts != null) {
      customers = (jsonDecode(rawCusts) as List<dynamic>)
          .map((c) => Customer.fromJson(c as Map<String, dynamic>))
          .toList();
    }

    final rawSupps = prefs.getString('cached_suppliers');
    if (rawSupps != null) {
      suppliers = (jsonDecode(rawSupps) as List<dynamic>)
          .map((s) => Supplier.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    // Queues
    _pendingSales.clear();
    _pendingSales.addAll((prefs.getStringList('queue_sales') ?? [])
        .map((s) => jsonDecode(s) as Map<String, dynamic>));

    _pendingPurchases.clear();
    _pendingPurchases.addAll((prefs.getStringList('queue_purchases') ?? [])
        .map((s) => jsonDecode(s) as Map<String, dynamic>));

    _pendingPayments.clear();
    _pendingPayments.addAll((prefs.getStringList('queue_payments') ?? [])
        .map((s) => jsonDecode(s) as Map<String, dynamic>));

    _pendingAdjustments.clear();
    _pendingAdjustments.addAll((prefs.getStringList('queue_adjustments') ?? [])
        .map((s) => jsonDecode(s) as Map<String, dynamic>));

    _pendingExpenses.clear();
    _pendingExpenses.addAll((prefs.getStringList('queue_expenses') ?? [])
        .map((s) => jsonDecode(s) as Map<String, dynamic>));

    // Local History (merge pending sales & expenses if not yet in local history)
    _localSales.clear();
    final rawSales = prefs.getStringList('local_sales_history');
    if (rawSales != null) {
      _localSales.addAll(rawSales.map((s) => jsonDecode(s) as Map<String, dynamic>));
    }
    for (final s in _pendingSales) {
      final txId = s['client_transaction_id'];
      if (!_localSales.any((ls) => ls['client_transaction_id'] == txId)) {
        _localSales.add(s);
      }
    }

    _localExpenses.clear();
    final rawExpenses = prefs.getStringList('local_expenses_history');
    if (rawExpenses != null) {
      _localExpenses.addAll(rawExpenses.map((s) => jsonDecode(s) as Map<String, dynamic>));
    }
    for (final e in _pendingExpenses) {
      if (!_localExpenses.contains(e)) {
        _localExpenses.add(e);
      }
    }

    if (pendingCount > 0) {
      _status = SyncStatus.pending;
    }

    // Default Seed Data (Offline-First initial setup)
    bool needSave = false;
    if (currentBusiness == null) {
      currentBusiness = Business(id: 1, name: 'Krum Store', currency: 'NGN', phone: '');
      needSave = true;
    }

    if (units.isEmpty) {
      units = [
        Unit(id: 1, name: 'Piece', symbol: 'pcs'),
        Unit(id: 2, name: 'Carton', symbol: 'ctn'),
        Unit(id: 3, name: 'Pack', symbol: 'pk'),
        Unit(id: 4, name: 'Bag', symbol: 'bag'),
        Unit(id: 5, name: 'Crate', symbol: 'crt'),
        Unit(id: 6, name: 'Mudu', symbol: 'mudu'),
        Unit(id: 7, name: 'Bottle', symbol: 'btl'),
        Unit(id: 8, name: 'Kilogram', symbol: 'kg'),
        Unit(id: 9, name: 'Dozen', symbol: 'dz'),
      ];
      needSave = true;
    }

    if (categories.isEmpty) {
      categories = [
        Category(id: 1, name: 'General'),
        Category(id: 2, name: 'Beverages & Drinks'),
        Category(id: 3, name: 'Food & Groceries'),
        Category(id: 4, name: 'Toiletries & Personal Care'),
        Category(id: 5, name: 'Snacks & Confectionery'),
      ];
      needSave = true;
    }

    if (needSave) {
      await _saveLocal();
    }
  }

  // --- Local Management (Offline-First CRUD) ---

  Future<void> saveLocal() => _saveLocal();

  Future<Category> addCategoryLocally(String name) async {
    final nextId = categories.isEmpty
        ? 1
        : (categories.map((c) => c.id).reduce((a, b) => a > b ? a : b) + 1);
    final newCat = Category(id: nextId, name: name.trim());
    categories.add(newCat);
    await _saveLocal();
    notifyListeners();
    return newCat;
  }

  Future<bool> deleteCategoryLocally(int id) async {
    categories.removeWhere((c) => c.id == id);
    for (int i = 0; i < products.length; i++) {
      if (products[i].categoryId == id) {
        products[i] = products[i].copyWith(categoryId: null, categoryName: null);
      }
    }
    await _saveLocal();
    notifyListeners();
    return true;
  }

  Future<Unit> addUnitLocally(String name, {String symbol = ''}) async {
    final nextId = units.isEmpty
        ? 1
        : (units.map((u) => u.id).reduce((a, b) => a > b ? a : b) + 1);
    final newUnit = Unit(id: nextId, name: name.trim(), symbol: symbol.trim());
    units.add(newUnit);
    await _saveLocal();
    notifyListeners();
    return newUnit;
  }

  Future<bool> deleteUnitLocally(int id) async {
    final inUse = products.any((p) => p.baseUnitId == id || p.units.any((u) => u.unitId == id));
    if (inUse) return false;
    units.removeWhere((u) => u.id == id);
    await _saveLocal();
    notifyListeners();
    return true;
  }

  Product? findProduct(String rawCode) {
    final code = rawCode.trim();
    if (code.isEmpty) return null;
    final lower = code.toLowerCase();
    final noZeros = lower.replaceFirst(RegExp(r'^0+'), '');

    bool matches(Product p) {
      final pBarcode = p.barcode.trim().toLowerCase();
      final pSku = p.sku.trim().toLowerCase();
      final pId = p.id.toString();

      // 1. Direct exact matches
      if (pBarcode.isNotEmpty && pBarcode == lower) return true;
      if (pSku.isNotEmpty && pSku == lower) return true;
      if (pId == lower) return true;

      // 2. Normalized leading zeros (e.g. UPC-A 12-digit vs EAN-13 13-digit)
      if (noZeros.isNotEmpty) {
        final bNoZero = pBarcode.replaceFirst(RegExp(r'^0+'), '');
        final sNoZero = pSku.replaceFirst(RegExp(r'^0+'), '');
        if (bNoZero.isNotEmpty && bNoZero == noZeros) return true;
        if (sNoZero.isNotEmpty && sNoZero == noZeros) return true;
      }

      // 3. Exact name match
      if (p.name.trim().toLowerCase() == lower) return true;

      return false;
    }

    // Prioritize active products first
    for (final p in products) {
      if (p.active && matches(p)) return p;
    }
    // Fallback to inactive products
    for (final p in products) {
      if (!p.active && matches(p)) return p;
    }
    return null;
  }

  Future<Product> addProductLocally({
    required String name,
    required int baseUnitId,
    String sku = '',
    String barcode = '',
    int? categoryId,
    String brand = '',
    double reorderLevel = 0.0,
    double sellingPrice = 0.0,
    double costPrice = 0.0,
    double openingStock = 0.0,
    List<Map<String, dynamic>> alternativeUnits = const [],
  }) async {
    final cleanBarcode = barcode.trim();
    final cleanSku = sku.trim();

    final nextProductId = products.isEmpty
        ? 1
        : (products.map((p) => p.id).reduce((a, b) => a > b ? a : b) + 1);

    final finalSku = cleanSku.isNotEmpty
        ? cleanSku
        : (cleanBarcode.isNotEmpty
            ? cleanBarcode
            : 'PRD-${nextProductId.toString().padLeft(4, '0')}');

    final finalBarcode = cleanBarcode.isNotEmpty ? cleanBarcode : cleanSku;

    final baseUnitObj = units.firstWhere(
      (u) => u.id == baseUnitId,
      orElse: () => Unit(id: baseUnitId, name: 'Piece', symbol: 'pcs'),
    );

    String? categoryName;
    if (categoryId != null) {
      final match = categories.where((c) => c.id == categoryId);
      if (match.isNotEmpty) {
        categoryName = match.first.name;
      }
    }

    int nextUnitId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final List<ProductUnit> productUnits = [
      ProductUnit(
        id: nextUnitId++,
        unitId: baseUnitId,
        unitName: baseUnitObj.name,
        conversionToBase: 1.0,
        costPrice: costPrice,
        sellingPrice: sellingPrice,
        minimumPrice: costPrice,
      ),
    ];

    for (final alt in alternativeUnits) {
      final altUnitId = alt['unit_id'] as int;
      final altUnitName = alt['unit_name'] as String? ??
          units.firstWhere((u) => u.id == altUnitId, orElse: () => Unit(id: altUnitId, name: 'Unit')).name;
      final conversion = (alt['conversion_to_base'] as num).toDouble();
      final altSelling = (alt['selling_price'] as num).toDouble();
      final altCost = (alt['cost_price'] as num?)?.toDouble() ?? (costPrice * conversion);

      productUnits.add(ProductUnit(
        id: nextUnitId++,
        unitId: altUnitId,
        unitName: altUnitName,
        conversionToBase: conversion,
        costPrice: altCost,
        sellingPrice: altSelling,
        minimumPrice: altCost,
      ));
    }

    final newProduct = Product(
      id: nextProductId,
      name: name.trim(),
      sku: finalSku,
      barcode: finalBarcode,
      categoryId: categoryId,
      categoryName: categoryName,
      baseUnitId: baseUnitId,
      baseUnitName: baseUnitObj.name,
      brand: brand.trim(),
      reorderLevel: reorderLevel,
      stockBase: openingStock,
      averageCost: costPrice,
      units: productUnits,
      active: true,
    );

    products.add(newProduct);
    await _saveLocal();
    notifyListeners();
    return newProduct;
  }

  Future<bool> updateProductLocally(Product updated) async {
    final cleanBarcode = updated.barcode.trim();
    final cleanSku = updated.sku.trim();
    final finalBarcode = cleanBarcode.isNotEmpty ? cleanBarcode : cleanSku;
    final finalSku = cleanSku.isNotEmpty ? cleanSku : (cleanBarcode.isNotEmpty ? cleanBarcode : updated.sku);

    final normalized = updated.copyWith(
      name: updated.name.trim(),
      barcode: finalBarcode,
      sku: finalSku,
    );

    final index = products.indexWhere((p) => p.id == updated.id);
    if (index != -1) {
      products[index] = normalized;
      await _saveLocal();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> deleteProductLocally(int id) async {
    products.removeWhere((p) => p.id == id);
    await _saveLocal();
    notifyListeners();
    return true;
  }

  // --- Customer & Supplier Local Offline CRUD ---

  Future<Customer> addCustomerLocally(
    String name, {
    String phone = '',
    double initialDebt = 0.0,
  }) async {
    final nextId = customers.isEmpty
        ? 1
        : (customers.map((c) => c.id).reduce((a, b) => a > b ? a : b) + 1);
    final newCustomer = Customer(
      id: nextId,
      name: name.trim(),
      phone: phone.trim(),
      outstanding: initialDebt,
    );
    customers.add(newCustomer);
    await _saveLocal();
    notifyListeners();
    return newCustomer;
  }

  Future<bool> updateCustomerLocally(Customer updated) async {
    final index = customers.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      customers[index] = updated;
      await _saveLocal();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> deleteCustomerLocally(int id) async {
    customers.removeWhere((c) => c.id == id);
    await _saveLocal();
    notifyListeners();
    return true;
  }

  Future<Supplier> addSupplierLocally(String name, {String phone = ''}) async {
    final nextId = suppliers.isEmpty
        ? 1
        : (suppliers.map((s) => s.id).reduce((a, b) => a > b ? a : b) + 1);
    final newSupplier = Supplier(
      id: nextId,
      name: name.trim(),
      phone: phone.trim(),
    );
    suppliers.add(newSupplier);
    await _saveLocal();
    notifyListeners();
    return newSupplier;
  }

  Future<bool> deleteSupplierLocally(int id) async {
    suppliers.removeWhere((s) => s.id == id);
    await _saveLocal();
    notifyListeners();
    return true;
  }
}
