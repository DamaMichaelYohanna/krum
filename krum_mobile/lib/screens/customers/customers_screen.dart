import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/store_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_search_bar.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showNewCustomerDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final debtController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Customer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Customer Name *',
                  hintText: 'e.g. John Okafor',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number (Optional)',
                  hintText: 'e.g. 08012345678',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: debtController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Opening Debt (₦, Optional)',
                  hintText: '0',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                  helperText: 'Existing balance owed before today',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter customer name')),
                );
                return;
              }
              final initialDebt = double.tryParse(debtController.text.trim()) ?? 0.0;
              final provider = context.read<StoreProvider>();
              final customer = await provider.createCustomer(
                name,
                phone: phoneController.text.trim(),
                initialDebt: initialDebt,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted && customer != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Customer "$name" added successfully!'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              }
            },
            child: const Text('Save Customer'),
          ),
        ],
      ),
    );
  }

  void _showEditCustomerDialog(Customer customer) {
    final nameController = TextEditingController(text: customer.name);
    final phoneController = TextEditingController(text: customer.phone);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Customer Name *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final provider = context.read<StoreProvider>();
              final updated = customer.copyWith(name: name, phone: phoneController.text.trim());
              final success = await provider.updateCustomer(updated);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted && success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Customer "$name" updated!'), backgroundColor: AppColors.primary),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCustomer(Customer customer) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Customer?'),
        content: Text(
          'Are you sure you want to delete ${customer.name}?${customer.outstanding > 0 ? "\n\nWarning: This customer has an outstanding debt of ₦${customer.outstanding.toStringAsFixed(0)}." : ""}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final provider = context.read<StoreProvider>();
              final success = await provider.deleteCustomer(customer.id);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted && success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Customer "${customer.name}" deleted'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showRecordPaymentDialog(Customer customer) {
    final amountController = TextEditingController(text: customer.outstanding.toStringAsFixed(0));
    final refController = TextEditingController();
    String method = 'cash';
    final currency = context.read<StoreProvider>().business?.currency ?? 'NGN';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.payments_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Record Debt Payment: ${customer.name}')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Debt: ${CurrencyFormatter.format(customer.outstanding, currency: currency)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Payment Amount (₦) *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Payment Method', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'transfer', child: Text('Bank Transfer')),
                  DropdownMenuItem(value: 'pos', child: Text('POS')),
                ],
                onChanged: (val) => setDialogState(() => method = val ?? 'cash'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: refController,
                decoration: const InputDecoration(
                  labelText: 'Reference / Note (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text) ?? 0.0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter an amount greater than 0')),
                  );
                  return;
                }
                if (amount > customer.outstanding) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Payment cannot exceed total outstanding balance')),
                  );
                  return;
                }

                Navigator.pop(ctx);
                final provider = context.read<StoreProvider>();
                await provider.recordCustomerPayment(
                  customerId: customer.id,
                  amount: amount,
                  method: method,
                  reference: refController.text.trim(),
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Payment of ${CurrencyFormatter.format(amount, currency: currency)} recorded!'),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                }
              },
              child: const Text('Save Payment'),
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

    final allCustomers = provider.customers.where((c) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return c.name.toLowerCase().contains(q) || c.phone.toLowerCase().contains(q);
    }).toList();

    final debtors = allCustomers.where((c) => c.outstanding > 0).toList();
    final totalOwed = debtors.fold(0.0, (acc, c) => acc + c.outstanding);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers & Debtors'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: 'Debtors (${debtors.length})'),
            Tab(text: 'All Customers (${allCustomers.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Debt Total Banner (if on Debtors tab)
          if (totalOwed > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: Colors.amber.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Outstanding Debt:',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                  Text(
                    CurrencyFormatter.format(totalOwed, currency: currency),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: AppSearchBar(
              controller: _searchController,
              hintText: 'Search customer by name or phone...',
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Debtors
                debtors.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline, size: 48, color: Colors.green.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'No outstanding customer debts!',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Credit sales will show here automatically.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: debtors.length,
                        itemBuilder: (context, i) {
                          final debtor = debtors[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.amber.shade200),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.amber.shade100,
                                child: Icon(Icons.person, color: Colors.amber.shade900),
                              ),
                              title: Text(debtor.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(debtor.phone.isEmpty ? 'No phone' : debtor.phone),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    CurrencyFormatter.format(debtor.outstanding, currency: currency),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.tonal(
                                    onPressed: () => _showRecordPaymentDialog(debtor),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    ),
                                    child: const Text('Pay', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                // Tab 2: All Customers
                allCustomers.isEmpty
                    ? const Center(child: Text('No customers found'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: allCustomers.length,
                        itemBuilder: (context, i) {
                          final c = allCustomers[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(c.phone.isEmpty ? 'No phone' : c.phone),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  c.outstanding > 0
                                      ? Text(
                                          'Owes ${CurrencyFormatter.format(c.outstanding, currency: currency)}',
                                          style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold),
                                        )
                                      : const Text('No debt', style: TextStyle(color: Colors.black45)),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 20),
                                    onSelected: (action) {
                                      if (action == 'edit') {
                                        _showEditCustomerDialog(c);
                                      } else if (action == 'pay') {
                                        _showRecordPaymentDialog(c);
                                      } else if (action == 'delete') {
                                        _confirmDeleteCustomer(c);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      if (c.outstanding > 0)
                                        const PopupMenuItem(
                                          value: 'pay',
                                          child: Row(
                                            children: [
                                              Icon(Icons.payment, size: 18, color: AppColors.primary),
                                              SizedBox(width: 8),
                                              Text('Record Payment'),
                                            ],
                                          ),
                                        ),
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit, size: 18),
                                            SizedBox(width: 8),
                                            Text('Edit Customer'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Delete Customer', style: TextStyle(color: Colors.red)),
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
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewCustomerDialog,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Add Customer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
