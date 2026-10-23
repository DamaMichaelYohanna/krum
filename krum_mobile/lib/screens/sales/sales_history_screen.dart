import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/store_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

class SalesHistoryScreen extends StatefulWidget {
  final int initialTabIndex;

  const SalesHistoryScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedPeriod = 'this_month';
  DateTimeRange? _customDateRange;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _refreshSales();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshSales() async {
    final provider = context.read<StoreProvider>();
    if (!provider.isAuthenticated) return;
    setState(() => _loading = true);
    try {
      await provider.loadSales(
        period: _selectedPeriod,
        startDate: _customDateRange?.start,
        endDate: _customDateRange?.end,
      );
      await provider.refreshDashboard();
    } catch (_) {}
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final initialRange = _customDateRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: now,
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      initialDateRange: initialRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedPeriod = 'custom';
        _customDateRange = picked;
      });
      _refreshSales();
    }
  }

  String _getPeriodLabel() {
    switch (_selectedPeriod) {
      case 'today':
        return 'Today';
      case 'yesterday':
        return 'Yesterday';
      case 'this_week':
        return 'This Week';
      case 'this_month':
        return 'This Month (${DateFormat('MMM yyyy').format(DateTime.now())})';
      case 'custom':
        if (_customDateRange != null) {
          return DateFormatter.formatRange(
              _customDateRange!.start, _customDateRange!.end);
        }
        return 'Custom Range';
      case 'all':
        return 'All Time';
      default:
        return _selectedPeriod;
    }
  }

  void _showReceiptDialog(BuildContext context, Map<String, dynamic> sale, String currency) {
    final rawDate = (sale['created_at'] ?? sale['completed_at'])?.toString() ?? '';
    final formattedDate = DateFormatter.format(rawDate, includeTime: true);
    final txId = (sale['client_transaction_id'] ?? sale['id'] ?? 'N/A').toString();
    final shortTx = txId.length > 8 ? txId.substring(txId.length - 8).toUpperCase() : txId.toUpperCase();
    final customerName = (sale['customer_name'] ?? 'Walk-in Customer').toString();
    final items = (sale['items'] as List<dynamic>? ?? []);
    final total = (sale['total_amount'] as num?)?.toDouble() ?? (sale['total'] as num?)?.toDouble() ?? 0.0;
    final discount = (sale['discount'] as num?)?.toDouble() ?? 0.0;
    final amountPaid = (sale['amount_paid'] as num?)?.toDouble() ?? total;
    final balance = (total - amountPaid).clamp(0.0, double.infinity);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.88,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Sale Receipt',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Receipt Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Receipt Number & Date
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Receipt #$shortTx',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            formattedDate,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Customer details
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline, size: 20, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Customer', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                Text(
                                  customerName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: balance == 0
                                  ? AppColors.success.withValues(alpha: 0.12)
                                  : Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              balance == 0 ? 'PAID' : 'CREDIT / PARTIAL',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: balance == 0 ? AppColors.success : Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Items Table
                    const Text(
                      'ITEMS PURCHASED',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),

                    ...items.map((it) {
                      final pName = (it['product_name'] ?? it['product'] ?? 'Item').toString();
                      final uName = (it['unit_name'] ?? it['unit'] ?? '').toString();
                      final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
                      final uPrice = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
                      final lineTotal = (it['total'] as num?)?.toDouble() ?? (qty * uPrice);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pName,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  Text(
                                    '${CurrencyFormatter.formatQty(qty)} ${uName.isNotEmpty ? uName : 'unit'} × ${CurrencyFormatter.format(uPrice, currency: currency)}',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              CurrencyFormatter.format(lineTotal, currency: currency),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    }),

                    const Divider(height: 24),

                    // Summary breakdown
                    if (discount > 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Subtotal:', style: TextStyle(color: AppColors.textSecondary)),
                          Text(CurrencyFormatter.format(total + discount, currency: currency)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Discount:', style: TextStyle(color: Colors.green)),
                          Text('-${CurrencyFormatter.format(discount, currency: currency)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL AMOUNT:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(
                          CurrencyFormatter.format(total, currency: currency),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Amount Paid:', style: TextStyle(color: AppColors.textSecondary)),
                        Text(CurrencyFormatter.format(amountPaid, currency: currency), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),

                    if (balance > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Balance Due (Debt):', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          Text(
                            CurrencyFormatter.format(balance, currency: currency),
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),

            // Bottom Close Button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close Receipt', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final currency = provider.business?.currency ?? 'NGN';

    final filteredSales = provider.filterSales(
      period: _selectedPeriod,
      startDate: _customDateRange?.start,
      endDate: _customDateRange?.end,
      searchQuery: _searchQuery,
    );

    final itemizedSummary = provider.getItemizedSalesSummary(
      period: _selectedPeriod,
      startDate: _customDateRange?.start,
      endDate: _customDateRange?.end,
      searchQuery: _searchQuery,
    );

    final totalRevenue = filteredSales.fold<double>(
      0.0,
      (acc, s) =>
          acc +
          ((s['total_amount'] as num?)?.toDouble() ??
              (s['total'] as num?)?.toDouble() ??
              0.0),
    );

    final totalUnitsSold = itemizedSummary.fold<double>(
      0.0,
      (acc, item) => acc + item.quantitySold,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Sales & Items Sold', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refreshSales,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: [
            Tab(
              icon: const Icon(Icons.shopping_bag_outlined, size: 20),
              text: 'Items Sold (${itemizedSummary.length})',
            ),
            Tab(
              icon: const Icon(Icons.receipt_long_outlined, size: 20),
              text: 'Receipts (${filteredSales.length})',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 1. Date Period Filter Bar
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildPeriodChip('today', 'Today'),
                  const SizedBox(width: 8),
                  _buildPeriodChip('yesterday', 'Yesterday'),
                  const SizedBox(width: 8),
                  _buildPeriodChip('this_week', 'This Week'),
                  const SizedBox(width: 8),
                  _buildPeriodChip('this_month', 'This Month'),
                  const SizedBox(width: 8),
                  _buildCustomRangeChip(),
                  const SizedBox(width: 8),
                  _buildPeriodChip('all', 'All Time'),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // 2. Summary Card
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryLight,
                    const Color(0xFFD4EDE2).withValues(alpha: 0.5),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'TOTAL REVENUE',
                              style: TextStyle(
                                color: AppColors.primaryDark,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${filteredSales.length} sales · ${CurrencyFormatter.formatQty(totalUnitsSold)} items',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          CurrencyFormatter.format(totalRevenue, currency: currency, showDecimals: true),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.date_range, size: 13, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              _getPeriodLabel(),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.point_of_sale, color: AppColors.primary, size: 24),
                  ),
                ],
              ),
            ),
          ),

          // 3. Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search product, receipt #, customer...',
                  hintStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),

          // 4. Tab Views: Receipts vs Items Sold
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // TAB 1: Items Sold Breakdown
                      _buildItemsSoldTab(context, itemizedSummary, currency),

                      // TAB 2: Receipts List
                      _buildReceiptsTab(context, filteredSales, currency),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptsTab(
    BuildContext context,
    List<Map<String, dynamic>> salesList,
    String currency,
  ) {
    if (salesList.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refreshSales,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.receipt_long_outlined, size: 32, color: AppColors.primary),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'No matching sales found'
                            : 'No sales for ${_getPeriodLabel()}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Try searching by a different product or receipt number.'
                            : 'Complete sales via the POS Sell tab to view receipts here.',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      if (_selectedPeriod != 'all' || _searchQuery.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedPeriod = 'this_month';
                              _searchQuery = '';
                              _searchController.clear();
                              _customDateRange = null;
                            });
                          },
                          icon: const Icon(Icons.filter_alt_off, size: 16),
                          label: const Text('Reset Filters'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshSales,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: salesList.length,
        separatorBuilder: (_, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final sale = salesList[index];
          final rawDate = (sale['created_at'] ?? sale['completed_at'])?.toString() ?? '';
          final formattedDate = DateFormatter.format(rawDate, includeTime: true);
          final txId = (sale['client_transaction_id'] ?? sale['id'] ?? 'N/A').toString();
          final shortTx = txId.length > 8 ? txId.substring(txId.length - 8).toUpperCase() : txId.toUpperCase();
          final customerName = (sale['customer_name'] ?? 'Walk-in Customer').toString();
          final items = (sale['items'] as List<dynamic>? ?? []);
          final total = (sale['total_amount'] as num?)?.toDouble() ?? (sale['total'] as num?)?.toDouble() ?? 0.0;
          final amountPaid = (sale['amount_paid'] as num?)?.toDouble() ?? total;
          final isCredit = (total - amountPaid) > 0.01;

          // Item preview summary text
          final itemSummary = items.take(2).map((it) {
            final pName = (it['product_name'] ?? it['product'] ?? 'Item').toString();
            final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
            return '${CurrencyFormatter.formatQty(qty)}x $pName';
          }).join(', ');
          final extraItemsCount = items.length - 2;
          final fullItemText = extraItemsCount > 0 ? '$itemSummary +$extraItemsCount more' : itemSummary;

          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => _showReceiptDialog(context, sale, currency),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Code + Date + Status
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '#$shortTx',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formattedDate,
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isCredit
                                  ? Colors.orange.withValues(alpha: 0.12)
                                  : AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isCredit ? 'CREDIT' : 'PAID',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isCredit ? Colors.orange.shade800 : AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Customer + Items count
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            customerName,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const Text(' · ', style: TextStyle(color: AppColors.textSecondary)),
                          Text(
                            '${items.length} ${items.length == 1 ? 'item' : 'items'}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Items brief preview
                      if (fullItemText.isNotEmpty)
                        Text(
                          fullItemText,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 8),

                      // Bottom Row: Total & "View Receipt"
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Text('Total: ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                              Text(
                                CurrencyFormatter.format(total, currency: currency),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: const [
                              Text(
                                'View Receipt',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                              Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildItemsSoldTab(
    BuildContext context,
    List<SoldItemSummary> items,
    String currency,
  ) {
    if (items.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refreshSales,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.shopping_bag_outlined, size: 32, color: AppColors.primary),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'No matching items sold'
                            : 'No items sold in ${_getPeriodLabel()}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Items sold in checkout will appear here with total quantities and revenue.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshSales,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: items.length,
        separatorBuilder: (_, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final rank = index + 1;

          // Rank styling
          Color rankBg = AppColors.background;
          Color rankColor = AppColors.textSecondary;
          if (rank == 1) {
            rankBg = const Color(0xFFFEF3C7);
            rankColor = const Color(0xFFB45309);
          } else if (rank == 2) {
            rankBg = const Color(0xFFF1F5F9);
            rankColor = const Color(0xFF475569);
          } else if (rank == 3) {
            rankBg = const Color(0xFFFFEDD5);
            rankColor = const Color(0xFFC2410C);
          }

          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: rankBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: rankColor,
                  ),
                ),
              ),
              title: Text(
                item.productName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    '${CurrencyFormatter.formatQty(item.quantitySold)} ${item.unitName.isNotEmpty ? item.unitName : 'units'} sold across ${item.transactionCount} ${item.transactionCount == 1 ? 'sale' : 'sales'}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Avg. price: ${CurrencyFormatter.format(item.averagePrice, currency: currency)}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.format(item.totalRevenue, currency: currency),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text('Revenue', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPeriodChip(String periodKey, String label) {
    final isSelected = _selectedPeriod == periodKey;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPeriod = periodKey;
          if (periodKey != 'custom') {
            _customDateRange = null;
          }
        });
        _refreshSales();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomRangeChip() {
    final isSelected = _selectedPeriod == 'custom';
    final hasRange = _customDateRange != null;
    final label = hasRange
        ? DateFormatter.formatRange(_customDateRange!.start, _customDateRange!.end)
        : 'Custom Range';

    return GestureDetector(
      onTap: _pickCustomDateRange,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.date_range,
              size: 15,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
