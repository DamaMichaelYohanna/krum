import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/store_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

class ReportsScreen extends StatefulWidget {
  final int initialTabIndex;

  const ReportsScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
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
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _refreshReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshReports() async {
    final provider = context.read<StoreProvider>();
    setState(() => _loading = true);

    try {
      await provider.loadProfitLoss(
        period: _selectedPeriod,
        startDate: _customDateRange?.start,
        endDate: _customDateRange?.end,
      );
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
      _refreshReports();
    }
  }

  String _getPeriodLabel() {
    switch (_selectedPeriod) {
      case 'today':
        return 'Today (${DateFormat('MMM d').format(DateTime.now())})';
      case 'yesterday':
        return 'Yesterday';
      case 'this_week':
        return 'This Week';
      case 'this_month':
        return 'This Month (${DateFormat('MMMM yyyy').format(DateTime.now())})';
      case 'custom':
        if (_customDateRange != null) {
          final s = DateFormat('MMM d').format(_customDateRange!.start);
          final e = DateFormat('MMM d, yyyy').format(_customDateRange!.end);
          return '$s - $e';
        }
        return 'Custom Range';
      case 'all':
      default:
        return 'All Time';
    }
  }

  void _exportReportCsv(String type) {
    final provider = context.read<StoreProvider>();
    final csvData = provider.exportReportCsvData(
      type,
      period: _selectedPeriod,
      startDate: _customDateRange?.start,
      endDate: _customDateRange?.end,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.table_view_outlined, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              '${type.replaceAll('_', ' ').toUpperCase()} CSV',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                csvData,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy CSV'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvData));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('CSV copied to clipboard!'),
                  backgroundColor: AppColors.primary,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showShareSummaryModal() {
    final provider = context.read<StoreProvider>();
    final summaryText = provider.generateShareableSummaryText(
      period: _selectedPeriod,
      startDate: _customDateRange?.start,
      endDate: _customDateRange?.end,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Financial Statement Summary',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                summaryText,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy Statement to Clipboard'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: summaryText));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Statement copied! Ready to share to WhatsApp or print.'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _recordCustomerPaymentDialog(BuildContext context, Customer customer, String currency) {
    final amountController = TextEditingController();
    final refController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Record Debt Payment - ${customer.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Balance Owed: ${CurrencyFormatter.format(customer.outstanding, currency: currency)}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Amount Paid',
                prefixText: '₦ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: refController,
              decoration: const InputDecoration(
                labelText: 'Note / Reference (Optional)',
                hintText: 'e.g. Bank transfer, Cash deposit',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final amt = double.tryParse(amountController.text.trim()) ?? 0.0;
              if (amt <= 0) return;
              final provider = context.read<StoreProvider>();
              await provider.recordCustomerPayment(
                customerId: customer.id,
                amount: amt,
                reference: refController.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _refreshReports();
            },
            child: const Text('Confirm Payment'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final currency = provider.business?.currency ?? 'NGN';

    final pl = provider.getProfitLossReport(
      period: _selectedPeriod,
      startDate: _customDateRange?.start,
      endDate: _customDateRange?.end,
    );

    final salesItems = provider.getSalesReportItems(
      period: _selectedPeriod,
      startDate: _customDateRange?.start,
      endDate: _customDateRange?.end,
      searchQuery: _searchQuery,
    );

    final categories = provider.getCategorySalesSummary(
      period: _selectedPeriod,
      startDate: _customDateRange?.start,
      endDate: _customDateRange?.end,
    );

    final inventory = provider.getInventoryValuationSummary(searchQuery: _searchQuery);
    final debtorsData = provider.getDebtorsSummary(searchQuery: _searchQuery);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share Summary Statement',
            onPressed: _showShareSummaryModal,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export CSV',
            onSelected: _exportReportCsv,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profit_loss', child: Text('Export Profit & Loss (CSV)')),
              PopupMenuItem(value: 'sales', child: Text('Export Sales Report (CSV)')),
              PopupMenuItem(value: 'inventory', child: Text('Export Stock Valuation (CSV)')),
              PopupMenuItem(value: 'debtors', child: Text('Export Debtors Report (CSV)')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Reports',
            onPressed: _refreshReports,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            const Tab(
              icon: Icon(Icons.analytics_outlined, size: 20),
              text: 'Profit & Loss',
            ),
            Tab(
              icon: const Icon(Icons.category_outlined, size: 20),
              text: 'Sales & Categories (${categories.length})',
            ),
            Tab(
              icon: const Icon(Icons.inventory_2_outlined, size: 20),
              text: 'Stock Value (${provider.products.length})',
            ),
            Tab(
              icon: const Icon(Icons.people_outline, size: 20),
              text: 'Debtors (${debtorsData['count']})',
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

          // 2. Tab Views
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Profit & Loss Statement
                      _buildProfitLossTab(context, pl, currency),

                      // Tab 2: Sales & Category Breakdown
                      _buildSalesAndCategoriesTab(context, categories, salesItems, currency),

                      // Tab 3: Inventory Valuation
                      _buildInventoryValuationTab(context, inventory, currency),

                      // Tab 4: Debtors & Receivables
                      _buildDebtorsTab(context, debtorsData, currency),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String id, String label) {
    final isSelected = _selectedPeriod == id;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedPeriod = id;
          if (id != 'custom') _customDateRange = null;
        });
        _refreshReports();
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomRangeChip() {
    final isSelected = _selectedPeriod == 'custom';
    String label = 'Custom Range';
    if (_customDateRange != null) {
      final s = DateFormat('MMM d').format(_customDateRange!.start);
      final e = DateFormat('MMM d').format(_customDateRange!.end);
      label = '$s - $e';
    }

    return InkWell(
      onTap: _pickCustomDateRange,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month_outlined,
              size: 14,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: PROFIT & LOSS STATEMENT (P&L)
  // ==========================================
  Widget _buildProfitLossTab(BuildContext context, ProfitLossData pl, String currency) {
    final grossMargin = pl.revenue > 0 ? (pl.grossProfit / pl.revenue) * 100 : 0.0;
    final netMargin = pl.revenue > 0 ? (pl.netProfit / pl.revenue) * 100 : 0.0;
    final isProfit = pl.netProfit >= 0;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshReports,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Hero Net Profit Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isProfit
                    ? [
                        AppColors.primaryLight,
                        const Color(0xFFD8F2F7).withValues(alpha: 0.6),
                      ]
                    : [
                        const Color(0xFFFEE2E2),
                        const Color(0xFFFFECEC),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isProfit
                    ? AppColors.primaryBorder
                    : Colors.red.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: isProfit
                      ? AppColors.primaryGlow
                      : Colors.red.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'NET PROFIT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: isProfit ? AppColors.primaryDark : Colors.red.shade900,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isProfit
                            ? AppColors.success.withValues(alpha: 0.15)
                            : Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isProfit ? Icons.trending_up : Icons.trending_down,
                            size: 14,
                            color: isProfit ? AppColors.success : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isProfit ? 'PROFITABLE' : 'NET LOSS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isProfit ? AppColors.success : Colors.red.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  CurrencyFormatter.format(pl.netProfit, currency: currency, showDecimals: true),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.0,
                    color: isProfit ? AppColors.primaryDark : Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        'Net Margin: ${netMargin.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isProfit ? AppColors.primary : Colors.red.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• for ${_getPeriodLabel()}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Statement Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Income Statement',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 16),

                _reportLineItem(
                  'Sales Revenue',
                  pl.revenue,
                  currency: currency,
                  isPositive: true,
                  isBold: true,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 8),

                _reportLineItem(
                  'Cost of Goods Sold (COGS)',
                  -pl.cogs,
                  currency: currency,
                  isNegative: true,
                  subtitle: 'Direct cost of inventory sold',
                ),
                const Divider(height: 24),

                _reportLineItem(
                  'Gross Profit',
                  pl.grossProfit,
                  currency: currency,
                  isBold: true,
                  tag: 'Gross Margin: ${grossMargin.toStringAsFixed(1)}%',
                ),
                const Divider(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'OPERATING EXPENSES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '-${CurrencyFormatter.format(pl.operatingExpenses, currency: currency)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (pl.expenseBreakdown.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'No operating expenses recorded for this period.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  )
                else
                  ...pl.expenseBreakdown.map((exp) {
                    final cat = exp['category'] as String;
                    final amt = (exp['total'] as num).toDouble();
                    final pct = pl.operatingExpenses > 0 ? (amt / pl.operatingExpenses) * 100 : 0.0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.warning,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              cat,
                              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                            ),
                          ),
                          Text(
                            '${pct.toStringAsFixed(0)}%  ',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          Text(
                            '-${CurrencyFormatter.format(amt, currency: currency)}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  }),

                const Divider(height: 28, thickness: 1.5),

                // Bottom Line
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'NET PROFIT (BOTTOM LINE)',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                    Text(
                      CurrencyFormatter.format(pl.netProfit, currency: currency),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: isProfit ? AppColors.primary : Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Financial Health Overview Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Key Performance Indicators',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _kpiMiniTile(
                        'Gross Margin',
                        '${grossMargin.toStringAsFixed(1)}%',
                        'Profit after inventory cost',
                        Icons.pie_chart_outline,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _kpiMiniTile(
                        'Net Margin',
                        '${netMargin.toStringAsFixed(1)}%',
                        'Take-home percentage',
                        Icons.trending_up,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _kpiMiniTile(
                        'Expense Ratio',
                        pl.revenue > 0
                            ? '${((pl.operatingExpenses / pl.revenue) * 100).toStringAsFixed(1)}%'
                            : '0.0%',
                        'Expenses as % of sales',
                        Icons.receipt_long_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _kpiMiniTile(
                        'COGS Ratio',
                        pl.revenue > 0
                            ? '${((pl.cogs / pl.revenue) * 100).toStringAsFixed(1)}%'
                            : '0.0%',
                        'Stock acquisition cost',
                        Icons.inventory_outlined,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportLineItem(
    String label,
    double value, {
    required String currency,
    bool isBold = false,
    bool isNegative = false,
    bool isPositive = false,
    String? subtitle,
    String? tag,
    Color? color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                      fontSize: isBold ? 14 : 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isNegative
                      ? '-${CurrencyFormatter.format(value.abs(), currency: currency)}'
                      : CurrencyFormatter.format(value, currency: currency),
                  style: TextStyle(
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                    fontSize: isBold ? 15 : 13,
                    color: color ?? (isNegative ? Colors.red.shade800 : AppColors.textPrimary),
                  ),
                ),
                if (tag != null)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _kpiMiniTile(String label, String value, String description, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: SALES & CATEGORIES
  // ==========================================
  Widget _buildSalesAndCategoriesTab(
    BuildContext context,
    List<Map<String, dynamic>> categories,
    List<Map<String, dynamic>> salesItems,
    String currency,
  ) {
    final totalSalesRevenue = categories.fold<double>(0.0, (acc, c) => acc + (c['revenue'] as double));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshReports,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // 1. Category Distribution Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Category Performance',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    Text(
                      CurrencyFormatter.format(totalSalesRevenue, currency: currency),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (categories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No sales recorded for this period.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  )
                else
                  ...categories.map((c) {
                    final name = c['category'] as String;
                    final rev = c['revenue'] as double;
                    final pct = (c['percentage'] as num?)?.toDouble() ?? 0.0;
                    final units = (c['units_sold'] as num?)?.toDouble() ?? 0.0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              Text(
                                '${CurrencyFormatter.format(rev, currency: currency)} (${pct.toStringAsFixed(1)}%)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: pct / 100,
                                    backgroundColor: AppColors.primaryLight,
                                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                    minHeight: 6,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${CurrencyFormatter.formatQty(units)} units',
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Product Items Performance
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Itemized Product Sales',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    Text(
                      '${salesItems.length} products',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Search Bar
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search product in sales...',
                      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textSecondary),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
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
                const SizedBox(height: 16),

                if (salesItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('No matching items found.', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  )
                else
                  ...salesItems.map((item) {
                    final name = item['product'] as String;
                    final unit = item['unit'] as String;
                    final qty = (item['quantity'] as num).toDouble();
                    final price = (item['unit_price'] as num).toDouble();
                    final rev = (item['revenue'] as num).toDouble();
                    final gross = (item['gross_profit'] as num).toDouble();
                    final margin = (item['margin'] as num).toDouble();

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${CurrencyFormatter.formatQty(qty)} $unit sold · Avg: ${CurrencyFormatter.format(price, currency: currency)}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                CurrencyFormatter.format(rev, currency: currency),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.primary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Profit: ${CurrencyFormatter.format(gross, currency: currency)} (${margin.toStringAsFixed(0)}%)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: gross >= 0 ? AppColors.success : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: INVENTORY VALUATION
  // ==========================================
  Widget _buildInventoryValuationTab(BuildContext context, Map<String, dynamic> inv, String currency) {
    final totalCost = inv['total_cost_value'] as double;
    final totalRetail = inv['total_retail_value'] as double;
    final potentialProfit = inv['potential_profit'] as double;
    final potentialMargin = inv['potential_margin'] as double;
    final items = inv['items'] as List<Map<String, dynamic>>;
    final lowStockCount = inv['low_stock_count'] as int;
    final outOfStockCount = inv['out_of_stock_count'] as int;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshReports,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Total Valuation Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  AppColors.primaryLight,
                  Color(0xFFE2F4F7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primaryBorder),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryGlow,
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'STOCK VALUE (AT COST PRICE)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  CurrencyFormatter.format(totalCost, currency: currency, showDecimals: true),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Expected Retail Value', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          Text(
                            CurrencyFormatter.format(totalRetail, currency: currency),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Potential Gross Profit', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          Text(
                            '+${CurrencyFormatter.format(potentialProfit, currency: currency)} (${potentialMargin.toStringAsFixed(0)}%)',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.success),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stock Alerts Status Row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: lowStockCount > 0 ? AppColors.warning : AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$lowStockCount Low Stock',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: lowStockCount > 0 ? Colors.orange.shade800 : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: outOfStockCount > 0 ? AppColors.error : AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$outOfStockCount Out of Stock',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: outOfStockCount > 0 ? Colors.red.shade800 : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Product Valuation List
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Catalog Breakdown', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('${items.length} items', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 12),

                // Search Box
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search product in inventory...',
                      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textSecondary),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
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
                const SizedBox(height: 16),

                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No catalog products found.', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  )
                else
                  ...items.map((p) {
                    final name = p['name'] as String;
                    final category = p['category'] as String;
                    final unit = p['unit'] as String;
                    final stock = (p['stock'] as num).toDouble();
                    final cost = (p['cost_price'] as num).toDouble();
                    final price = (p['selling_price'] as num).toDouble();
                    final costVal = (p['stock_cost_value'] as num).toDouble();
                    final margin = (p['margin'] as num).toDouble();
                    final isLow = p['is_low_stock'] as bool;
                    final isOut = p['is_out_of_stock'] as bool;

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isOut
                              ? Colors.red.withValues(alpha: 0.3)
                              : isLow
                                  ? Colors.orange.withValues(alpha: 0.3)
                                  : AppColors.border.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isOut)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'OUT',
                                          style: TextStyle(color: Colors.red.shade800, fontSize: 9, fontWeight: FontWeight.bold),
                                        ),
                                      )
                                    else if (isLow)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'LOW',
                                          style: TextStyle(color: Colors.orange.shade900, fontSize: 9, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Stock: ${CurrencyFormatter.formatQty(stock)} $unit · Cost: ${CurrencyFormatter.format(cost, currency: currency)} · Price: ${CurrencyFormatter.format(price, currency: currency)}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Category: $category',
                                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                CurrencyFormatter.format(costVal, currency: currency),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.primary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Margin: ${margin.toStringAsFixed(0)}%',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 4: DEBTORS & RECEIVABLES
  // ==========================================
  Widget _buildDebtorsTab(BuildContext context, Map<String, dynamic> debtData, String currency) {
    final totalDebt = debtData['total_debt'] as double;
    final count = debtData['count'] as int;
    final debtors = debtData['debtors'] as List<Customer>;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshReports,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Total Receivables Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFEF3C7),
                  const Color(0xFFFFFBEB),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL OUTSTANDING RECEIVABLES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Colors.amber.shade900,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count debtor(s)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  CurrencyFormatter.format(totalDebt, currency: currency, showDecimals: true),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: Colors.amber.shade900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Credit granted to customers awaiting collection.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Debtors List Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Debtor Customer Directory', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 12),

                // Search bar
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search debtor by name or phone...',
                      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textSecondary),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
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
                const SizedBox(height: 16),

                if (debtors.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.check_circle_outline, size: 40, color: AppColors.success.withValues(alpha: 0.6)),
                          const SizedBox(height: 8),
                          const Text(
                            'No outstanding customer debts!',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'All customer accounts are settled.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...debtors.map((cust) {
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.primaryLight,
                            child: Text(
                              cust.name.isNotEmpty ? cust.name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cust.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                if (cust.phone.isNotEmpty)
                                  Text(
                                    cust.phone,
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                CurrencyFormatter.format(cust.outstanding, currency: currency),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  color: Colors.red,
                                ),
                              ),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: () => _recordCustomerPaymentDialog(context, cust, currency),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Collect',
                                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
