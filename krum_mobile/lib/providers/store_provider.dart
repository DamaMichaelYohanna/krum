import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import 'package:intl/intl.dart';
import '../utils/formatters.dart';

class StoreProvider extends ChangeNotifier {
  final ApiService api;
  final SyncService syncService;

  bool _isLoading = false;
  String _errorMessage = '';
  String _username = '';
  String _userRole = 'owner';

  // Active Cart State
  final List<CartItem> _cart = [];
  double _cartDiscount = 0.0;
  Customer? _selectedCustomer;
  String _paymentMethod = 'cash';

  // Dashboard & Reports State
  DashboardData _dashboard = DashboardData();
  String _dashboardPeriod = 'today';
  ProfitLossData? _profitLoss;

  StoreProvider({required this.api, required this.syncService}) {
    syncService.addListener(() {
      refreshDashboard();
    });
  }

  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  String get username => _username;
  String get userRole => _userRole;
  bool get isOwner => _userRole == 'owner';
  bool get isOwnerOrManager => _userRole == 'owner' || _userRole == 'manager';
  bool get isAuthenticated => api.isAuthenticated;

  // Sync delegations
  SyncStatus get syncStatus => syncService.status;
  int get pendingSyncCount => syncService.pendingCount;
  String get syncError => syncService.errorMessage;

  // Domain lists from sync cache
  List<Product> get products => syncService.products;
  List<Category> get categories => syncService.categories;
  List<Unit> get units => syncService.units;
  List<Customer> get customers => syncService.customers;
  List<Supplier> get suppliers => syncService.suppliers;
  Business? get business => syncService.currentBusiness;

  // Low Stock & Reordering Getters
  List<Product> get lowStockProducts => products.where((p) => p.active && p.needsRestock).toList();
  List<Product> get outOfStockProducts => products.where((p) => p.active && p.isOutOfStock).toList();
  double get totalRestockBudget => lowStockProducts.fold(0.0, (sum, p) => sum + p.estimatedRestockCost);

  // Cart getters
  List<CartItem> get cart => _cart;
  double get cartDiscount => _cartDiscount;
  Customer? get selectedCustomer => _selectedCustomer;
  String get paymentMethod => _paymentMethod;
  double get cartSubtotal => _cart.fold(0.0, (sum, item) => sum + item.total);
  double get cartTotal => (cartSubtotal - _cartDiscount).clamp(0.0, double.infinity);
  int get cartItemCount => _cart.length;

  DashboardData get dashboard => _dashboard;
  String get dashboardPeriod => _dashboardPeriod;
  ProfitLossData? get profitLoss => _profitLoss;

  Future<void> init() async {
    _setLoading(true);
    await api.init();
    await syncService.init();

    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString('user_username') ?? '';
    _userRole = prefs.getString('user_role') ?? 'owner';

    if (api.isAuthenticated) {
      try {
        final profile = await api.getBusinessProfile();
        _userRole = profile['role'] ?? 'owner';
        await prefs.setString('user_role', _userRole);
      } catch (_) {}
    }
    await refreshDashboard();
    _setLoading(false);
  }

  // --- Authentication ---

  Future<bool> login(String username, String password) async {
    _setLoading(true);
    _errorMessage = '';
    try {
      await api.login(username, password);
      _username = username;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_username', username);

      final profile = await api.getBusinessProfile();
      _userRole = profile['role'] ?? 'owner';
      await prefs.setString('user_role', _userRole);

      await syncService.sync();
      await refreshDashboard();
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  Future<bool> register({
    required String businessName,
    required String username,
    required String password,
    String currency = 'NGN',
    String phone = '',
  }) async {
    _setLoading(true);
    _errorMessage = '';
    try {
      await api.register(
        businessName: businessName,
        username: username,
        password: password,
        currency: currency,
        phone: phone,
      );
      _username = username;
      _userRole = 'owner';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_username', username);
      await prefs.setString('user_role', 'owner');

      await syncService.sync();
      await refreshDashboard();
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  Future<void> logout() async {
    await api.clearAuth();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_username');
    await prefs.remove('user_role');
    _username = '';
    _userRole = 'owner';
    clearCart();
    notifyListeners();
  }

  // --- Cart Management ---

  void addToCart(Product product, {ProductUnit? unit, double quantity = 1.0}) {
    final targetUnit = unit ?? product.baseUnit;
    final existingIndex = _cart.indexWhere(
      (item) =>
          item.product.id == product.id &&
          ((targetUnit.id != 0 && item.selectedUnit.id != 0 && item.selectedUnit.id == targetUnit.id) ||
           (targetUnit.unitId != 0 && item.selectedUnit.unitId != 0 && item.selectedUnit.unitId == targetUnit.unitId) ||
           item.selectedUnit.unitName.toLowerCase() == targetUnit.unitName.toLowerCase()),
    );

    if (existingIndex >= 0) {
      _cart[existingIndex].quantity += quantity;
    } else {
      _cart.add(CartItem(product: product, selectedUnit: targetUnit, quantity: quantity));
    }
    notifyListeners();
  }

  void updateCartQuantity(int index, double qty) {
    if (index >= 0 && index < _cart.length) {
      if (qty <= 0) {
        _cart.removeAt(index);
      } else {
        _cart[index].quantity = qty;
      }
      notifyListeners();
    }
  }

  void updateCartItemUnit(int index, ProductUnit newUnit) {
    if (index >= 0 && index < _cart.length) {
      final currentItem = _cart[index];
      final otherIndex = _cart.indexWhere(
        (it) =>
            !identical(it, currentItem) &&
            it.product.id == currentItem.product.id &&
            ((newUnit.id != 0 && it.selectedUnit.id != 0 && it.selectedUnit.id == newUnit.id) ||
             (newUnit.unitId != 0 && it.selectedUnit.unitId != 0 && it.selectedUnit.unitId == newUnit.unitId) ||
             it.selectedUnit.unitName.toLowerCase() == newUnit.unitName.toLowerCase()),
      );

      if (otherIndex >= 0) {
        _cart[otherIndex].quantity += currentItem.quantity;
        _cart.removeAt(index);
      } else {
        _cart[index].selectedUnit = newUnit;
        _cart[index].customUnitPrice = newUnit.sellingPrice;
      }
      notifyListeners();
    }
  }

  void setCartDiscount(double discount) {
    _cartDiscount = discount;
    notifyListeners();
  }

  void setSelectedCustomer(Customer? customer) {
    _selectedCustomer = customer;
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    _paymentMethod = method;
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _cartDiscount = 0.0;
    _selectedCustomer = null;
    _paymentMethod = 'cash';
    notifyListeners();
  }

  Future<String> checkoutSale({required double amountPaid}) async {
    if (_cart.isEmpty) throw Exception('Cart is empty');

    final txId = await syncService.enqueueSale(
      customerId: _selectedCustomer?.id,
      cartItems: List.from(_cart),
      amountPaid: amountPaid,
      discount: _cartDiscount,
    );

    clearCart();
    await refreshDashboard();
    return txId;
  }

  // --- Inventory & Product Operations ---

  Product? findProduct(String rawCode) => syncService.findProduct(rawCode);

  Future<Product?> findProductOrLookup(String rawCode) async {
    final local = findProduct(rawCode);
    if (local != null) return local;

    if (api.isAuthenticated) {
      try {
        final serverData = await api.lookupBarcode(rawCode.trim());
        if (serverData != null) {
          final serverProd = Product.fromJson(serverData);
          final existingIdx = syncService.products.indexWhere((p) => p.id == serverProd.id);
          if (existingIdx != -1) {
            syncService.products[existingIdx] = serverProd;
          } else {
            syncService.products.add(serverProd);
          }
          await syncService.saveLocal();
          notifyListeners();
          return serverProd;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<bool> createProduct({
    required String name,
    required int baseUnitId,
    String sku = '',
    String barcode = '',
    int? categoryId,
    int? preferredSupplierId,
    String brand = '',
    double reorderLevel = 0.0,
    double sellingPrice = 0.0,
    double costPrice = 0.0,
    double openingStock = 0.0,
    List<Map<String, dynamic>> alternativeUnits = const [],
  }) async {
    _setLoading(true);
    try {
      final product = await syncService.addProductLocally(
        name: name,
        baseUnitId: baseUnitId,
        sku: sku,
        barcode: barcode,
        categoryId: categoryId,
        preferredSupplierId: preferredSupplierId,
        brand: brand,
        reorderLevel: reorderLevel,
        sellingPrice: sellingPrice,
        costPrice: costPrice,
        openingStock: openingStock,
        alternativeUnits: alternativeUnits,
      );

      if (api.isAuthenticated) {
        try {
          await api.createProduct({
            'name': name,
            'sku': product.sku,
            'barcode': barcode,
            'category': categoryId,
            'preferred_supplier': preferredSupplierId,
            'base_unit': baseUnitId,
            'brand': brand,
            'reorder_level': reorderLevel,
            'selling_price': sellingPrice,
            'cost_price': costPrice,
            'opening_stock': openingStock,
          });
          await syncService.sync();
        } catch (_) {}
      }
      await refreshDashboard();
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  Future<bool> updateProduct(Product product) async {
    _setLoading(true);
    try {
      final success = await syncService.updateProductLocally(product);
      await refreshDashboard();
      _setLoading(false);
      return success;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  Future<bool> deleteProduct(int productId) async {
    _setLoading(true);
    try {
      final success = await syncService.deleteProductLocally(productId);
      await refreshDashboard();
      _setLoading(false);
      return success;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  Future<bool> addProductUnit({
    required int productId,
    required int unitId,
    required double conversionToBase,
    required double sellingPrice,
    double costPrice = 0.0,
    double minimumPrice = 0.0,
  }) async {
    _setLoading(true);
    try {
      final pIndex = syncService.products.indexWhere((p) => p.id == productId);
      if (pIndex != -1) {
        final p = syncService.products[pIndex];
        final unitObj = syncService.units.firstWhere((u) => u.id == unitId, orElse: () => Unit(id: unitId, name: 'Unit'));
        final newUnit = ProductUnit(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          unitId: unitId,
          unitName: unitObj.name,
          conversionToBase: conversionToBase,
          costPrice: costPrice,
          sellingPrice: sellingPrice,
          minimumPrice: minimumPrice,
        );
        p.units.add(newUnit);
        await syncService.saveLocal();
        notifyListeners();
      }

      if (api.isAuthenticated) {
        try {
          await api.addProductUnit(productId, {
            'unit': unitId,
            'conversion_to_base': conversionToBase,
            'selling_price': sellingPrice,
            'cost_price': costPrice,
            'minimum_price': minimumPrice,
          });
          await syncService.sync();
        } catch (_) {}
      }
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  Future<Unit?> createCustomUnit(String name, {String symbol = ''}) async {
    _setLoading(true);
    try {
      final unit = await syncService.addUnitLocally(name, symbol: symbol);
      if (api.isAuthenticated) {
        try {
          await api.createUnit(name, symbol: symbol);
          await syncService.sync();
        } catch (_) {}
      }
      _setLoading(false);
      return unit;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return null;
    }
  }

  Future<bool> deleteUnit(int unitId) async {
    return await syncService.deleteUnitLocally(unitId);
  }

  Future<Category?> createCategory(String name) async {
    _setLoading(true);
    try {
      final cat = await syncService.addCategoryLocally(name);
      if (api.isAuthenticated) {
        try {
          await api.createCategory(name);
          await syncService.sync();
        } catch (_) {}
      }
      _setLoading(false);
      return cat;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return null;
    }
  }

  Future<bool> deleteCategory(int categoryId) async {
    return await syncService.deleteCategoryLocally(categoryId);
  }

  Future<void> adjustStock({
    required int productId,
    required double quantityDelta,
    required String reason,
    String reference = '',
  }) async {
    await syncService.enqueueAdjustment(
      productId: productId,
      quantityDelta: quantityDelta,
      reason: reason,
      reference: reference,
    );
    notifyListeners();
  }

  // --- Purchases / Stock Receipt ---

  Future<void> receivePurchase({
    int? supplierId,
    required int productId,
    required int productUnitId,
    required double quantity,
    required double unitCost,
    required double amountPaid,
    double? newSellingPrice,
    String reference = '',
  }) async {
    await syncService.enqueuePurchase(
      supplierId: supplierId,
      productId: productId,
      productUnitId: productUnitId,
      quantity: quantity,
      unitCost: unitCost,
      amountPaid: amountPaid,
      newSellingPrice: newSellingPrice,
      reference: reference,
    );
    await refreshDashboard();
    notifyListeners();
  }

  Future<bool> batchReceiveStock({
    int? supplierId,
    required List<Map<String, dynamic>> items,
    String reference = '',
  }) async {
    _setLoading(true);
    try {
      for (final item in items) {
        final product = item['product'] as Product;
        final unit = item['unit'] as ProductUnit;
        final qty = (item['quantity'] as num).toDouble();
        final unitCost = (item['unit_cost'] as num).toDouble();
        final sellingPrice = (item['selling_price'] as num?)?.toDouble();

        await syncService.enqueuePurchase(
          supplierId: supplierId,
          productId: product.id,
          productUnitId: unit.id,
          quantity: qty,
          unitCost: unitCost,
          amountPaid: qty * unitCost,
          newSellingPrice: sellingPrice,
          reference: reference.isNotEmpty ? reference : 'Bulk Reorder',
        );
      }
      await refreshDashboard();
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  String generatePurchaseOrderText({
    Supplier? supplier,
    required List<Map<String, dynamic>> items,
    String notes = '',
  }) {
    final businessName = business?.name ?? 'Our Store';
    final now = DateTime.now();
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(now);
    final ref = 'PO-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch.toString().substring(8)}';
    final currency = business?.currency ?? 'NGN';

    final buffer = StringBuffer();
    buffer.writeln('📦 *PURCHASE REQUISITION ORDER*');
    buffer.writeln('🏪 Store: *$businessName*');
    if (supplier != null) {
      buffer.writeln('🚚 Supplier: *${supplier.name}*');
      if (supplier.phone.isNotEmpty) buffer.writeln('📞 Contact: ${supplier.phone}');
    }
    buffer.writeln('🗓 Date: $dateStr');
    buffer.writeln('🔖 Order Ref: $ref');
    buffer.writeln('--------------------------------');
    buffer.writeln('*ITEMS REQUESTED:*');

    double grandTotal = 0.0;
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final name = item['name'] ?? 'Product';
      final unitName = item['unit_name'] ?? 'pcs';
      final qty = (item['quantity'] as num).toDouble();
      final cost = (item['unit_cost'] as num).toDouble();
      final subtotal = qty * cost;
      grandTotal += subtotal;

      buffer.writeln('${i + 1}. *$name*');
      buffer.writeln('   Qty: ${CurrencyFormatter.formatQty(qty)} $unitName @ ${CurrencyFormatter.format(cost, currency: currency)} = ${CurrencyFormatter.format(subtotal, currency: currency)}');
    }

    buffer.writeln('--------------------------------');
    buffer.writeln('💰 *Total Estimated Order: ${CurrencyFormatter.format(grandTotal, currency: currency)}*');
    if (notes.trim().isNotEmpty) {
      buffer.writeln('📝 Notes: ${notes.trim()}');
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('Please confirm item availability and delivery schedule.');
    buffer.writeln('Thank you!');
    return buffer.toString();
  }

  // --- Customers & Debt Repayments ---

  Future<Customer?> createCustomer(
    String name, {
    String phone = '',
    double initialDebt = 0.0,
  }) async {
    _setLoading(true);
    try {
      final customer = await syncService.addCustomerLocally(
        name,
        phone: phone,
        initialDebt: initialDebt,
      );

      if (api.isAuthenticated) {
        try {
          await api.createCustomer(name, phone: phone);
        } catch (_) {}
      }

      await refreshDashboard();
      _setLoading(false);
      return customer;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return null;
    }
  }

  Future<bool> updateCustomer(Customer customer) async {
    _setLoading(true);
    try {
      final success = await syncService.updateCustomerLocally(customer);
      await refreshDashboard();
      _setLoading(false);
      return success;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  Future<bool> deleteCustomer(int id) async {
    _setLoading(true);
    try {
      final success = await syncService.deleteCustomerLocally(id);
      await refreshDashboard();
      _setLoading(false);
      return success;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  Future<Supplier?> createSupplier(String name, {String phone = ''}) async {
    _setLoading(true);
    try {
      final supplier = await syncService.addSupplierLocally(name, phone: phone);
      if (api.isAuthenticated) {
        try {
          await api.createSupplier(name, phone: phone);
        } catch (_) {}
      }
      _setLoading(false);
      return supplier;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return null;
    }
  }

  Future<bool> deleteSupplier(int id) async {
    _setLoading(true);
    try {
      final success = await syncService.deleteSupplierLocally(id);
      _setLoading(false);
      return success;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  Future<void> recordCustomerPayment({
    required int customerId,
    required double amount,
    String method = 'cash',
    String reference = '',
  }) async {
    await syncService.enqueueCustomerPayment(
      customerId: customerId,
      amount: amount,
      method: method,
      reference: reference,
    );
    notifyListeners();
  }

  // --- Expenses ---

  List<Expense> get expenses {
    final Map<String, Expense> map = {};

    for (final e in syncService.localExpenses) {
      final key = e['client_transaction_id'] ?? (e['id'] != null ? 'id_${e['id']}' : (e['created_at']?.toString() ?? '${e['category']}_${e['amount']}_${e['occurred_at']}'));
      map[key] = Expense.fromJson(e);
    }

    for (final e in syncService.pendingExpenses) {
      final key = e['client_transaction_id'] ?? (e['id'] != null ? 'id_${e['id']}' : (e['created_at']?.toString() ?? '${e['category']}_${e['amount']}_${e['occurred_at']}'));
      map[key] = Expense.fromJson(e);
    }

    final list = map.values.toList();
    list.sort((a, b) {
      final cmp = b.occurredAt.compareTo(a.occurredAt);
      if (cmp != 0) return cmp;
      final createA = a.createdAt ?? '';
      final createB = b.createdAt ?? '';
      return createB.compareTo(createA);
    });
    return list;
  }

  List<Expense> filterExpenses({
    String period = 'this_month',
    DateTime? startDate,
    DateTime? endDate,
    String? category,
    String? searchQuery,
  }) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final yesterdayEnd = todayStart;
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    return expenses.where((exp) {
      // 1. Category filter
      if (category != null && category.isNotEmpty && category.toLowerCase() != 'all') {
        if (exp.category.toLowerCase() != category.toLowerCase()) {
          return false;
        }
      }

      // 2. Search query filter
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        final matchDesc = exp.description.toLowerCase().contains(q);
        final matchCat = exp.category.toLowerCase().contains(q);
        final matchAmt = exp.amount.toString().contains(q);
        if (!matchDesc && !matchCat && !matchAmt) {
          return false;
        }
      }

      // 3. Date / Period filter
      if (period == 'all') {
        return true;
      }

      DateTime? expDate;
      if (exp.occurredAt.isNotEmpty) {
        final raw = exp.occurredAt.length == 10 ? '${exp.occurredAt}T00:00:00' : exp.occurredAt;
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) {
          expDate = parsed.isUtc ? parsed.toLocal() : parsed;
        }
      }
      if (expDate == null && exp.createdAt != null) {
        final parsed = DateTime.tryParse(exp.createdAt!);
        if (parsed != null) {
          expDate = parsed.isUtc ? parsed.toLocal() : parsed;
        }
      }
      if (expDate == null) return true;

      final dateOnly = DateTime(expDate.year, expDate.month, expDate.day);

      switch (period) {
        case 'today':
          return !dateOnly.isBefore(todayStart) && dateOnly.isBefore(todayEnd);
        case 'yesterday':
          return !dateOnly.isBefore(yesterdayStart) && dateOnly.isBefore(yesterdayEnd);
        case 'this_week':
          return !dateOnly.isBefore(weekStart) && dateOnly.isBefore(todayEnd);
        case 'this_month':
          return !dateOnly.isBefore(monthStart) && dateOnly.isBefore(todayEnd);
        case 'custom':
          if (startDate != null && endDate != null) {
            final s = DateTime(startDate.year, startDate.month, startDate.day);
            final e = DateTime(endDate.year, endDate.month, endDate.day).add(const Duration(days: 1));
            return !dateOnly.isBefore(s) && dateOnly.isBefore(e);
          }
          return true;
        default:
          return true;
      }
    }).toList();
  }

  Future<void> recordExpense({
    required String category,
    required double amount,
    String description = '',
    String? occurredAt,
  }) async {
    await syncService.enqueueExpense(
      category: category,
      amount: amount,
      description: description,
      occurredAt: occurredAt,
    );
    refreshDashboard();
    notifyListeners();
  }

  Future<void> loadExpenses({
    String? period,
    DateTime? startDate,
    DateTime? endDate,
    String? category,
  }) async {
    if (!isAuthenticated) return;
    try {
      final sStr = startDate?.toIso8601String().substring(0, 10);
      final eStr = endDate?.toIso8601String().substring(0, 10);
      final rawList = await api.getExpenses(
        period: period,
        startDate: sStr,
        endDate: eStr,
        category: category,
      );
      final maps = rawList.map((e) => e as Map<String, dynamic>).toList();
      syncService.mergeRemoteExpenses(maps);
      refreshDashboard();
      notifyListeners();
    } catch (_) {
      // Offline fallback: local data is already available
    }
  }

  Future<void> deleteExpense(Expense expense) async {
    await syncService.deleteExpense(
      id: expense.id,
      clientTransactionId: expense.clientTransactionId,
      createdAt: expense.createdAt,
      occurredAt: expense.occurredAt,
      amount: expense.amount,
      category: expense.category,
    );
    refreshDashboard();
    notifyListeners();
  }

  // --- Sales & Transactions History ---

  List<Map<String, dynamic>> get sales {
    final Map<String, Map<String, dynamic>> salesMap = {};
    for (final s in syncService.localSales) {
      final id = s['client_transaction_id']?.toString() ?? s['id']?.toString() ?? s.hashCode.toString();
      salesMap[id] = s;
    }
    for (final s in syncService.pendingSales) {
      final id = s['client_transaction_id']?.toString() ?? s['id']?.toString() ?? s.hashCode.toString();
      salesMap[id] = s;
    }

    final list = salesMap.values.toList();
    list.sort((a, b) {
      final dateA = (a['created_at'] ?? a['completed_at'] ?? '').toString();
      final dateB = (b['created_at'] ?? b['completed_at'] ?? '').toString();
      return dateB.compareTo(dateA);
    });
    return list;
  }

  List<Map<String, dynamic>> filterSales({
    String period = 'this_month',
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final yesterdayEnd = todayStart;
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    return sales.where((sale) {
      // 1. Search Query
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        final txId = (sale['client_transaction_id'] ?? sale['id'] ?? '').toString().toLowerCase();
        final cust = (sale['customer_name'] ?? '').toString().toLowerCase();

        bool itemMatched = false;
        final items = sale['items'] as List<dynamic>? ?? [];
        for (final item in items) {
          if (item is Map) {
            final pName = (item['product_name'] ?? item['product'] ?? '').toString().toLowerCase();
            if (pName.contains(q)) {
              itemMatched = true;
              break;
            }
          }
        }

        if (!txId.contains(q) && !cust.contains(q) && !itemMatched) {
          return false;
        }
      }

      // 2. Date / Period filter
      if (period == 'all') return true;

      final rawDate = (sale['created_at'] ?? sale['completed_at'])?.toString();
      if (rawDate == null || rawDate.isEmpty) return true;
      final normalized = rawDate.length == 10 ? '${rawDate}T00:00:00' : rawDate;
      final parsedDate = DateTime.tryParse(normalized);
      if (parsedDate == null) return true;
      final saleDate = parsedDate.isUtc ? parsedDate.toLocal() : parsedDate;
      final dateOnly = DateTime(saleDate.year, saleDate.month, saleDate.day);

      switch (period) {
        case 'today':
          return !dateOnly.isBefore(todayStart) && dateOnly.isBefore(todayEnd);
        case 'yesterday':
          return !dateOnly.isBefore(yesterdayStart) && dateOnly.isBefore(yesterdayEnd);
        case 'this_week':
          return !dateOnly.isBefore(weekStart) && dateOnly.isBefore(todayEnd);
        case 'this_month':
          return !dateOnly.isBefore(monthStart) && dateOnly.isBefore(todayEnd);
        case 'custom':
          if (startDate != null && endDate != null) {
            final s = DateTime(startDate.year, startDate.month, startDate.day);
            final e = DateTime(endDate.year, endDate.month, endDate.day).add(const Duration(days: 1));
            return !dateOnly.isBefore(s) && dateOnly.isBefore(e);
          }
          return true;
        default:
          return true;
      }
    }).toList();
  }

  List<SoldItemSummary> getItemizedSalesSummary({
    String period = 'this_month',
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) {
    final filtered = filterSales(
      period: period,
      startDate: startDate,
      endDate: endDate,
    );

    final Map<String, _SoldItemAccumulator> map = {};

    for (final sale in filtered) {
      if (sale['status'] == 'reversed') continue;
      final items = sale['items'] as List<dynamic>? ?? [];
      final Set<String> productsInThisSale = {};

      for (final raw in items) {
        if (raw is Map<String, dynamic>) {
          final pId = raw['product_id'] as int? ?? 0;
          final pName = raw['product_name'] as String? ?? raw['product'] as String? ?? 'Item';
          final uName = raw['unit_name'] as String? ?? raw['unit'] as String? ?? '';
          final qty = (raw['quantity'] as num?)?.toDouble() ?? 0.0;
          final total = (raw['total'] as num?)?.toDouble() ??
              (qty * ((raw['unit_price'] as num?)?.toDouble() ?? 0.0));

          final key = '$pId-$pName-$uName';
          final acc = map.putIfAbsent(
            key,
            () => _SoldItemAccumulator(
              productId: pId,
              productName: pName,
              unitName: uName,
            ),
          );
          acc.quantitySold += qty;
          acc.totalRevenue += total;

          if (!productsInThisSale.contains(key)) {
            acc.transactionCount += 1;
            productsInThisSale.add(key);
          }
        }
      }
    }

    var list = map.values.map((a) {
      final avg = a.quantitySold > 0 ? (a.totalRevenue / a.quantitySold) : 0.0;
      return SoldItemSummary(
        productId: a.productId,
        productName: a.productName,
        unitName: a.unitName,
        quantitySold: a.quantitySold,
        totalRevenue: a.totalRevenue,
        transactionCount: a.transactionCount,
        averagePrice: avg,
      );
    }).toList();

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase().trim();
      list = list.where((item) => item.productName.toLowerCase().contains(q)).toList();
    }

    list.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    return list;
  }

  Future<void> loadSales({
    String? period,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (!isAuthenticated) return;
    try {
      final sStr = startDate?.toIso8601String().substring(0, 10);
      final eStr = endDate?.toIso8601String().substring(0, 10);
      final rawList = await api.getSales(
        period: period,
        startDate: sStr,
        endDate: eStr,
      );
      final maps = rawList.map((s) => s as Map<String, dynamic>).toList();
      syncService.mergeRemoteSales(maps);
      refreshDashboard();
      notifyListeners();
    } catch (_) {
      // Offline fallback
    }
  }

  Future<bool> reverseSale(Map<String, dynamic> sale) async {
    _setLoading(true);
    try {
      final success = await syncService.reverseSaleLocally(sale);
      await refreshDashboard();
      _setLoading(false);
      return success;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  Future<bool> updateBusinessProfile({
    required String name,
    String? phone,
    String? currency,
  }) async {
    _setLoading(true);
    try {
      await syncService.updateBusinessLocally(
        name: name,
        phone: phone,
        currency: currency,
      );
      await refreshDashboard();
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  // --- Dashboard & Analytics ---

  Future<void> setDashboardPeriod(String period) async {
    _dashboardPeriod = period;
    await refreshDashboard();
  }

  Future<void> refreshDashboard() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final yesterdayEnd = todayStart;
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    // Merge local sales and pending sales, deduplicating by transaction id
    final Map<String, Map<String, dynamic>> salesMap = {};
    for (final s in syncService.localSales) {
      final id = s['client_transaction_id']?.toString() ?? s.hashCode.toString();
      salesMap[id] = s;
    }
    for (final s in syncService.pendingSales) {
      final id = s['client_transaction_id']?.toString() ?? s.hashCode.toString();
      salesMap[id] = s;
    }

    final filteredSales = salesMap.values.where((sale) {
      final rawDate = sale['created_at']?.toString();
      if (rawDate == null) return true;
      final parsedDate = DateTime.tryParse(rawDate);
      if (parsedDate == null) return true;
      final saleDate = parsedDate.isUtc ? parsedDate.toLocal() : parsedDate;

      switch (_dashboardPeriod) {
        case 'yesterday':
          return !saleDate.isBefore(yesterdayStart) && saleDate.isBefore(yesterdayEnd);
        case 'this_week':
          return !saleDate.isBefore(weekStart);
        case 'this_month':
          return !saleDate.isBefore(monthStart);
        case 'today':
        default:
          return !saleDate.isBefore(todayStart);
      }
    }).toList();

    double periodRevenue = 0.0;
    double periodCogs = 0.0;
    final Map<int, _TopProductAccumulator> productSalesMap = {};

    for (final sale in filteredSales) {
      if (sale['status'] == 'reversed') continue;
      double total = (sale['total_amount'] as num?)?.toDouble() ??
          (sale['total'] as num?)?.toDouble() ??
          (sale['amount'] as num?)?.toDouble() ??
          0.0;

      final items = sale['items'] as List<dynamic>? ?? [];
      double itemsTotal = 0.0;
      for (final rawItem in items) {
        if (rawItem is Map<String, dynamic>) {
          final pId = rawItem['product_id'] as int? ?? 0;
          final pName = rawItem['product_name'] as String? ?? 'Product';
          final qty = (rawItem['quantity'] as num?)?.toDouble() ?? 0.0;
          final itemTotal = (rawItem['total'] as num?)?.toDouble() ??
              (qty * ((rawItem['unit_price'] as num?)?.toDouble() ?? 0.0));

          itemsTotal += itemTotal;

          final acc = productSalesMap.putIfAbsent(
            pId,
            () => _TopProductAccumulator(id: pId, name: pName),
          );
          acc.quantity += qty;
          acc.totalSales += itemTotal;
        }
      }

      if (total == 0.0 && itemsTotal > 0.0) {
        final disc = (sale['discount'] as num?)?.toDouble() ?? 0.0;
        total = (itemsTotal - disc).clamp(0.0, double.infinity);
      }
      if (total == 0.0) {
        total = (sale['amount_paid'] as num?)?.toDouble() ?? 0.0;
      }
      periodRevenue += total;

      final cogs = (sale['cogs'] as num?)?.toDouble() ?? 0.0;
      periodCogs += cogs;
    }

    final topList = productSalesMap.values.toList()
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));
    final topProducts = topList.take(5).map((h) => TopProduct(
      productId: h.id,
      productName: h.name,
      quantity: h.quantity,
      totalSales: h.totalSales,
    )).toList();

    // Merge and filter expenses
    final Map<String, Map<String, dynamic>> expensesMap = {};
    for (final e in syncService.localExpenses) {
      final id = e['id'] != null ? 'id_${e['id']}' : (e['created_at']?.toString() ?? '${e['category']}_${e['amount']}_${e['occurred_at']}');
      expensesMap[id] = e;
    }
    for (final e in syncService.pendingExpenses) {
      final id = e['id'] != null ? 'id_${e['id']}' : (e['created_at']?.toString() ?? '${e['category']}_${e['amount']}_${e['occurred_at']}');
      expensesMap[id] = e;
    }

    final filteredExpenses = expensesMap.values.where((exp) {
      if (_dashboardPeriod == 'all') return true;
      final rawDate = exp['occurred_at']?.toString() ?? exp['created_at']?.toString();
      if (rawDate == null) return true;
      final normalized = rawDate.length == 10 ? '${rawDate}T00:00:00' : rawDate;
      final parsedDate = DateTime.tryParse(normalized);
      if (parsedDate == null) return true;
      final expDate = parsedDate.isUtc ? parsedDate.toLocal() : parsedDate;
      final dateOnly = DateTime(expDate.year, expDate.month, expDate.day);

      switch (_dashboardPeriod) {
        case 'yesterday':
          return !dateOnly.isBefore(yesterdayStart) && dateOnly.isBefore(yesterdayEnd);
        case 'this_week':
          return !dateOnly.isBefore(weekStart) && dateOnly.isBefore(todayEnd);
        case 'this_month':
          return !dateOnly.isBefore(monthStart) && dateOnly.isBefore(todayEnd);
        case 'today':
        default:
          return !dateOnly.isBefore(todayStart) && dateOnly.isBefore(todayEnd);
      }
    }).toList();

    final periodExpenses = filteredExpenses.fold<double>(
      0.0,
      (sum, e) => sum + ((e['amount'] as num?)?.toDouble() ?? 0.0),
    );

    final grossProfit = periodRevenue - periodCogs;
    final netProfit = grossProfit - periodExpenses;

    final totalStock = products.fold<double>(0.0, (acc, p) => acc + (p.stockBase * p.averageCost));
    final lowCount = products.where((p) => p.isLowStock).length;
    final outCount = products.where((p) => p.isOutOfStock).length;
    final debt = customers.fold<double>(0.0, (acc, c) => acc + c.outstanding);

    _dashboard = DashboardData(
      currency: business?.currency ?? 'NGN',
      period: _dashboardPeriod,
      todaySales: periodRevenue,
      grossProfit: grossProfit,
      cogs: periodCogs,
      expenses: periodExpenses,
      netProfit: netProfit,
      transactions: filteredSales.length,
      lowStock: lowCount,
      outOfStock: outCount,
      stockValue: totalStock,
      outstandingDebt: debt,
      topProducts: topProducts,
    );
    notifyListeners();

    if (api.isAuthenticated) {
      try {
        final json = await api.getDashboard(period: _dashboardPeriod);
        final remoteDashboard = DashboardData.fromJson(json);
        if (remoteDashboard.todaySales > 0 || periodRevenue == 0.0) {
          _dashboard = remoteDashboard;
          notifyListeners();
        }
      } catch (_) {}
    }
  }

  ProfitLossData getProfitLossReport({
    String period = 'this_month',
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final filteredSales = filterSales(
      period: period,
      startDate: startDate,
      endDate: endDate,
    );

    final filteredExpenses = filterExpenses(
      period: period,
      startDate: startDate,
      endDate: endDate,
    );

    double revenue = 0.0;
    double cogs = 0.0;
    for (final sale in filteredSales) {
      if (sale['status'] == 'reversed') continue;
      final total = (sale['total_amount'] as num?)?.toDouble() ??
          (sale['total'] as num?)?.toDouble() ??
          0.0;
      final saleCogs = (sale['cogs'] as num?)?.toDouble() ?? 0.0;
      revenue += total;
      cogs += saleCogs;
    }

    double totalExpenses = 0.0;
    final Map<String, double> categoryExpenseMap = {};
    for (final exp in filteredExpenses) {
      final amt = exp.amount;
      final cat = exp.category.isNotEmpty ? exp.category : 'Other';
      totalExpenses += amt;
      categoryExpenseMap[cat] = (categoryExpenseMap[cat] ?? 0.0) + amt;
    }

    final expenseBreakdown = categoryExpenseMap.entries
        .map((e) => {'category': e.key, 'total': e.value})
        .toList()
      ..sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));

    final grossProfit = revenue - cogs;
    final netProfit = grossProfit - totalExpenses;

    final pl = ProfitLossData(
      period: period,
      currency: business?.currency ?? 'NGN',
      revenue: revenue,
      cogs: cogs,
      grossProfit: grossProfit,
      operatingExpenses: totalExpenses,
      netProfit: netProfit,
      expenseBreakdown: expenseBreakdown,
    );

    _profitLoss = pl;
    return pl;
  }

  List<Map<String, dynamic>> getSalesReportItems({
    String period = 'this_month',
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
  }) {
    final filteredSales = filterSales(
      period: period,
      startDate: startDate,
      endDate: endDate,
    );

    final Map<String, Map<String, dynamic>> itemMap = {};

    for (final sale in filteredSales) {
      if (sale['status'] == 'reversed') continue;
      final items = sale['items'] as List<dynamic>? ?? [];
      for (final raw in items) {
        if (raw is Map<String, dynamic>) {
          final pId = raw['product_id'] as int? ?? 0;
          final pName = raw['product_name'] as String? ?? raw['product'] as String? ?? 'Item';
          final uName = raw['unit_name'] as String? ?? raw['unit'] as String? ?? '';
          final qty = (raw['quantity'] as num?)?.toDouble() ?? 0.0;
          final uPrice = (raw['unit_price'] as num?)?.toDouble() ?? 0.0;
          final lineTotal = (raw['total'] as num?)?.toDouble() ?? (qty * uPrice);

          double lineCogs = (raw['cogs'] as num?)?.toDouble() ?? 0.0;
          if (lineCogs == 0.0 && qty > 0) {
            final prod = products.firstWhere(
              (p) => p.id == pId || p.name.toLowerCase() == pName.toLowerCase(),
              orElse: () => Product(id: 0, name: pName, baseUnitName: uName),
            );
            final unitCost = prod.averageCost > 0 ? prod.averageCost : (prod.basePrice * 0.75);
            lineCogs = qty * unitCost;
          }

          final key = '$pId-$pName-$uName';
          if (!itemMap.containsKey(key)) {
            itemMap[key] = {
              'product_id': pId,
              'product': pName,
              'unit': uName,
              'quantity': 0.0,
              'unit_price': uPrice,
              'revenue': 0.0,
              'cogs': 0.0,
              'gross_profit': 0.0,
              'margin': 0.0,
              'transactions': 0,
            };
          }

          final entry = itemMap[key]!;
          entry['quantity'] = (entry['quantity'] as double) + qty;
          entry['revenue'] = (entry['revenue'] as double) + lineTotal;
          entry['cogs'] = (entry['cogs'] as double) + lineCogs;
          entry['gross_profit'] = (entry['revenue'] as double) - (entry['cogs'] as double);
          final rev = entry['revenue'] as double;
          entry['margin'] = rev > 0 ? ((entry['gross_profit'] as double) / rev) * 100 : 0.0;
          entry['transactions'] = (entry['transactions'] as int) + 1;
        }
      }
    }

    var list = itemMap.values.toList();
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase().trim();
      list = list.where((item) => (item['product'] as String).toLowerCase().contains(q)).toList();
    }

    list.sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));
    return list;
  }

  List<Map<String, dynamic>> getCategorySalesSummary({
    String period = 'this_month',
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final filteredSales = filterSales(
      period: period,
      startDate: startDate,
      endDate: endDate,
    );

    final Map<String, Map<String, dynamic>> catMap = {};
    double totalRevenueAll = 0.0;

    for (final sale in filteredSales) {
      final items = sale['items'] as List<dynamic>? ?? [];
      for (final raw in items) {
        if (raw is Map<String, dynamic>) {
          final pId = raw['product_id'] as int? ?? 0;
          final pName = raw['product_name'] as String? ?? raw['product'] as String? ?? 'Item';
          final qty = (raw['quantity'] as num?)?.toDouble() ?? 0.0;
          final uPrice = (raw['unit_price'] as num?)?.toDouble() ?? 0.0;
          final lineTotal = (raw['total'] as num?)?.toDouble() ?? (qty * uPrice);

          final prod = products.firstWhere(
            (p) => p.id == pId || p.name.toLowerCase() == pName.toLowerCase(),
            orElse: () => Product(id: 0, name: pName, categoryName: 'General'),
          );
          final catName = (prod.categoryName != null && prod.categoryName!.isNotEmpty) ? prod.categoryName! : 'General';

          if (!catMap.containsKey(catName)) {
            catMap[catName] = {
              'category': catName,
              'revenue': 0.0,
              'units_sold': 0.0,
              'item_count': 0,
            };
          }

          final entry = catMap[catName]!;
          entry['revenue'] = (entry['revenue'] as double) + lineTotal;
          entry['units_sold'] = (entry['units_sold'] as double) + qty;
          entry['item_count'] = (entry['item_count'] as int) + 1;
          totalRevenueAll += lineTotal;
        }
      }
    }

    final list = catMap.values.toList();
    for (final entry in list) {
      final rev = entry['revenue'] as double;
      entry['percentage'] = totalRevenueAll > 0 ? (rev / totalRevenueAll) * 100 : 0.0;
    }

    list.sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));
    return list;
  }

  Map<String, dynamic> getInventoryValuationSummary({String? searchQuery}) {
    double totalCost = 0.0;
    double totalRetail = 0.0;
    int lowCount = 0;
    int outCount = 0;

    final List<Map<String, dynamic>> items = [];

    for (final p in products) {
      if (p.isOutOfStock) outCount++;
      if (p.isLowStock) lowCount++;

      final cost = p.averageCost > 0 ? p.averageCost : (p.basePrice * 0.75);
      final price = p.basePrice;
      final stock = p.stockBase;

      final costVal = stock > 0 ? (stock * cost) : 0.0;
      final retailVal = stock > 0 ? (stock * price) : 0.0;
      final profitVal = retailVal - costVal;
      final margin = retailVal > 0 ? (profitVal / retailVal) * 100 : 0.0;

      totalCost += costVal;
      totalRetail += retailVal;

      items.add({
        'id': p.id,
        'name': p.name,
        'category': (p.categoryName != null && p.categoryName!.isNotEmpty) ? p.categoryName! : 'General',
        'unit': p.baseUnitName,
        'stock': stock,
        'cost_price': cost,
        'selling_price': price,
        'stock_cost_value': costVal,
        'stock_retail_value': retailVal,
        'potential_profit': profitVal,
        'margin': margin,
        'is_low_stock': p.isLowStock,
        'is_out_of_stock': p.isOutOfStock,
      });
    }

    var filteredItems = items;
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase().trim();
      filteredItems = items.where((it) => (it['name'] as String).toLowerCase().contains(q)).toList();
    }

    filteredItems.sort((a, b) => (b['stock_cost_value'] as double).compareTo(a['stock_cost_value'] as double));

    final potentialProfit = totalRetail - totalCost;
    final overallMargin = totalRetail > 0 ? (potentialProfit / totalRetail) * 100 : 0.0;

    return {
      'total_cost_value': totalCost,
      'total_retail_value': totalRetail,
      'potential_profit': potentialProfit,
      'potential_margin': overallMargin,
      'total_products': products.length,
      'low_stock_count': lowCount,
      'out_of_stock_count': outCount,
      'items': filteredItems,
    };
  }

  Map<String, dynamic> getDebtorsSummary({String? searchQuery}) {
    var debtors = customers.where((c) => c.outstanding > 0).toList();
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase().trim();
      debtors = debtors.where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q)).toList();
    }
    debtors.sort((a, b) => b.outstanding.compareTo(a.outstanding));

    final totalDebt = debtors.fold<double>(0.0, (acc, c) => acc + c.outstanding);

    return {
      'total_debt': totalDebt,
      'count': debtors.length,
      'debtors': debtors,
    };
  }

  String exportReportCsvData(
    String type, {
    String period = 'this_month',
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final curr = business?.currency ?? 'NGN';
    final buffer = StringBuffer();

    switch (type.toLowerCase()) {
      case 'profit_loss':
        final pl = getProfitLossReport(period: period, startDate: startDate, endDate: endDate);
        buffer.writeln('PROFIT & LOSS STATEMENT');
        buffer.writeln('Store,${business?.name ?? "Krum Store"}');
        buffer.writeln('Period,$period');
        buffer.writeln('Currency,$curr');
        buffer.writeln('Sales Revenue,${pl.revenue.toStringAsFixed(2)}');
        buffer.writeln('Cost of Goods Sold (COGS),${pl.cogs.toStringAsFixed(2)}');
        buffer.writeln('Gross Profit,${pl.grossProfit.toStringAsFixed(2)}');
        final grossMargin = pl.revenue > 0 ? (pl.grossProfit / pl.revenue * 100).toStringAsFixed(1) : '0.0';
        buffer.writeln('Gross Margin %,$grossMargin%');
        buffer.writeln('Operating Expenses,${pl.operatingExpenses.toStringAsFixed(2)}');
        buffer.writeln('Net Profit,${pl.netProfit.toStringAsFixed(2)}');
        final netMargin = pl.revenue > 0 ? (pl.netProfit / pl.revenue * 100).toStringAsFixed(1) : '0.0';
        buffer.writeln('Net Margin %,$netMargin%');
        buffer.writeln('');
        buffer.writeln('OPERATING EXPENSES BREAKDOWN');
        buffer.writeln('Category,Amount ($curr)');
        for (final exp in pl.expenseBreakdown) {
          buffer.writeln('"${exp['category']}",${(exp['total'] as double).toStringAsFixed(2)}');
        }
        break;

      case 'sales':
        final items = getSalesReportItems(period: period, startDate: startDate, endDate: endDate);
        buffer.writeln('Product,Unit,Quantity Sold,Unit Price,Total Revenue,COGS,Gross Profit,Margin %');
        for (final it in items) {
          buffer.writeln(
            '"${it['product']}","${it['unit']}",${it['quantity']},${(it['unit_price'] as double).toStringAsFixed(2)},${(it['revenue'] as double).toStringAsFixed(2)},${(it['cogs'] as double).toStringAsFixed(2)},${(it['gross_profit'] as double).toStringAsFixed(2)},${(it['margin'] as double).toStringAsFixed(1)}%',
          );
        }
        break;

      case 'inventory':
        final inv = getInventoryValuationSummary();
        final items = inv['items'] as List<Map<String, dynamic>>;
        buffer.writeln('Product,Category,Current Stock,Unit,Unit Cost,Selling Price,Stock Cost Value,Stock Retail Value,Potential Profit');
        for (final it in items) {
          buffer.writeln(
            '"${it['name']}","${it['category']}",${it['stock']},"${it['unit']}",${(it['cost_price'] as double).toStringAsFixed(2)},${(it['selling_price'] as double).toStringAsFixed(2)},${(it['stock_cost_value'] as double).toStringAsFixed(2)},${(it['stock_retail_value'] as double).toStringAsFixed(2)},${(it['potential_profit'] as double).toStringAsFixed(2)}',
          );
        }
        break;

      case 'debtors':
        final debt = getDebtorsSummary();
        final list = debt['debtors'] as List<Customer>;
        buffer.writeln('Customer Name,Phone Number,Outstanding Debt ($curr)');
        for (final c in list) {
          buffer.writeln('"${c.name}","${c.phone}",${c.outstanding.toStringAsFixed(2)}');
        }
        break;
    }

    return buffer.toString();
  }

  String generateShareableSummaryText({
    String period = 'this_month',
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final curr = business?.currency ?? 'NGN';
    final pl = getProfitLossReport(period: period, startDate: startDate, endDate: endDate);
    final inv = getInventoryValuationSummary();
    final debt = getDebtorsSummary();

    String periodLabel = period.replaceAll('_', ' ').toUpperCase();
    if (period == 'custom' && startDate != null && endDate != null) {
      periodLabel = '${startDate.day}/${startDate.month}/${startDate.year} - ${endDate.day}/${endDate.month}/${endDate.year}';
    }

    final grossMargin = pl.revenue > 0 ? ((pl.grossProfit / pl.revenue) * 100).toStringAsFixed(1) : '0.0';
    final netMargin = pl.revenue > 0 ? ((pl.netProfit / pl.revenue) * 100).toStringAsFixed(1) : '0.0';

    final buffer = StringBuffer();
    buffer.writeln('📊 *KRUM STORE BUSINESS REPORT*');
    buffer.writeln('🏪 Store: ${business?.name ?? "Krum Store"}');
    buffer.writeln('📅 Period: $periodLabel');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('💰 *FINANCIAL STATEMENT*');
    buffer.writeln('• Sales Revenue: $curr ${CurrencyFormatter.format(pl.revenue, currency: "")}');
    buffer.writeln('• Cost of Goods (COGS): -$curr ${CurrencyFormatter.format(pl.cogs, currency: "")}');
    buffer.writeln('• Gross Profit: $curr ${CurrencyFormatter.format(pl.grossProfit, currency: "")} ($grossMargin%)');
    buffer.writeln('• Operating Expenses: -$curr ${CurrencyFormatter.format(pl.operatingExpenses, currency: "")}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('✨ *NET PROFIT: $curr ${CurrencyFormatter.format(pl.netProfit, currency: "")} ($netMargin%)*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📦 *INVENTORY VALUATION*');
    buffer.writeln('• Stock at Cost: $curr ${CurrencyFormatter.format(inv['total_cost_value'] as double, currency: "")}');
    buffer.writeln('• Retail Value: $curr ${CurrencyFormatter.format(inv['total_retail_value'] as double, currency: "")}');
    buffer.writeln('• Potential Profit: $curr ${CurrencyFormatter.format(inv['potential_profit'] as double, currency: "")}');
    buffer.writeln('• Low Stock Items: ${inv['low_stock_count']} | Out of Stock: ${inv['out_of_stock_count']}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('👥 *RECEIVABLES (DEBTORS)*');
    buffer.writeln('• Total Debt Owed: $curr ${CurrencyFormatter.format(debt['total_debt'] as double, currency: "")} (${debt['count']} debtors)');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('Generated by Krum Store Manager');

    return buffer.toString();
  }

  Future<void> loadProfitLoss({
    String period = 'this_month',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // 1. Immediately calculate offline so reports work with zero latency
    getProfitLossReport(
      period: period,
      startDate: startDate,
      endDate: endDate,
    );
    notifyListeners();

    // 2. If authenticated, attempt to fetch remote and merge if remote has newer data
    if (api.isAuthenticated) {
      try {
        final json = await api.getProfitLoss(period: period);
        final remote = ProfitLossData.fromJson(json);
        if (remote.revenue > 0 || _profitLoss?.revenue == 0.0) {
          _profitLoss = remote;
          notifyListeners();
        }
      } catch (_) {}
    }
  }

  Future<void> syncNow() async {
    _setLoading(true);
    await syncService.sync();
    await refreshDashboard();
    _setLoading(false);
  }

  // --- Staff & Cashier Management ---
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> get staff => _staff;

  Future<void> loadStaff() async {
    if (!isAuthenticated) return;
    try {
      final list = await api.getStaff();
      _staff = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> createStaff({
    required String username,
    required String password,
    String role = 'sales',
  }) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();
    try {
      final newStaff = await api.createStaff(
        username: username,
        password: password,
        role: role,
      );
      _staff.add(newStaff);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateStaffRole(int membershipId, String role) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();
    try {
      final updated = await api.updateStaffRole(membershipId, role);
      final idx = _staff.indexWhere((s) => s['id'] == membershipId);
      if (idx != -1) {
        _staff[idx] = updated;
      }
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteStaff(int membershipId) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();
    try {
      await api.deleteStaff(membershipId);
      _staff.removeWhere((s) => s['id'] == membershipId);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  // --- Cash Drawer & Shift Handover Sessions ---

  Map<String, dynamic>? get currentCashSession => syncService.currentCashSession;
  bool get isShiftActive => currentCashSession != null && currentCashSession!['status'] == 'open';
  List<Map<String, dynamic>> get cashSessions => syncService.cashSessions;

  Map<String, double> get currentDrawerMetrics {
    if (!isShiftActive) {
      return {
        'openingFloat': 0.0,
        'cashSales': 0.0,
        'otherSales': 0.0,
        'totalSales': 0.0,
        'cashDebtPayments': 0.0,
        'cashExpenses': 0.0,
        'expectedCash': 0.0,
      };
    }

    final session = currentCashSession!;
    final openedAtStr = session['opened_at']?.toString() ?? '';
    final openedAt = DateTime.tryParse(openedAtStr) ?? DateTime.now();
    final openingFloat = (session['opening_float'] as num?)?.toDouble() ?? 0.0;

    double cashSales = 0.0;
    double otherSales = 0.0;

    for (final s in sales) {
      if (s['status'] == 'reversed') continue;
      final sDateStr = s['completed_at'] ?? s['created_at'];
      if (sDateStr == null) continue;
      final sDate = DateTime.tryParse(sDateStr.toString());
      if (sDate != null && sDate.isAfter(openedAt.subtract(const Duration(seconds: 1)))) {
        final method = (s['payment_method'] ?? 'cash').toString().toLowerCase();
        final amount = (s['amount_paid'] as num?)?.toDouble() ?? (s['total_amount'] as num?)?.toDouble() ?? 0.0;
        if (method == 'cash') {
          cashSales += amount;
        } else {
          otherSales += amount;
        }
      }
    }

    double cashExpenses = 0.0;
    for (final e in expenses) {
      final eDateStr = e.createdAt;
      DateTime? eDate;
      if (eDateStr != null) {
        eDate = DateTime.tryParse(eDateStr);
      }
      eDate ??= DateTime.tryParse(e.occurredAt);
      if (eDate != null && eDate.isAfter(openedAt.subtract(const Duration(seconds: 1)))) {
        cashExpenses += e.amount;
      }
    }

    double cashDebtPayments = 0.0;
    final allPayments = [
      ...syncService.localPayments,
      ...syncService.pendingPayments,
    ];
    final Set<String> processedPayKeys = {};
    for (final p in allPayments) {
      final key = p['client_transaction_id'] ?? '${p['customer_id']}_${p['amount']}_${p['created_at']}';
      if (processedPayKeys.contains(key)) continue;
      processedPayKeys.add(key);

      final pMethod = (p['method'] ?? 'cash').toString().toLowerCase();
      if (pMethod != 'cash') continue;

      final pDateStr = p['created_at']?.toString();
      final pDate = pDateStr != null ? DateTime.tryParse(pDateStr) : null;
      if (pDate != null && pDate.isAfter(openedAt.subtract(const Duration(seconds: 1)))) {
        final amt = p['amount'];
        if (amt is num) {
          cashDebtPayments += amt.toDouble();
        }
      }
    }

    final expectedCash = openingFloat + cashSales + cashDebtPayments - cashExpenses;

    return {
      'openingFloat': openingFloat,
      'cashSales': cashSales,
      'otherSales': otherSales,
      'totalSales': cashSales + otherSales,
      'cashDebtPayments': cashDebtPayments,
      'cashExpenses': cashExpenses,
      'expectedCash': expectedCash,
    };
  }

  Future<bool> startShift({
    required double openingFloat,
    String openingNotes = '',
  }) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();
    try {
      await syncService.startCashSessionLocally(
        openingFloat: openingFloat,
        openingNotes: openingNotes,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> closeShift({
    required double closingCashActual,
    String closingNotes = '',
  }) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();
    try {
      final metrics = currentDrawerMetrics;
      final closed = await syncService.closeCashSessionLocally(
        closingCashActual: closingCashActual,
        closingNotes: closingNotes,
        cashSales: metrics['cashSales'] ?? 0.0,
        otherSales: metrics['otherSales'] ?? 0.0,
        cashDebtPayments: metrics['cashDebtPayments'] ?? 0.0,
        cashExpenses: metrics['cashExpenses'] ?? 0.0,
      );
      _isLoading = false;
      notifyListeners();
      return closed;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  Future<void> refreshCashSessions() async {
    await syncService.syncCashSessionsWithRemote();
    notifyListeners();
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }
}

class _TopProductAccumulator {
  final int id;
  final String name;
  double quantity = 0.0;
  double totalSales = 0.0;

  _TopProductAccumulator({required this.id, required this.name});
}

class _SoldItemAccumulator {
  final int productId;
  final String productName;
  final String unitName;
  double quantitySold = 0.0;
  double totalRevenue = 0.0;
  int transactionCount = 0;

  _SoldItemAccumulator({
    required this.productId,
    required this.productName,
    required this.unitName,
  });
}
