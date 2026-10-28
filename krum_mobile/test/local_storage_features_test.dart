import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:krum/services/api_service.dart';
import 'package:krum/services/sync_service.dart';
import 'package:krum/providers/store_provider.dart';
import 'package:krum/utils/pdf_receipt_helper.dart';

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

  test('Comprehensive Business Reports offline calculation: P&L, itemized sales, category summary, inventory valuation, debtors, CSV export, and statement text', () async {
    SharedPreferences.setMockInitialValues({});

    final api = ApiService();
    final syncService = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: syncService);
    await provider.init();

    // 1. Create Products
    final beverageCat = provider.categories.firstWhere((c) => c.name.toLowerCase().contains('beverage'), orElse: () => provider.categories.first);
    final grainCat = provider.categories.firstWhere((c) => c.name.toLowerCase().contains('grain') || c.name.toLowerCase().contains('general'), orElse: () => provider.categories.first);

    await provider.createProduct(
      name: 'Nestle Milo',
      categoryId: beverageCat.id,
      baseUnitId: provider.units.first.id,
      openingStock: 50.0,
      costPrice: 2000.0,
      sellingPrice: 3000.0,
    );

    await provider.createProduct(
      name: 'Brown Sugar',
      categoryId: grainCat.id,
      baseUnitId: provider.units.first.id,
      openingStock: 20.0,
      costPrice: 800.0,
      sellingPrice: 1200.0,
    );

    // 2. Add an Expense
    await provider.recordExpense(
      category: 'Utilities',
      amount: 1500.0,
      description: 'Shop Electricity',
      occurredAt: DateTime.now().toIso8601String().substring(0, 10),
    );

    // 3. Create a Customer with Debt
    await provider.createCustomer(
      'Alhaji Musa',
      phone: '08012345678',
      initialDebt: 4500.0,
    );

    // 4. Perform a Sale
    final milo = provider.products.firstWhere((p) => p.name == 'Nestle Milo');
    final sugar = provider.products.firstWhere((p) => p.name == 'Brown Sugar');

    provider.addToCart(milo, quantity: 2.0); // 2 milo @ 3000 = 6000
    provider.addToCart(sugar, quantity: 1.0); // 1 sugar @ 1200 = 1200
    // Total = 7200, COGS = (2 * 2000) + (1 * 800) = 4800, Gross Profit = 2400

    await provider.checkoutSale(amountPaid: 7200.0);

    // 5. Test Profit & Loss Report Offline
    final pl = provider.getProfitLossReport(period: 'today');
    expect(pl.revenue, 7200.0);
    expect(pl.cogs, 4800.0);
    expect(pl.grossProfit, 2400.0);
    expect(pl.operatingExpenses, 1500.0);
    expect(pl.netProfit, 900.0); // 2400 gross - 1500 exp = 900
    expect(pl.expenseBreakdown.length, 1);
    expect(pl.expenseBreakdown.first['category'], 'Utilities');
    expect(pl.expenseBreakdown.first['total'], 1500.0);

    // 6. Test Sales Report Items
    final salesItems = provider.getSalesReportItems(period: 'today');
    expect(salesItems.length, 2);
    final topSold = salesItems.firstWhere((it) => it['product'] == 'Nestle Milo');
    expect(topSold['quantity'], 2.0);
    expect(topSold['revenue'], 6000.0);
    expect(topSold['cogs'], 4000.0);
    expect(topSold['gross_profit'], 2000.0);

    // 7. Test Category Sales Summary
    final catSummary = provider.getCategorySalesSummary(period: 'today');
    expect(catSummary.isNotEmpty, true);
    final totalRevCheck = catSummary.fold<double>(0.0, (acc, c) => acc + (c['revenue'] as double));
    expect(totalRevCheck, 7200.0);

    // 8. Test Inventory Valuation Summary
    final invSummary = provider.getInventoryValuationSummary();
    expect(invSummary['total_cost_value'], greaterThan(0.0));
    expect(invSummary['total_retail_value'], greaterThan(0.0));
    expect(invSummary['potential_profit'], greaterThan(0.0));

    // 9. Test Debtors Summary
    final debtorsSummary = provider.getDebtorsSummary();
    expect(debtorsSummary['count'], 1);
    expect(debtorsSummary['total_debt'], 4500.0);

    // 10. Test CSV Export Generation
    final plCsv = provider.exportReportCsvData('profit_loss', period: 'today');
    expect(plCsv.contains('PROFIT & LOSS STATEMENT'), true);
    expect(plCsv.contains('7200.00'), true);
    expect(plCsv.contains('4800.00'), true);
    expect(plCsv.contains('900.00'), true);

    final salesCsv = provider.exportReportCsvData('sales', period: 'today');
    expect(salesCsv.contains('Nestle Milo'), true);
    expect(salesCsv.contains('Brown Sugar'), true);

    final invCsv = provider.exportReportCsvData('inventory');
    expect(invCsv.contains('Nestle Milo'), true);

    final debtCsv = provider.exportReportCsvData('debtors');
    expect(debtCsv.contains('Alhaji Musa'), true);
    expect(debtCsv.contains('4500.00'), true);

    // 11. Test Shareable Text Statement Generation
    final statement = provider.generateShareableSummaryText(period: 'today');
    expect(statement.contains('KRUM STORE BUSINESS REPORT'), true);
    expect(statement.contains('Sales Revenue'), true);
    expect(statement.contains('NET PROFIT'), true);
    expect(statement.contains('INVENTORY VALUATION'), true);
    expect(statement.contains('RECEIVABLES (DEBTORS)'), true);
  });

  test('Switching cart item units updates prices, totals, and deducts base stock accurately', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    final pieceUnit = provider.units.firstWhere((u) => u.name == 'Piece');
    final cartonUnit = provider.units.firstWhere((u) => u.name == 'Carton');

    // Create a product with base unit Piece (₦500) and alternative unit Carton (₦5,500, contains 12 pieces)
    await provider.createProduct(
      name: 'Coca Cola 50cl',
      baseUnitId: pieceUnit.id,
      sellingPrice: 500.0,
      costPrice: 350.0,
      openingStock: 120.0, // 120 pieces in stock
      alternativeUnits: [
        {
          'unit_id': cartonUnit.id,
          'unit_name': 'Carton',
          'conversion_to_base': 12.0,
          'selling_price': 5500.0,
          'cost_price': 4000.0,
        }
      ],
    );

    final coke = provider.products.firstWhere((p) => p.name == 'Coca Cola 50cl');
    expect(coke.allUnits.length, 2);

    // 1. Add Coke to cart (defaults to base unit Piece)
    provider.addToCart(coke, quantity: 2.0);
    expect(provider.cart.length, 1);
    expect(provider.cart.first.selectedUnit.unitName, 'Piece');
    expect(provider.cart.first.unitPrice, 500.0);
    expect(provider.cart.first.total, 1000.0); // 2 * 500
    expect(provider.cartTotal, 1000.0);

    // 2. Switch unit in cart from Piece to Carton
    final cartonObj = coke.allUnits.firstWhere((u) => u.unitName == 'Carton');
    provider.updateCartItemUnit(0, cartonObj);

    // 3. Verify cart immediately updates with Carton pricing and conversion
    expect(provider.cart.length, 1);
    expect(provider.cart.first.selectedUnit.unitName, 'Carton');
    expect(provider.cart.first.unitPrice, 5500.0);
    expect(provider.cart.first.total, 11000.0); // 2 cartons * 5500 = 11,000
    expect(provider.cartTotal, 11000.0);
    expect(provider.cart.first.requiredBaseQuantity, 24.0); // 2 cartons * 12 = 24 base pieces

    // 4. Checkout the 2 cartons
    await provider.checkoutSale(amountPaid: 11000.0);
    expect(provider.cart.length, 0);

    // 5. Verify stock deduction: 120 opening - 24 base pieces sold = 96 pieces remaining
    final updatedCoke = provider.products.firstWhere((p) => p.name == 'Coca Cola 50cl');
    expect(updatedCoke.stockBase, 96.0);
  });

  test('Receipt PDF generation and formatted text sharing for completed sales', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    final pieceUnit = provider.units.firstWhere((u) => u.name == 'Piece');

    await provider.createProduct(
      name: 'Peak Milk 400g',
      baseUnitId: pieceUnit.id,
      sellingPrice: 2500.0,
      costPrice: 1900.0,
      openingStock: 50.0,
    );

    final milk = provider.products.firstWhere((p) => p.name == 'Peak Milk 400g');
    provider.addToCart(milk, quantity: 2.0); // 5000.0
    await provider.checkoutSale(amountPaid: 5000.0);

    expect(provider.sales.isNotEmpty, true);
    final completedSale = provider.sales.first;

    // 1. Generate formatted WhatsApp/SMS text receipt
    final receiptText = PdfReceiptHelper.generateReceiptText(
      sale: completedSale,
      business: provider.business,
    );
    expect(receiptText.contains('SALES RECEIPT'), true);
    expect(receiptText.contains('Peak Milk 400g'), true);
    expect(receiptText.contains('TOTAL PAYABLE'), true);
    expect(receiptText.contains('Thank you for your patronage!'), true);

    // 2. Generate PDF byte array (Thermal Roll 80mm standard format)
    final pdfBytes = await PdfReceiptHelper.generateReceiptPdf(
      sale: completedSale,
      business: provider.business,
    );
    expect(pdfBytes.isNotEmpty, true);
    // PDF files always begin with the magic header bytes %PDF-
    final header = String.fromCharCodes(pdfBytes.take(5));
    expect(header, '%PDF-');
  });

  test('Supplier restocking updates moving weighted average cost, unit cost prices, selling price, and stock valuation offline', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    final pieceUnit = provider.units.firstWhere((u) => u.name == 'Piece');
    final cartonUnit = provider.units.firstWhere((u) => u.name == 'Carton');

    // 1. Create a product with 10 Pieces opening stock @ cost of ₦1,000 each (selling price ₦1,500)
    // Plus a carton unit (1 carton = 10 pieces)
    await provider.createProduct(
      name: 'Golden Penny Spaghetti 500g',
      baseUnitId: pieceUnit.id,
      sellingPrice: 1500.0,
      costPrice: 1000.0,
      openingStock: 10.0,
      alternativeUnits: [
        {
          'unit_id': cartonUnit.id,
          'unit_name': 'Carton',
          'conversion_to_base': 10.0,
          'selling_price': 14000.0,
          'cost_price': 10000.0,
        }
      ],
    );

    var prod = provider.products.firstWhere((p) => p.name == 'Golden Penny Spaghetti 500g');
    expect(prod.stockBase, 10.0);
    expect(prod.averageCost, 1000.0);
    expect(prod.baseUnit.costPrice, 1000.0);
    expect(prod.baseUnit.sellingPrice, 1500.0);

    // Initial stock valuation: 10 * 1000 = 10,000
    expect(provider.products.fold<double>(0.0, (acc, p) => acc + (p.stockBase * p.averageCost)), 10000.0);

    // 2. Restock 10 Pieces from supplier at a new higher unit cost of ₦1,500 each, and update selling price to ₦2,000
    // Weighted Average Cost calculation:
    // (10 old * 1,000 + 10 new * 1,500) / 20 = 25,000 / 20 = ₦1,250
    await provider.receivePurchase(
      productId: prod.id,
      productUnitId: prod.baseUnit.id,
      quantity: 10.0,
      unitCost: 1500.0,
      amountPaid: 15000.0,
      newSellingPrice: 2000.0,
      reference: 'RESTOCK-001',
    );

    prod = provider.products.firstWhere((p) => p.name == 'Golden Penny Spaghetti 500g');
    expect(prod.stockBase, 20.0);
    expect(prod.averageCost, 1250.0);
    expect(prod.baseUnit.costPrice, 1500.0);
    expect(prod.baseUnit.sellingPrice, 2000.0);

    // New stock valuation: 20 * 1250 = 25,000
    expect(provider.products.fold<double>(0.0, (acc, p) => acc + (p.stockBase * p.averageCost)), 25000.0);

    // 3. Restock 1 Carton (10 pieces) at ₦16,000 per carton (i.e. ₦1,600 per base piece)
    // Weighted Average Cost calculation:
    // (20 old * 1,250 + 10 new * 1,600) / 30 = (25,000 + 16,000) / 30 = 41,000 / 30 = ₦1,366.67
    final cartonObj = prod.units.firstWhere((u) => u.unitName == 'Carton');
    await provider.receivePurchase(
      productId: prod.id,
      productUnitId: cartonObj.id,
      quantity: 1.0,
      unitCost: 16000.0,
      amountPaid: 16000.0,
      newSellingPrice: 19000.0,
      reference: 'RESTOCK-002',
    );

    prod = provider.products.firstWhere((p) => p.name == 'Golden Penny Spaghetti 500g');
    expect(prod.stockBase, 30.0);
    expect(prod.averageCost, closeTo(1366.67, 0.01));
    final updatedCarton = prod.units.firstWhere((u) => u.unitName == 'Carton');
    expect(updatedCarton.costPrice, 16000.0);
    expect(updatedCarton.sellingPrice, 19000.0);

    // 4. Sell 2 pieces and verify COGS uses the updated moving average cost
    provider.addToCart(prod, quantity: 2.0);
    await provider.checkoutSale(amountPaid: 4000.0); // 2 * 2000 = 4000

    expect(provider.sales.isNotEmpty, true);
    final lastSale = provider.sales.first;
    final cogs = (lastSale['cogs'] as num).toDouble();
    final total = (lastSale['total_amount'] as num).toDouble();
    expect(cogs, closeTo(2 * 1366.67, 0.02));
    expect(total - cogs, closeTo(4000 - (2 * 1366.67), 0.02));

    // 5. Verify local storage persistence across a completely new provider instance
    final sync2 = SyncService(api: api);
    final provider2 = StoreProvider(api: api, syncService: sync2);
    await provider2.init();

    final persistedProd = provider2.products.firstWhere((p) => p.name == 'Golden Penny Spaghetti 500g');
    expect(persistedProd.stockBase, 28.0); // 30 - 2 sold
    expect(persistedProd.averageCost, closeTo(1366.67, 0.01));
    expect(persistedProd.baseUnit.sellingPrice, 2000.0);
    final persistedCarton = persistedProd.units.firstWhere((u) => u.unitName == 'Carton');
    expect(persistedCarton.costPrice, 16000.0);
    expect(persistedCarton.sellingPrice, 19000.0);
  });

  test('Sale reversal restores stock, deducts customer debt, and marks receipt void offline', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    final pieceUnit = provider.units.firstWhere((u) => u.name == 'Piece');

    // Create a product with 10 pieces
    await provider.createProduct(
      name: 'Cornflakes 350g',
      baseUnitId: pieceUnit.id,
      sellingPrice: 2500.0,
      costPrice: 1800.0,
      openingStock: 10.0,
    );

    // Create a customer
    await provider.createCustomer('Bisi Adebayo', phone: '08055443322');
    final customer = provider.customers.firstWhere((c) => c.name == 'Bisi Adebayo');

    // 1. Credit sale: Sell 3 pieces (₦7,500), paid ₦2,500, owes ₦5,000
    final product = provider.products.firstWhere((p) => p.name == 'Cornflakes 350g');
    provider.addToCart(product, quantity: 3.0);
    provider.setSelectedCustomer(customer);
    await provider.checkoutSale(amountPaid: 2500.0);

    // Verify stock dropped from 10 to 7
    final pAfterSale = provider.products.firstWhere((p) => p.name == 'Cornflakes 350g');
    expect(pAfterSale.stockBase, 7.0);

    // Verify customer owes ₦5,000
    final custAfterSale = provider.customers.firstWhere((c) => c.id == customer.id);
    expect(custAfterSale.outstanding, 5000.0);

    expect(provider.sales.length, 1);
    final sale = provider.sales.first;
    expect(sale['status'], isNot('reversed'));

    // 2. Reverse this sale
    final success = await provider.reverseSale(sale);
    expect(success, true);

    // Verify stock was restored to 10
    final pAfterReverse = provider.products.firstWhere((p) => p.name == 'Cornflakes 350g');
    expect(pAfterReverse.stockBase, 10.0);

    // Verify customer debt was cleared back to 0
    final custAfterReverse = provider.customers.firstWhere((c) => c.id == customer.id);
    expect(custAfterReverse.outstanding, 0.0);

    // Verify sale status is now 'reversed'
    final reversedSale = provider.sales.firstWhere((s) => s['client_transaction_id'] == sale['client_transaction_id']);
    expect(reversedSale['status'], 'reversed');

    // 3. Verify persistence across a fresh provider instance
    final sync2 = SyncService(api: api);
    final provider2 = StoreProvider(api: api, syncService: sync2);
    await provider2.init();

    final reloadedProd = provider2.products.firstWhere((p) => p.name == 'Cornflakes 350g');
    expect(reloadedProd.stockBase, 10.0);
    final reloadedCust = provider2.customers.firstWhere((c) => c.id == customer.id);
    expect(reloadedCust.outstanding, 0.0);
  });

  test('Update store profile name, phone, and currency persists offline and updates branding', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    expect(provider.business?.name, 'Krum Store');

    // Update store profile
    final updated = await provider.updateBusinessProfile(
      name: 'Mama Chidi Provision Store',
      phone: '08012345678',
      currency: 'NGN',
    );
    expect(updated, true);
    expect(provider.business?.name, 'Mama Chidi Provision Store');
    expect(provider.business?.phone, '08012345678');

    // Verify persistence across reload
    final sync2 = SyncService(api: api);
    final provider2 = StoreProvider(api: api, syncService: sync2);
    await provider2.init();

    expect(provider2.business?.name, 'Mama Chidi Provision Store');
    expect(provider2.business?.phone, '08012345678');
  });

  test('Role permissions check isOwner and isOwnerOrManager correctly', () async {
    SharedPreferences.setMockInitialValues({'user_role': 'owner'});
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    expect(provider.userRole, 'owner');
    expect(provider.isOwner, true);
    expect(provider.isOwnerOrManager, true);

    // Test manager role
    SharedPreferences.setMockInitialValues({'user_role': 'manager'});
    final providerMgr = StoreProvider(api: api, syncService: sync);
    await providerMgr.init();

    expect(providerMgr.userRole, 'manager');
    expect(providerMgr.isOwner, false);
    expect(providerMgr.isOwnerOrManager, true);

    // Test sales (cashier) role
    SharedPreferences.setMockInitialValues({'user_role': 'sales'});
    final providerSales = StoreProvider(api: api, syncService: sync);
    await providerSales.init();

    expect(providerSales.userRole, 'sales');
    expect(providerSales.isOwner, false);
    expect(providerSales.isOwnerOrManager, false);
  });

  test('Cash drawer shift session start, live till metrics calculation, sales, and closing reconciliation offline', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiService();
    final sync = SyncService(api: api);
    final provider = StoreProvider(api: api, syncService: sync);
    await provider.init();

    // 1. Initial drawer state: No active session
    expect(provider.isShiftActive, false);
    expect(provider.currentCashSession, isNull);
    expect(provider.currentDrawerMetrics['expectedCash'], 0.0);

    // 2. Start shift with opening float of 10,000 NGN
    final started = await provider.startShift(
      openingFloat: 10000.0,
      openingNotes: 'Morning shift opening float',
    );
    expect(started, true);
    expect(provider.isShiftActive, true);
    expect(provider.currentCashSession, isNotNull);
    expect(provider.currentCashSession?['opening_float'], 10000.0);
    expect(provider.currentDrawerMetrics['openingFloat'], 10000.0);
    expect(provider.currentDrawerMetrics['expectedCash'], 10000.0);

    // 3. Create a product and perform a cash sale of 5,000 NGN
    final prodCreated = await provider.createProduct(
      name: 'Milo 500g Refill',
      barcode: '9988776655',
      sku: 'MILO-500',
      sellingPrice: 5000.0,
      costPrice: 4000.0,
      openingStock: 20.0,
      baseUnitId: 1,
    );
    expect(prodCreated, true);
    final product = provider.products.firstWhere((p) => p.name == 'Milo 500g Refill');

    provider.setPaymentMethod('cash');
    provider.addToCart(product, quantity: 1.0);
    expect(provider.cartTotal, 5000.0);

    final txId = await provider.checkoutSale(amountPaid: 5000.0);
    expect(txId.isNotEmpty, true);

    // 4. Record a cash expense of 2,000 NGN (e.g., Shop cleaner / fuel)
    await provider.recordExpense(
      category: 'Cleaning',
      amount: 2000.0,
      description: 'Morning sweeping and detergent',
    );

    // 5. Create a customer with debt and record a cash debt payment of 1,500 NGN
    final customer = await provider.createCustomer(
      'Madam Ngozi',
      phone: '08055556666',
      initialDebt: 3000.0,
    );
    expect(customer, isNotNull);

    await provider.recordCustomerPayment(
      customerId: customer!.id,
      amount: 1500.0,
      method: 'cash',
    );

    // 6. Verify live drawer metrics calculation:
    // Expected Cash = Opening Float (10,000) + Cash Sales (5,000) + Debt Payments (1,500) - Expenses (2,000) = 14,500
    final liveMetrics = provider.currentDrawerMetrics;
    expect(liveMetrics['openingFloat'], 10000.0);
    expect(liveMetrics['cashSales'], 5000.0);
    expect(liveMetrics['cashDebtPayments'], 1500.0);
    expect(liveMetrics['cashExpenses'], 2000.0);
    expect(liveMetrics['expectedCash'], 14500.0);

    // 7. Test persistence across app reload
    final sync2 = SyncService(api: api);
    final provider2 = StoreProvider(api: api, syncService: sync2);
    await provider2.init();

    expect(provider2.isShiftActive, true);
    expect(provider2.currentCashSession, isNotNull);
    final reloadedMetrics = provider2.currentDrawerMetrics;
    expect(reloadedMetrics['openingFloat'], 10000.0);
    expect(reloadedMetrics['cashSales'], 5000.0);
    expect(reloadedMetrics['cashDebtPayments'], 1500.0);
    expect(reloadedMetrics['cashExpenses'], 2000.0);
    expect(reloadedMetrics['expectedCash'], 14500.0);

    // 8. Close shift with actual counted cash = 14,000 NGN (shortage of 500 NGN)
    final closeResult = await provider2.closeShift(
      closingCashActual: 14000.0,
      closingNotes: 'End of morning shift with 500 shortage',
    );
    expect(closeResult, isNotNull);
    expect(closeResult?['status'], 'closed');
    expect(closeResult?['expected_cash'], 14500.0);
    expect(closeResult?['closing_cash_actual'], 14000.0);
    expect(closeResult?['difference'], -500.0);

    // 9. Verify provider state after closing
    expect(provider2.isShiftActive, false);
    expect(provider2.currentCashSession, isNull);
    expect(provider2.cashSessions.length, 1);
    expect(provider2.cashSessions.first['difference'], -500.0);

    // 10. Verify history persistence across reload
    final sync3 = SyncService(api: api);
    final provider3 = StoreProvider(api: api, syncService: sync3);
    await provider3.init();

    expect(provider3.isShiftActive, false);
    expect(provider3.cashSessions.length, 1);
    expect(provider3.cashSessions.first['difference'], -500.0);
    expect(provider3.cashSessions.first['status'], 'closed');
  });
}


