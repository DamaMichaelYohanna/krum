import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../providers/store_provider.dart';
import '../customers/customers_screen.dart';
import '../expenses/expenses_screen.dart';
import '../purchases/add_purchase_screen.dart';
import '../reports/reports_screen.dart';
import '../sales/sales_history_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showServerConfigDialog(BuildContext context) {
    final provider = context.read<StoreProvider>();
    final urlController = TextEditingController(text: provider.api.baseUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backend Server URL'),
        content: TextField(
          controller: urlController,
          decoration: const InputDecoration(
            hintText: 'http://127.0.0.1:8000/api',
            labelText: 'API Base URL',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await provider.api.setBaseUrl(urlController.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showNewUnitDialog(BuildContext context) {
    final unitNameController = TextEditingController();
    final unitSymbolController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Custom Unit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: unitNameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Unit Name',
                hintText: 'e.g. Paint Bucket, Mudu, Crate, Bag',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: unitSymbolController,
              decoration: const InputDecoration(
                labelText: 'Symbol (optional)',
                hintText: 'e.g. mudu, bkt',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = unitNameController.text.trim();
              if (name.isNotEmpty) {
                final provider = context.read<StoreProvider>();
                await provider.createCustomUnit(name, symbol: unitSymbolController.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showNewCategoryDialog(BuildContext context) {
    final catController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Category'),
        content: TextField(
          controller: catController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            hintText: 'e.g. Beverages, Provisions, Toiletries',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = catController.text.trim();
              if (name.isNotEmpty) {
                await context.read<StoreProvider>().createCategory(name);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showCategoriesManagerDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Consumer<StoreProvider>(
        builder: (context, provider, _) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Product Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: AppColors.primary),
                    onPressed: () => _showNewCategoryDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (provider.categories.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No categories added yet.')),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: provider.categories.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final cat = provider.categories[index];
                      final productCount = provider.products.where((p) => p.categoryId == cat.id).length;
                      return ListTile(
                        dense: true,
                        title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('$productCount product(s) in category'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () async {
                            await provider.deleteCategory(cat.id);
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUnitsManagerDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Consumer<StoreProvider>(
        builder: (context, provider, _) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Custom Units', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: AppColors.primary),
                    onPressed: () => _showNewUnitDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: provider.units.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final unit = provider.units[index];
                    final inUse = provider.products.any((p) => p.baseUnitId == unit.id || p.units.any((u) => u.unitId == unit.id));
                    return ListTile(
                      dense: true,
                      title: Text(unit.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(unit.symbol.isNotEmpty ? 'Symbol: ${unit.symbol}' : 'No symbol'),
                      trailing: inUse
                          ? const Chip(label: Text('In use', style: TextStyle(fontSize: 10)))
                          : IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              onPressed: () async {
                                await provider.deleteUnit(unit.id);
                              },
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final business = provider.business;
    final username = provider.username;
    final role = provider.userRole;

    return Scaffold(
      appBar: AppBar(
        title: const Text('More Options'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Store Profile Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary,
                  radius: 24,
                  child: Text(
                    business?.name.isNotEmpty == true ? business!.name[0].toUpperCase() : 'K',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        business?.name ?? 'Krum Store',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'User: $username (${role.toUpperCase()}) · Currency: ${business?.currency ?? "NGN"}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Business Operations Group
          _sectionHeader('Business Operations'),
          ListTile(
            leading: const Icon(Icons.people_outline, color: AppColors.primary),
            title: const Text('Customers & Debtors'),
            subtitle: Text('${provider.customers.where((c) => c.outstanding > 0).length} customer(s) owing'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomersScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined, color: AppColors.primary),
            title: const Text('Receive Stock / Supplier Purchases'),
            subtitle: Text('${provider.suppliers.length} registered suppliers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AddPurchaseScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined, color: Colors.deepOrange),
            title: const Text('Operating Expenses'),
            subtitle: const Text('Track generator fuel, electricity, transport'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpensesScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
            title: const Text('Sales & Items Sold History'),
            subtitle: const Text('View receipts, past transactions & items sold'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesHistoryScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart_outlined, color: Colors.indigo),
            title: const Text('Business Reports & Profit/Loss'),
            subtitle: const Text('Net profit, sales history, valuation'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
            },
          ),

          const Divider(),

          // Store Configurations (Categories, Units & Sync)
          _sectionHeader('Store Configuration'),
          ListTile(
            leading: const Icon(Icons.category_outlined, color: AppColors.primary),
            title: const Text('Product Categories'),
            subtitle: Text('${provider.categories.length} category(ies) defined'),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showNewCategoryDialog(context),
            ),
            onTap: () => _showCategoriesManagerDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.scale_outlined, color: AppColors.primary),
            title: const Text('Custom Units'),
            subtitle: Text('${provider.units.length} unit(s) defined (Mudu, Crate, Bag, etc.)'),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showNewUnitDialog(context),
            ),
            onTap: () => _showUnitsManagerDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.sync, color: AppColors.primary),
            title: const Text('Sync Now'),
            subtitle: Text(
              provider.pendingSyncCount == 0
                  ? 'All local records synchronized'
                  : '${provider.pendingSyncCount} offline transaction(s) queued',
            ),
            trailing: FilledButton.tonal(
              onPressed: () async {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Syncing with server...')),
                );
                await provider.syncNow();
              },
              child: const Text('Sync'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined, color: Colors.blueGrey),
            title: const Text('Server Connection'),
            subtitle: Text(provider.api.baseUrl),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _showServerConfigDialog(context),
          ),

          const Divider(),

          // Logout
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Log Out', style: TextStyle(color: Colors.red)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Log Out'),
                  content: const Text('Are you sure you want to log out of your store?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Log Out'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await provider.logout();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: Colors.black45,
        ),
      ),
    );
  }
}
