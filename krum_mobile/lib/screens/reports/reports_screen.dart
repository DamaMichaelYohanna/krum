import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/store_provider.dart';
import '../../utils/formatters.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedPeriod = 'this_month';
  bool _loading = false;
  List<dynamic> _salesItems = [];
  List<dynamic> _inventoryItems = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadReportData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReportData() async {
    final provider = context.read<StoreProvider>();
    if (!provider.isAuthenticated) return;
    setState(() => _loading = true);

    try {
      await provider.loadProfitLoss(period: _selectedPeriod);
      _salesItems = await provider.api.getSalesReport(period: _selectedPeriod);
      _inventoryItems = await provider.api.getInventoryReport();
    } catch (_) {}

    setState(() => _loading = false);
  }

  void _exportReport(String type) async {
    final provider = context.read<StoreProvider>();
    try {
      final csvData = await provider.api.exportReportCsv(type, period: _selectedPeriod);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('$type Report Exported'),
            content: SingleChildScrollView(
              child: Text(csvData, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final currency = provider.business?.currency ?? 'NGN';
    final pl = provider.profitLoss;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Reports'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export CSV Report',
            onSelected: _exportReport,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'sales', child: Text('Export Sales Report (CSV)')),
              PopupMenuItem(value: 'inventory', child: Text('Export Inventory Report (CSV)')),
              PopupMenuItem(value: 'debtors', child: Text('Export Debtors Report (CSV)')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Profit & Loss'),
            Tab(text: 'Sales Report'),
            Tab(text: 'Inventory Valuation'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Period Selector Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Period:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                DropdownButton<String>(
                  value: _selectedPeriod,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'today', child: Text('Today')),
                    DropdownMenuItem(value: 'yesterday', child: Text('Yesterday')),
                    DropdownMenuItem(value: 'this_week', child: Text('This Week')),
                    DropdownMenuItem(value: 'this_month', child: Text('This Month')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedPeriod = val);
                      _loadReportData();
                    }
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Profit & Loss Statement (Section 20, 27)
                      _buildProfitLossView(context, pl, currency),

                      // Tab 2: Sales Report
                      _buildSalesReportView(context, _salesItems, currency),

                      // Tab 3: Inventory Valuation Report
                      _buildInventoryValuationView(context, _inventoryItems, currency),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitLossView(BuildContext context, ProfitLossData? pl, String currency) {
    if (pl == null) {
      return const Center(child: Text('No data for this period.'));
    }

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'Profit & Loss Statement',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),

        _statementRow('Sales Revenue', pl.revenue, isBold: true, color: AppColors.primary, currency: currency),
        _statementRow('Cost of Goods Sold (COGS)', -pl.cogs, isNegative: true, currency: currency),
        const Divider(),
        _statementRow('Gross Profit', pl.grossProfit, isBold: true, color: Colors.teal.shade800, currency: currency),
        const SizedBox(height: 14),

        const Text(
          'Operating Expenses',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 8),

        if (pl.expenseBreakdown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('No operating expenses logged for this period.', style: TextStyle(color: Colors.black54, fontSize: 13)),
          )
        else
          ...pl.expenseBreakdown.map((e) => _statementRow(
                e['category'] as String,
                -(e['total'] as double),
                indent: true,
                isNegative: true,
                currency: currency,
              )),

        _statementRow('Total Operating Expenses', -pl.operatingExpenses, isBold: true, isNegative: true, currency: currency),
        const Divider(thickness: 2),

        // Net Profit Box
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pl.netProfit >= 0 ? Colors.green.shade50 : Colors.red.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: pl.netProfit >= 0 ? Colors.green.shade200 : Colors.red.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'NET PROFIT:',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              Text(
                CurrencyFormatter.format(pl.netProfit, currency: currency),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: pl.netProfit >= 0 ? AppColors.primary : Colors.red.shade900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statementRow(
    String label,
    double value, {
    bool isBold = false,
    bool indent = false,
    bool isNegative = false,
    Color? color,
    required String currency,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: indent ? 16 : 0, top: 6, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: isBold ? 15 : 13,
              color: Colors.black87,
            ),
          ),
          Text(
            isNegative
                ? '-${CurrencyFormatter.format(value.abs(), currency: currency)}'
                : CurrencyFormatter.format(value, currency: currency),
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              fontSize: isBold ? 15 : 13,
              color: color ?? (isNegative ? Colors.deepOrange.shade900 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesReportView(BuildContext context, List<dynamic> items, String currency) {
    if (items.isEmpty) {
      return const Center(child: Text('No sales records in this period.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = items[i] as Map<String, dynamic>;
        final rev = (item['revenue'] as num).toDouble();
        final gross = (item['gross_profit'] as num).toDouble();

        return ListTile(
          dense: true,
          title: Text('${item['product']} (${item['quantity']} ${item['unit']})', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('Unit price: ${CurrencyFormatter.format((item['unit_price'] as num).toDouble(), currency: currency)} · Gross profit: ${CurrencyFormatter.format(gross, currency: currency)}'),
          trailing: Text(
            CurrencyFormatter.format(rev, currency: currency),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        );
      },
    );
  }

  Widget _buildInventoryValuationView(BuildContext context, List<dynamic> items, String currency) {
    if (items.isEmpty) {
      return const Center(child: Text('No inventory items found.'));
    }

    final totalValuation = items.fold(0.0, (sum, i) => sum + ((i['stock_value'] as num?)?.toDouble() ?? 0.0));

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.teal.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Stock Value:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Text(
                CurrencyFormatter.format(totalValuation, currency: currency),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal.shade900),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = items[i] as Map<String, dynamic>;
              final val = (p['stock_value'] as num?)?.toDouble() ?? 0.0;
              final qty = (p['stock_base'] as num?)?.toDouble() ?? 0.0;

              return ListTile(
                dense: true,
                title: Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Stock: ${CurrencyFormatter.formatQty(qty)} ${p['unit']} · Avg Cost: ₦${p['average_cost']}'),
                trailing: Text(
                  CurrencyFormatter.format(val, currency: currency),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
