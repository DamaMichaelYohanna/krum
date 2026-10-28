import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/store_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

class CashDrawerScreen extends StatefulWidget {
  const CashDrawerScreen({super.key});

  @override
  State<CashDrawerScreen> createState() => _CashDrawerScreenState();
}

class _CashDrawerScreenState extends State<CashDrawerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showStartShiftDialog(BuildContext context) {
    final floatController = TextEditingController();
    final notesController = TextEditingController();
    String? errorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 24,
            left: 20,
            right: 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Start Shift / Open Drawer',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(sheetCtx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter the cash float placed in the till at the beginning of the shift for giving change.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(errorText!, style: TextStyle(color: Colors.red.shade800, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: floatController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Opening Cash Float (₦) *',
                    hintText: 'e.g. 5000 or 0',
                    prefixIcon: Icon(Icons.payments_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Opening Notes (Optional)',
                    hintText: 'e.g. Morning Shift - Mary',
                    prefixIcon: Icon(Icons.notes_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Open Drawer & Start Shift', style: TextStyle(fontSize: 15)),
                    onPressed: () async {
                      final val = double.tryParse(floatController.text.trim()) ?? 0.0;
                      if (val < 0) {
                        setModalState(() => errorText = 'Opening float cannot be negative.');
                        return;
                      }

                      final provider = context.read<StoreProvider>();
                      final success = await provider.startShift(
                        openingFloat: val,
                        openingNotes: notesController.text.trim(),
                      );

                      if (!mounted) return;
                      if (success) {
                        Navigator.pop(sheetCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cash drawer opened. Shift started!')),
                        );
                      } else {
                        setModalState(() => errorText = provider.errorMessage);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCloseShiftDialog(BuildContext context) {
    final provider = context.read<StoreProvider>();
    final metrics = provider.currentDrawerMetrics;
    final expectedCash = metrics['expectedCash'] ?? 0.0;
    final currency = provider.business?.currency ?? 'NGN';

    final countedController = TextEditingController();
    final notesController = TextEditingController();
    double countedVal = 0.0;
    String? errorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final diff = countedVal - expectedCash;
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              top: 24,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'End of Shift / Balance Drawer',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Count all physical cash in the till and input the total to close shift.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),

                  const SizedBox(height: 14),

                  // Expected Drawer Total Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Expected Cash in Till:',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          CurrencyFormatter.format(expectedCash, currency: currency),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Counted Cash Input
                  TextField(
                    controller: countedController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Actual Counted Cash (₦) *',
                      hintText: 'e.g. 45000',
                      prefixIcon: Icon(Icons.point_of_sale),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        countedVal = double.tryParse(val.trim()) ?? 0.0;
                      });
                    },
                  ),

                  const SizedBox(height: 10),

                  // Quick Denomination helpers
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [1000, 500, 200, 100].map((d) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text('+₦$d'),
                            onPressed: () {
                              final cur = double.tryParse(countedController.text) ?? 0.0;
                              final next = cur + d;
                              countedController.text = next.toStringAsFixed(0);
                              setModalState(() => countedVal = next);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Difference Feedback Banner
                  if (countedController.text.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: diff.abs() < 0.01
                            ? const Color(0xFFE6F4EA)
                            : diff > 0
                                ? const Color(0xFFE8EEF9)
                                : const Color(0xFFFCE8E6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: diff.abs() < 0.01
                              ? const Color(0xFF34A853)
                              : diff > 0
                                  ? const Color(0xFF1A73E8)
                                  : const Color(0xFFEA4335),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            diff.abs() < 0.01
                                ? Icons.check_circle_outline
                                : (diff > 0 ? Icons.info_outline : Icons.warning_amber_rounded),
                            color: diff.abs() < 0.01
                                ? const Color(0xFF137333)
                                : (diff > 0 ? const Color(0xFF174EA6) : const Color(0xFFC5221F)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  diff.abs() < 0.01
                                      ? 'Drawer is perfectly balanced!'
                                      : (diff > 0
                                          ? 'Cash Overage: +${CurrencyFormatter.format(diff, currency: currency)}'
                                          : 'Cash Shortage: ${CurrencyFormatter.format(diff, currency: currency)}'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: diff.abs() < 0.01
                                        ? const Color(0xFF137333)
                                        : (diff > 0 ? const Color(0xFF174EA6) : const Color(0xFFC5221F)),
                                  ),
                                ),
                                Text(
                                  diff.abs() < 0.01
                                      ? 'Counted cash exactly matches transactions.'
                                      : 'Expected: ${CurrencyFormatter.format(expectedCash, currency: currency)} · Counted: ${CurrencyFormatter.format(countedVal, currency: currency)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  TextField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Closing / Discrepancy Notes',
                      hintText: 'e.g. ₦200 short due to mistake giving change',
                      prefixIcon: Icon(Icons.edit_note),
                      border: OutlineInputBorder(),
                    ),
                  ),

                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm & Close Shift', style: TextStyle(fontSize: 15)),
                      onPressed: () async {
                        if (countedController.text.trim().isEmpty) {
                          setModalState(() => errorText = 'Please enter actual counted cash amount.');
                          return;
                        }

                        final prov = context.read<StoreProvider>();
                        final closedSession = await prov.closeShift(
                          closingCashActual: countedVal,
                          closingNotes: notesController.text.trim(),
                        );

                        if (!mounted) return;
                        if (closedSession != null) {
                          Navigator.pop(sheetCtx);
                          _showClosedSummaryDialog(context, closedSession);
                        } else {
                          setModalState(() => errorText = prov.errorMessage);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showClosedSummaryDialog(BuildContext context, Map<String, dynamic> session) {
    final currency = context.read<StoreProvider>().business?.currency ?? 'NGN';
    final openFloat = (session['opening_float'] as num?)?.toDouble() ?? 0.0;
    final cashSales = (session['cash_sales'] as num?)?.toDouble() ?? 0.0;
    final otherSales = (session['other_sales'] as num?)?.toDouble() ?? 0.0;
    final expenses = (session['cash_expenses'] as num?)?.toDouble() ?? 0.0;
    final expected = (session['expected_cash'] as num?)?.toDouble() ?? 0.0;
    final actual = (session['closing_cash_actual'] as num?)?.toDouble() ?? 0.0;
    final diff = (session['difference'] as num?)?.toDouble() ?? 0.0;
    final notes = session['closing_notes'] as String? ?? '';

    final textReport = '''
==============================
KRUM POS - SHIFT CLOSING REPORT
==============================
Store: ${context.read<StoreProvider>().business?.name ?? "Krum Store"}
Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}
Cashier: ${session['cashier_name'] ?? context.read<StoreProvider>().username}
------------------------------
Opening Float:        ${CurrencyFormatter.format(openFloat, currency: currency)}
+ Cash Sales:         ${CurrencyFormatter.format(cashSales, currency: currency)}
- Cash Expenses:      ${CurrencyFormatter.format(expenses, currency: currency)}
------------------------------
Expected Drawer Cash: ${CurrencyFormatter.format(expected, currency: currency)}
Actual Counted Cash:  ${CurrencyFormatter.format(actual, currency: currency)}
Difference:           ${diff >= 0 ? "+" : ""}${CurrencyFormatter.format(diff, currency: currency)} (${diff == 0 ? "BALANCED" : (diff > 0 ? "OVER" : "SHORT")})
------------------------------
Non-Cash (Bank/POS):  ${CurrencyFormatter.format(otherSales, currency: currency)}
Total Sales Made:     ${CurrencyFormatter.format(cashSales + otherSales, currency: currency)}
${notes.isNotEmpty ? "\nNotes: $notes" : ""}
==============================
''';

    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              diff.abs() < 0.01 ? Icons.check_circle : (diff > 0 ? Icons.info : Icons.warning),
              color: diff.abs() < 0.01 ? Colors.green : (diff > 0 ? Colors.blue : Colors.red),
            ),
            const SizedBox(width: 8),
            const Text('Shift Balanced & Closed'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Expected: ${CurrencyFormatter.format(expected, currency: currency)}'),
            Text('Counted: ${CurrencyFormatter.format(actual, currency: currency)}'),
            const SizedBox(height: 6),
            Text(
              'Difference: ${diff >= 0 ? "+" : ""}${CurrencyFormatter.format(diff, currency: currency)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: diff.abs() < 0.01 ? Colors.green : (diff > 0 ? Colors.blue : Colors.red),
              ),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Note: $notes', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Done')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy Report'),
            onPressed: () {
              Navigator.pop(dCtx);
              Clipboard.setData(ClipboardData(text: textReport));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Shift report copied to clipboard for WhatsApp / sharing!'),
                  backgroundColor: AppColors.primary,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final isShiftActive = provider.isShiftActive;
    final currentSession = provider.currentCashSession;
    final metrics = provider.currentDrawerMetrics;
    final currency = provider.business?.currency ?? 'NGN';
    final historySessions = provider.cashSessions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Drawer & Shifts'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.point_of_sale), text: 'Active Till'),
            Tab(icon: Icon(Icons.history), text: 'Shift History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Active Till & Live Reconciliation
          RefreshIndicator(
            onRefresh: () => provider.refreshCashSessions(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!isShiftActive) ...[
                  // Drawer Closed State Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.lock_clock, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          'Cash Drawer is Closed',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Open drawer and enter your opening cash float to begin shift tracking and live till reconciliation.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Start Shift / Open Drawer', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () => _showStartShiftDialog(context),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Active Shift Header Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F4EA),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF34A853).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.fiber_manual_record, color: Color(0xFF137333), size: 12),
                            SizedBox(width: 6),
                            Text(
                              'SHIFT ACTIVE',
                              style: TextStyle(color: Color(0xFF137333), fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Opened: ${DateFormat('hh:mm a').format(DateTime.tryParse(currentSession?['opened_at'] ?? '') ?? DateTime.now())}',
                        style: const TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Expected Cash Hero Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.85)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Expected Cash in Drawer (Till)',
                          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          CurrencyFormatter.format(metrics['expectedCash'] ?? 0.0, currency: currency),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Cashier: ${currentSession?['cashier_name'] ?? provider.username}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Detailed Breakdown Grid
                  const Text(
                    'Till Cash Movement',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: _metricCard(
                          title: 'Opening Float',
                          amount: metrics['openingFloat'] ?? 0.0,
                          currency: currency,
                          icon: Icons.account_balance_wallet_outlined,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _metricCard(
                          title: '+ Cash Sales',
                          amount: metrics['cashSales'] ?? 0.0,
                          currency: currency,
                          icon: Icons.trending_up,
                          color: const Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: _metricCard(
                          title: '+ Debt Payments',
                          amount: metrics['cashDebtPayments'] ?? 0.0,
                          currency: currency,
                          icon: Icons.payments_outlined,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _metricCard(
                          title: '- Cash Expenses',
                          amount: metrics['cashExpenses'] ?? 0.0,
                          currency: currency,
                          icon: Icons.money_off,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Non-Cash Digital Sales Note
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.credit_card, color: Colors.indigo, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Bank Transfer / POS Card Sales: ${CurrencyFormatter.format(metrics['otherSales'] ?? 0.0, currency: currency)} (Paid directly to bank account)',
                            style: TextStyle(color: Colors.indigo.shade900, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Close Shift Primary Action
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text(
                        'Close Shift & Balance Drawer',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _showCloseShiftDialog(context),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Tab 2: Shift History & Audit Log
          RefreshIndicator(
            onRefresh: () => provider.refreshCashSessions(),
            child: historySessions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_toggle_off, size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          'No closed shift sessions yet',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Past shift balances and till audits will appear here.',
                          style: TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: historySessions.length,
                    itemBuilder: (context, index) {
                      final s = historySessions[index];
                      final isClosed = s['status'] == 'closed';
                      final openedAt = DateTime.tryParse(s['opened_at'] ?? '') ?? DateTime.now();
                      final diff = (s['difference'] as num?)?.toDouble() ?? 0.0;
                      final expected = (s['expected_cash'] as num?)?.toDouble() ?? 0.0;
                      final actual = (s['closing_cash_actual'] as num?)?.toDouble() ?? expected;

                      return Card(
                        elevation: 0.5,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: !isClosed
                                ? Colors.green.shade50
                                : (diff.abs() < 0.01
                                    ? Colors.green.shade50
                                    : (diff > 0 ? Colors.blue.shade50 : Colors.red.shade50)),
                            child: Icon(
                              !isClosed
                                  ? Icons.timelapse
                                  : (diff.abs() < 0.01 ? Icons.check : (diff > 0 ? Icons.arrow_upward : Icons.arrow_downward)),
                              color: !isClosed
                                  ? Colors.green
                                  : (diff.abs() < 0.01 ? Colors.green : (diff > 0 ? Colors.blue : Colors.red)),
                            ),
                          ),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                s['cashier_name'] ?? 'Cashier',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Text(
                                DateFormat('MMM dd, hh:mm a').format(openedAt),
                                style: const TextStyle(fontSize: 12, color: Colors.black54),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Counted: ${CurrencyFormatter.format(actual, currency: currency)}'),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: diff.abs() < 0.01
                                        ? Colors.green.shade50
                                        : (diff > 0 ? Colors.blue.shade50 : Colors.red.shade50),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    diff.abs() < 0.01
                                        ? 'BALANCED'
                                        : (diff > 0
                                            ? '+${CurrencyFormatter.format(diff, currency: currency)}'
                                            : CurrencyFormatter.format(diff, currency: currency)),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: diff.abs() < 0.01
                                          ? Colors.green.shade800
                                          : (diff > 0 ? Colors.blue.shade800 : Colors.red.shade800),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onTap: isClosed ? () => _showClosedSummaryDialog(context, s) : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required double amount,
    required String currency,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            CurrencyFormatter.format(amount, currency: currency),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
