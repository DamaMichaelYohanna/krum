import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/store_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String _selectedPeriod = 'this_month';
  DateTimeRange? _customDateRange;
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _loading = false;

  final List<String> _categories = const [
    'All',
    'Electricity',
    'Fuel',
    'Transport',
    'Rent',
    'Staff salary',
    'Packaging',
    'Repairs',
    'Internet',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _refreshExpenses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshExpenses() async {
    final provider = context.read<StoreProvider>();
    if (!provider.isAuthenticated) return;
    setState(() => _loading = true);
    try {
      await provider.loadExpenses(
        period: _selectedPeriod,
        startDate: _customDateRange?.start,
        endDate: _customDateRange?.end,
        category: _selectedCategory == 'All' ? null : _selectedCategory,
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
            colorScheme: ColorScheme.light(
              primary: Colors.deepOrange,
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
      _refreshExpenses();
    }
  }

  void _showAddExpenseDialog() {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    String category = 'Electricity';
    DateTime expenseDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFFBE9E7),
                child: Icon(Icons.receipt_long_outlined, color: Colors.deepOrange),
              ),
              SizedBox(width: 12),
              Text('Record Expense', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Category *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: InputDecoration(
                    prefixIcon: Icon(_getCategoryIcon(category), color: Colors.deepOrange, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Electricity', child: Text('Electricity / NEPA')),
                    DropdownMenuItem(value: 'Fuel', child: Text('Fuel / Generator')),
                    DropdownMenuItem(value: 'Transport', child: Text('Transport / Logistics')),
                    DropdownMenuItem(value: 'Rent', child: Text('Shop Rent')),
                    DropdownMenuItem(value: 'Staff salary', child: Text('Staff Salary')),
                    DropdownMenuItem(value: 'Packaging', child: Text('Packaging / Bags')),
                    DropdownMenuItem(value: 'Repairs', child: Text('Repairs & Maintenance')),
                    DropdownMenuItem(value: 'Internet', child: Text('Internet / Data')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (val) => setDialogState(() => category = val ?? 'Other'),
                ),
                const SizedBox(height: 14),

                const Text('Amount (₦) *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixText: '₦ ',
                    prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.deepOrange),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),

                const Text('Expense Date *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: expenseDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: ColorScheme.light(
                              primary: Colors.deepOrange,
                              onPrimary: Colors.white,
                              surface: AppColors.surface,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setDialogState(() => expenseDate = picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 18, color: Colors.deepOrange),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            DateFormatter.format(expenseDate.toIso8601String().substring(0, 10)),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                const Text('Description (Optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: descController,
                  decoration: InputDecoration(
                    hintText: 'e.g. Generator petrol, NEPA token recharge',
                    hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () async {
                final amount = double.tryParse(amountController.text) ?? 0.0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter an amount greater than 0')),
                  );
                  return;
                }

                Navigator.pop(ctx);
                final provider = context.read<StoreProvider>();
                final dateStr = expenseDate.toIso8601String().substring(0, 10);
                await provider.recordExpense(
                  category: category,
                  amount: amount,
                  description: descController.text.trim(),
                  occurredAt: dateStr,
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Expense recorded and saved offline!'),
                      backgroundColor: Color(0xFF176B4D),
                    ),
                  );
                }
              },
              child: const Text('Save Expense', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteExpense(Expense expense) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense?'),
        content: Text('Are you sure you want to remove the expense for ${expense.category} of ₦${expense.amount.toStringAsFixed(0)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final provider = context.read<StoreProvider>();
              await provider.deleteExpense(expense);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Expense deleted')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'electricity':
        return Icons.bolt;
      case 'fuel':
        return Icons.local_gas_station;
      case 'transport':
        return Icons.directions_car;
      case 'rent':
        return Icons.storefront;
      case 'staff salary':
        return Icons.people;
      case 'packaging':
        return Icons.inventory_2;
      case 'repairs':
        return Icons.build_circle;
      case 'internet':
        return Icons.wifi;
      default:
        return Icons.receipt_long;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'electricity':
        return const Color(0xFFF59E0B);
      case 'fuel':
        return const Color(0xFFEF4444);
      case 'transport':
        return const Color(0xFF3B82F6);
      case 'rent':
        return const Color(0xFF8B5CF6);
      case 'staff salary':
        return const Color(0xFF10B981);
      case 'packaging':
        return const Color(0xFFD97706);
      case 'repairs':
        return const Color(0xFFEC4899);
      case 'internet':
        return const Color(0xFF06B6D4);
      default:
        return Colors.deepOrange;
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
          return DateFormatter.formatRange(_customDateRange!.start, _customDateRange!.end);
        }
        return 'Custom Range';
      case 'all':
        return 'All Time';
      default:
        return _selectedPeriod;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final currency = provider.business?.currency ?? 'NGN';

    final filteredExpenses = provider.filterExpenses(
      period: _selectedPeriod,
      startDate: _customDateRange?.start,
      endDate: _customDateRange?.end,
      category: _selectedCategory,
      searchQuery: _searchQuery,
    );

    final totalFiltered = filteredExpenses.fold<double>(
      0.0,
      (sum, item) => sum + item.amount,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Operating Expenses', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Expenses',
            onPressed: _refreshExpenses,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Date Filter Chips Bar
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

          // 2. Total Period Expenses Card
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFFF3E0),
                    const Color(0xFFFFE0B2).withValues(alpha: 0.4),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFCC80)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepOrange.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'TOTAL EXPENSES',
                              style: TextStyle(
                                color: Colors.deepOrange.shade800,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${filteredExpenses.length} ${filteredExpenses.length == 1 ? 'record' : 'records'}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          CurrencyFormatter.format(totalFiltered, currency: currency, showDecimals: true),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: Colors.deepOrange.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.date_range, size: 13, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _getPeriodLabel(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_selectedCategory != 'All') ...[
                              const Text(' · ', style: TextStyle(color: AppColors.textSecondary)),
                              Flexible(
                                child: Text(
                                  _selectedCategory,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.deepOrange.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.receipt_long, color: Colors.deepOrange, size: 24),
                  ),
                ],
              ),
            ),
          ),

          // 3. Search and Category Filter Strip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
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
                        hintText: 'Search description, category...',
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
                const SizedBox(width: 10),
                // Category Filter Dropdown Button
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _selectedCategory == 'All' ? AppColors.surface : Colors.deepOrange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedCategory == 'All' ? AppColors.border : Colors.deepOrange.shade200,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCategory,
                      icon: Icon(
                        Icons.filter_list,
                        size: 18,
                        color: _selectedCategory == 'All' ? AppColors.textSecondary : Colors.deepOrange,
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _selectedCategory == 'All' ? AppColors.textPrimary : Colors.deepOrange.shade900,
                      ),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedCategory = val);
                          _refreshExpenses();
                        }
                      },
                      items: _categories.map((cat) {
                        return DropdownMenuItem<String>(
                          value: cat,
                          child: Text(cat == 'All' ? 'All Categories' : cat),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 4. Expenses List or Empty State
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.deepOrange))
                : filteredExpenses.isEmpty
                    ? RefreshIndicator(
                        color: Colors.deepOrange,
                        onRefresh: _refreshExpenses,
                        child: LayoutBuilder(
                          builder: (context, constraints) => SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: constraints.maxHeight),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: Colors.deepOrange.shade50,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.receipt_long_outlined, size: 30, color: Colors.deepOrange.shade300),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        _searchQuery.isNotEmpty || _selectedCategory != 'All'
                                            ? 'No matching expenses found'
                                            : 'No expenses for ${_getPeriodLabel()}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _searchQuery.isNotEmpty || _selectedCategory != 'All'
                                            ? 'Try clearing your search or category filter.'
                                            : 'Log operating expenses like fuel, rent, or utilities.',
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                        textAlign: TextAlign.center,
                                      ),
                                      if (_selectedPeriod != 'all' || _selectedCategory != 'All' || _searchQuery.isNotEmpty) ...[
                                        const SizedBox(height: 16),
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              _selectedPeriod = 'this_month';
                                              _selectedCategory = 'All';
                                              _searchQuery = '';
                                              _searchController.clear();
                                              _customDateRange = null;
                                            });
                                          },
                                          icon: const Icon(Icons.filter_alt_off, size: 16),
                                          label: const Text('Reset All Filters'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.deepOrange,
                                            side: const BorderSide(color: Colors.deepOrange),
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
                      )
                    : RefreshIndicator(
                        color: Colors.deepOrange,
                        onRefresh: _refreshExpenses,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                          itemCount: filteredExpenses.length,
                          separatorBuilder: (_, index) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final item = filteredExpenses[i];
                            final catColor = _getCategoryColor(item.category);
                            final formattedDate = DateFormatter.format(item.occurredAt);

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
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: catColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(_getCategoryIcon(item.category), color: catColor, size: 22),
                                ),
                                title: Text(
                                  item.category,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (item.description.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        item.description,
                                        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time, size: 12, color: AppColors.textSecondary),
                                        const SizedBox(width: 4),
                                        Text(
                                          formattedDate,
                                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '-${CurrencyFormatter.format(item.amount, currency: currency)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        color: Colors.deepOrange.shade800,
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
                                      onSelected: (val) {
                                        if (val == 'delete') {
                                          _confirmDeleteExpense(item);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                              SizedBox(width: 8),
                                              Text('Delete', style: TextStyle(color: Colors.red)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddExpenseDialog,
        backgroundColor: Colors.deepOrange,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Record Expense', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
        _refreshExpenses();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepOrange : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.deepOrange : AppColors.border,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.deepOrange.withValues(alpha: 0.25),
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
          color: isSelected ? Colors.deepOrange : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.deepOrange : AppColors.border,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.deepOrange.withValues(alpha: 0.25),
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
