import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:krum/services/api_service.dart';
import 'package:krum/services/sync_service.dart';
import 'package:krum/providers/store_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Local storage seeds default units, categories, and business when empty', () async {
    final api = ApiService();
    final sync = SyncService(api: api);
    await sync.init();

    // Verify seeded units
    expect(sync.units.isNotEmpty, true);
    expect(sync.units.any((u) => u.name == 'Piece'), true);
    expect(sync.units.any((u) => u.name == 'Carton'), true);
    expect(sync.units.any((u) => u.name == 'Mudu'), true);

    // Verify seeded categories
    expect(sync.categories.isNotEmpty, true);
    expect(sync.categories.any((c) => c.name == 'General'), true);
    expect(sync.categories.any((c) => c.name == 'Beverages & Drinks'), true);

    // Verify default business
    expect(sync.currentBusiness, isNotNull);
    expect(sync.currentBusiness?.currency, 'NGN');
  });

  test('Create and persist new category offline in local storage', () async {
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    final initialCount = provider.categories.length;
    final newCat = await provider.createCategory('Stationery & Office');
    expect(newCat, isNotNull);
    expect(newCat?.name, 'Stationery & Office');
    expect(provider.categories.length, initialCount + 1);

    // Re-instantiate SyncService to verify persistence
    final newSync = SyncService(api: api);
    await newSync.init();
    expect(newSync.categories.any((c) => c.name == 'Stationery & Office'), true);
  });

  test('Create and persist new custom unit offline in local storage', () async {
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    final initialCount = provider.units.length;
    final newUnit = await provider.createCustomUnit('Paint Bucket', symbol: 'bkt');
    expect(newUnit, isNotNull);
    expect(newUnit?.name, 'Paint Bucket');
    expect(newUnit?.symbol, 'bkt');
    expect(provider.units.length, initialCount + 1);

    // Verify persistence
    final newSync = SyncService(api: api);
    await newSync.init();
    expect(newSync.units.any((u) => u.name == 'Paint Bucket' && u.symbol == 'bkt'), true);
  });

  test('Create, update, and delete product with multiple units offline in local storage', () async {
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    final pieceUnit = provider.units.firstWhere((u) => u.name == 'Piece');
    final cartonUnit = provider.units.firstWhere((u) => u.name == 'Carton');
    final bevCategory = provider.categories.firstWhere((c) => c.name.contains('Beverages'));

    // 1. Create product
    final created = await provider.createProduct(
      name: 'Golden Penny Sugar',
      baseUnitId: pieceUnit.id,
      categoryId: bevCategory.id,
      costPrice: 800.0,
      sellingPrice: 1000.0,
      openingStock: 50.0,
      reorderLevel: 10.0,
      barcode: '1234567890',
      alternativeUnits: [
        {
          'unit_id': cartonUnit.id,
          'unit_name': cartonUnit.name,
          'conversion_to_base': 12.0,
          'selling_price': 11500.0,
        }
      ],
    );

    expect(created, true);
    expect(provider.products.length, 1);

    final p = provider.products.first;
    expect(p.name, 'Golden Penny Sugar');
    expect(p.stockBase, 50.0);
    expect(p.baseUnitName, 'Piece');
    expect(p.categoryName, bevCategory.name);
    expect(p.units.length, 2);
    expect(p.units[1].unitName, 'Carton');
    expect(p.units[1].conversionToBase, 12.0);
    expect(p.units[1].sellingPrice, 11500.0);

    // Verify dashboard updated stock valuation locally
    expect(provider.dashboard.stockValue, 50.0 * 800.0);
    expect(provider.dashboard.lowStock, 0);

    // 2. Update product
    final updated = p.copyWith(name: 'Golden Penny Sugar 500g', stockBase: 5.0);
    final updateSuccess = await provider.updateProduct(updated);
    expect(updateSuccess, true);
    expect(provider.products.first.name, 'Golden Penny Sugar 500g');
    expect(provider.products.first.stockBase, 5.0);
    expect(provider.dashboard.lowStock, 1); // 5 <= reorderLevel(10) -> now marked as low stock!

    // 3. Delete product
    final deleteSuccess = await provider.deleteProduct(p.id);
    expect(deleteSuccess, true);
    expect(provider.products.isEmpty, true);
    expect(provider.dashboard.stockValue, 0.0);
  });

  test('Selling an item immediately updates revenue, profit, and transactions on dashboard offline', () async {
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    final pieceUnit = provider.units.firstWhere((u) => u.name == 'Piece');

    // 1. Create product with stock 20, selling price 1,500, cost 1,000
    await provider.createProduct(
      name: 'Indomie Chicken Flavour',
      baseUnitId: pieceUnit.id,
      costPrice: 1000.0,
      sellingPrice: 1500.0,
      openingStock: 20.0,
    );

    expect(provider.products.length, 1);
    final prod = provider.products.first;
    expect(provider.dashboard.todaySales, 0.0);
    expect(provider.dashboard.transactions, 0);

    // 2. Add 2 pieces to cart
    provider.addToCart(prod, quantity: 2.0);
    expect(provider.cartTotal, 3000.0);

    // 3. Complete sale offline
    final txId = await provider.checkoutSale(amountPaid: 3000.0);
    expect(txId.isNotEmpty, true);

    // 4. Verify Dashboard instantly reflects the sold item
    expect(provider.dashboard.todaySales, 3000.0);
    expect(provider.dashboard.transactions, 1);
    expect(provider.dashboard.cogs, 2000.0);
    expect(provider.dashboard.grossProfit, 1000.0);
    expect(provider.dashboard.netProfit, 1000.0);
    expect(provider.dashboard.topProducts.length, 1);
    expect(provider.dashboard.topProducts.first.productName, 'Indomie Chicken Flavour');
    expect(provider.dashboard.topProducts.first.quantity, 2.0);
    expect(provider.dashboard.topProducts.first.totalSales, 3000.0);

    // Stock was deducted locally
    expect(provider.products.first.stockBase, 18.0);

    // 5. Verify persistence across app restarts / reload from SharedPreferences
    final newSync = SyncService(api: api);
    final newProvider = StoreProvider(api: api, syncService: newSync);
    await newProvider.init();

    expect(newProvider.dashboard.todaySales, 3000.0);
    expect(newProvider.dashboard.transactions, 1);
    expect(newProvider.dashboard.netProfit, 1000.0);
    expect(newProvider.dashboard.topProducts.first.productName, 'Indomie Chicken Flavour');
  });

  test('Create, update, record payment, and delete customer and supplier offline in local storage', () async {
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    // 1. Create customer offline
    final initialCustomerCount = provider.customers.length;
    final customer = await provider.createCustomer(
      'Alhaji Musa',
      phone: '08033334444',
      initialDebt: 5000.0,
    );

    expect(customer, isNotNull);
    expect(customer?.name, 'Alhaji Musa');
    expect(customer?.phone, '08033334444');
    expect(customer?.outstanding, 5000.0);
    expect(provider.customers.length, initialCustomerCount + 1);
    expect(provider.dashboard.outstandingDebt, 5000.0);

    // 2. Update customer details
    final updated = customer!.copyWith(name: 'Alhaji Musa Ibrahim', phone: '08099991111');
    final updateSuccess = await provider.updateCustomer(updated);
    expect(updateSuccess, true);
    expect(provider.customers.firstWhere((c) => c.id == customer.id).name, 'Alhaji Musa Ibrahim');
    expect(provider.customers.firstWhere((c) => c.id == customer.id).phone, '08099991111');

    // 3. Record debt payment of 2,000
    await provider.recordCustomerPayment(
      customerId: customer.id,
      amount: 2000.0,
      method: 'cash',
    );
    expect(provider.customers.firstWhere((c) => c.id == customer.id).outstanding, 3000.0);
    expect(provider.dashboard.outstandingDebt, 3000.0);

    // 4. Create and persist supplier offline
    final initialSupplierCount = provider.suppliers.length;
    final supplier = await provider.createSupplier('Dangote Flour Mills', phone: '08012345678');
    expect(supplier, isNotNull);
    expect(supplier?.name, 'Dangote Flour Mills');
    expect(provider.suppliers.length, initialSupplierCount + 1);

    // 5. Test persistence across reload from local storage
    final reloadedSync = SyncService(api: api);
    final reloadedProvider = StoreProvider(api: api, syncService: reloadedSync);
    await reloadedProvider.init();

    expect(reloadedProvider.customers.any((c) => c.name == 'Alhaji Musa Ibrahim' && c.outstanding == 3000.0), true);
    expect(reloadedProvider.suppliers.any((s) => s.name == 'Dangote Flour Mills'), true);
    expect(reloadedProvider.dashboard.outstandingDebt, 3000.0);

    // 6. Delete customer and supplier
    final delCust = await reloadedProvider.deleteCustomer(customer.id);
    expect(delCust, true);
    expect(reloadedProvider.customers.any((c) => c.id == customer.id), false);
    expect(reloadedProvider.dashboard.outstandingDebt, 0.0);

    final delSupp = await reloadedProvider.deleteSupplier(supplier!.id);
    expect(delSupp, true);
    expect(reloadedProvider.suppliers.any((s) => s.id == supplier.id), false);
  });

  test('Barcode scanning and tolerant checkout lookup by barcode, leading zeros, SKU, and ID offline in local storage', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    final pieceUnit = provider.units.firstWhere((u) => u.name == 'Piece');

    // 1. Create a product with a 12-digit UPC barcode having a leading zero: '073762806450'
    await provider.createProduct(
      name: 'Milo 500g Tin',
      baseUnitId: pieceUnit.id,
      sellingPrice: 2500.0,
      costPrice: 2000.0,
      openingStock: 25.0,
      barcode: '073762806450',
    );

    // 2. Create another product with custom SKU and barcode
    await provider.createProduct(
      name: 'Indomie Chicken 70g',
      baseUnitId: pieceUnit.id,
      sellingPrice: 150.0,
      costPrice: 120.0,
      openingStock: 100.0,
      sku: 'IND-CHICK-70G',
      barcode: '615110001234',
    );

    // Exact barcode lookup
    final miloByExact = provider.findProduct('073762806450');
    expect(miloByExact, isNotNull);
    expect(miloByExact!.name, 'Milo 500g Tin');

    // UPC-A / EAN-13 leading-zero stripped lookup ('73762806450' matches '073762806450')
    final miloWithoutZero = provider.findProduct('73762806450');
    expect(miloWithoutZero, isNotNull);
    expect(miloWithoutZero!.id, miloByExact.id);

    // Lookup by SKU (case-insensitive)
    final indomieBySku = provider.findProduct('ind-chick-70g');
    expect(indomieBySku, isNotNull);
    expect(indomieBySku!.name, 'Indomie Chicken 70g');

    // Lookup by product database numeric ID
    final indomieById = provider.findProduct(indomieBySku.id.toString());
    expect(indomieById, isNotNull);
    expect(indomieById!.name, 'Indomie Chicken 70g');

    // Test checkout flow: Scan item, add to cart, verify cart updates
    provider.addToCart(miloWithoutZero);
    provider.addToCart(indomieBySku, quantity: 3.0);

    expect(provider.cartItemCount, 2);
    expect(provider.cartTotal, 2500.0 + (150.0 * 3.0));

    // Test nonexistent item returns null
    final unknown = provider.findProduct('999999999999');
    expect(unknown, isNull);
  });

  test('Expenses offline recording, date range filtering (today, yesterday, this_week, this_month, custom, all), category filtering, and persistence', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    final now = DateTime.now();
    final todayStr = now.toIso8601String().substring(0, 10);
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr = yesterday.toIso8601String().substring(0, 10);
    final sixDaysAgo = now.subtract(const Duration(days: 6));
    final sixDaysAgoStr = sixDaysAgo.toIso8601String().substring(0, 10);
    final fortyDaysAgo = now.subtract(const Duration(days: 40));
    final fortyDaysAgoStr = fortyDaysAgo.toIso8601String().substring(0, 10);

    // 1. Record expenses across various dates and categories
    await provider.recordExpense(
      category: 'Fuel',
      amount: 15000.0,
      description: 'Generator petrol for shop',
      occurredAt: todayStr,
    );

    await provider.recordExpense(
      category: 'Electricity',
      amount: 5000.0,
      description: 'NEPA token recharge',
      occurredAt: todayStr,
    );

    await provider.recordExpense(
      category: 'Transport',
      amount: 3000.0,
      description: 'Keke delivery from market',
      occurredAt: yesterdayStr,
    );

    await provider.recordExpense(
      category: 'Packaging',
      amount: 4500.0,
      description: 'Nylon bags 10 rolls',
      occurredAt: sixDaysAgoStr,
    );

    await provider.recordExpense(
      category: 'Rent',
      amount: 50000.0,
      description: 'Shop rent deposit',
      occurredAt: fortyDaysAgoStr,
    );

    // 2. Verify all expenses loaded in provider
    expect(provider.expenses.length, 5);

    // 3. Test 'today' filter
    final todayExpenses = provider.filterExpenses(period: 'today');
    expect(todayExpenses.length, 2);
    expect(todayExpenses.any((e) => e.category == 'Fuel' && e.amount == 15000.0), true);
    expect(todayExpenses.any((e) => e.category == 'Electricity' && e.amount == 5000.0), true);

    // 4. Test 'yesterday' filter
    final yesterdayExpenses = provider.filterExpenses(period: 'yesterday');
    expect(yesterdayExpenses.length, 1);
    expect(yesterdayExpenses.first.category, 'Transport');
    expect(yesterdayExpenses.first.amount, 3000.0);

    // 5. Test 'all' filter
    final allExpenses = provider.filterExpenses(period: 'all');
    expect(allExpenses.length, 5);

    // 6. Test category filter
    final fuelOnly = provider.filterExpenses(period: 'all', category: 'Fuel');
    expect(fuelOnly.length, 1);
    expect(fuelOnly.first.category, 'Fuel');

    final electricityOnly = provider.filterExpenses(period: 'today', category: 'Electricity');
    expect(electricityOnly.length, 1);
    expect(electricityOnly.first.category, 'Electricity');

    // 7. Test custom date range picker filter
    final customRange = provider.filterExpenses(
      period: 'custom',
      startDate: yesterday,
      endDate: now,
    );
    // Should include today (2) + yesterday (1) = 3
    expect(customRange.length, 3);

    // 8. Test persistence: reload sync and provider from SharedPreferences
    final newSync = SyncService(api: api);
    final reloadedProvider = StoreProvider(api: api, syncService: newSync);
    await reloadedProvider.init();

    expect(reloadedProvider.expenses.length, 5);
    final reloadedToday = reloadedProvider.filterExpenses(period: 'today');
    expect(reloadedToday.length, 2);

    // 9. Test delete expense offline
    final toDelete = reloadedToday.firstWhere((e) => e.category == 'Electricity');
    await reloadedProvider.deleteExpense(toDelete);
    expect(reloadedProvider.expenses.length, 4);
    expect(reloadedProvider.filterExpenses(period: 'today').length, 1);
  });

  test('Sales history tracking, receipt details, and itemized items sold aggregation offline', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    final pieceUnit = provider.units.firstWhere((u) => u.name == 'Piece');

    // Create 2 products
    await provider.createProduct(
      name: 'Milo 500g',
      baseUnitId: pieceUnit.id,
      sellingPrice: 3000.0,
      costPrice: 2200.0,
      openingStock: 50.0,
      barcode: 'MILO-001',
    );

    await provider.createProduct(
      name: 'Dangote Sugar 1kg',
      baseUnitId: pieceUnit.id,
      sellingPrice: 1200.0,
      costPrice: 900.0,
      openingStock: 100.0,
      barcode: 'SUGAR-002',
    );

    final milo = provider.products.firstWhere((p) => p.name == 'Milo 500g');
    final sugar = provider.products.firstWhere((p) => p.name == 'Dangote Sugar 1kg');

    // Sale 1: 2 Milo + 3 Sugar
    provider.addToCart(milo, quantity: 2.0);
    provider.addToCart(sugar, quantity: 3.0);
    await provider.checkoutSale(amountPaid: 9600.0); // 2*3000 + 3*1200 = 9600
    expect(provider.cartItemCount, 0);

    // Sale 2: 1 Milo
    provider.addToCart(milo, quantity: 1.0);
    await provider.checkoutSale(amountPaid: 3000.0);

    // Verify sales history list
    expect(provider.sales.length, 2);

    // Verify filterSales by period
    final todaySales = provider.filterSales(period: 'today');
    expect(todaySales.length, 2);

    // Verify search in sales by product name
    final sugarSales = provider.filterSales(period: 'today', searchQuery: 'sugar');
    expect(sugarSales.length, 1);

    // Verify Itemized Sales Summary (Items Sold Tab)
    final itemsSold = provider.getItemizedSalesSummary(period: 'today');
    expect(itemsSold.length, 2);

    // Top item by revenue should be Milo (3 sold = 9,000 revenue)
    final topItem = itemsSold.first;
    expect(topItem.productName, 'Milo 500g');
    expect(topItem.quantitySold, 3.0);
    expect(topItem.totalRevenue, 9000.0);
    expect(topItem.transactionCount, 2); // sold in both sale 1 and sale 2

    // Second item should be Sugar (3 sold = 3,600 revenue)
    final secondItem = itemsSold[1];
    expect(secondItem.productName, 'Dangote Sugar 1kg');
    expect(secondItem.quantitySold, 3.0);
    expect(secondItem.totalRevenue, 3600.0);
    expect(secondItem.transactionCount, 1);

    // Verify persistence across reload
    final newSync = SyncService(api: api);
    final reloadedProvider = StoreProvider(api: api, syncService: newSync);
    await reloadedProvider.init();

    expect(reloadedProvider.sales.length, 2);
    final reloadedItems = reloadedProvider.getItemizedSalesSummary(period: 'today');
    expect(reloadedItems.length, 2);
    expect(reloadedItems.first.productName, 'Milo 500g');
    expect(reloadedItems.first.quantitySold, 3.0);
  });
}


