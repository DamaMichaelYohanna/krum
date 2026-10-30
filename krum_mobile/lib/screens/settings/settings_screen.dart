import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../providers/store_provider.dart';
import '../customers/customers_screen.dart';
import '../expenses/expenses_screen.dart';
import '../purchases/add_purchase_screen.dart';
import '../reports/reports_screen.dart';
import '../sales/sales_history_screen.dart';
import '../staff/staff_screen.dart';
import '../cash_drawer/cash_drawer_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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

  void _showEditStoreDialog(BuildContext context) {
    final provider = context.read<StoreProvider>();
    final business = provider.business;
    final nameController = TextEditingController(text: business?.name ?? '');
    final phoneController = TextEditingController(text: business?.phone ?? '');
    String selectedCurrency = business?.currency ?? 'NGN';

    final currencies = [
      {'code': 'NGN', 'label': 'Nigerian Naira (₦)'},
      {'code': 'USD', 'label': 'US Dollar (\$)'},
      {'code': 'GHS', 'label': 'Ghanaian Cedi (₵)'},
      {'code': 'KES', 'label': 'Kenyan Shilling (KSh)'},
      {'code': 'ZAR', 'label': 'South African Rand (R)'},
      {'code': 'EUR', 'label': 'Euro (€)'},
      {'code': 'GBP', 'label': 'British Pound (£)'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Store Profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Store Name',
                    hintText: 'e.g. Mama Chidi Supermarket',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number (optional)',
                    hintText: 'e.g. 08012345678',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: currencies.any((c) => c['code'] == selectedCurrency) ? selectedCurrency : 'NGN',
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  items: currencies.map((c) {
                    return DropdownMenuItem<String>(
                      value: c['code'],
                      child: Text(c['label']!),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedCurrency = val);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Store name cannot be empty.')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                final success = await provider.updateBusinessProfile(
                  name: newName,
                  phone: phoneController.text.trim(),
                  currency: selectedCurrency,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'Store details updated!' : 'Failed to update store details.'),
                      backgroundColor: success ? AppColors.primary : Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final business = provider.business;
    final role = provider.userRole;

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
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
                  radius: 22,
                  child: Text(
                    business?.name.isNotEmpty == true ? business!.name[0].toUpperCase() : 'K',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
                        '${role.toUpperCase()} · ${business?.currency ?? "NGN"}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                if (provider.isOwnerOrManager)
                  IconButton(
                    tooltip: 'Edit Store Details',
                    icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                    onPressed: () => _showEditStoreDialog(context),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          _sectionHeader('Operations'),
          ListTile(
            leading: const Icon(Icons.point_of_sale_outlined, color: Colors.teal),
            title: const Text('Cash Drawer'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CashDrawerScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.people_outline, color: AppColors.primary),
            title: const Text('Customers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomersScreen()));
            },
          ),
          if (provider.isOwnerOrManager) ...[
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined, color: AppColors.primary),
              title: const Text('Receive Stock'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AddPurchaseScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined, color: Colors.deepOrange),
              title: const Text('Expenses'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpensesScreen()));
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.history_outlined, color: AppColors.primary),
            title: const Text('Sales History'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesHistoryScreen()));
            },
          ),
          if (provider.isOwnerOrManager)
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined, color: Colors.indigo),
              title: const Text('Reports'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
              },
            ),

          const Divider(height: 24),

          _sectionHeader('Settings'),
          if (provider.isOwnerOrManager)
            ListTile(
              leading: const Icon(Icons.badge_outlined, color: AppColors.primary),
              title: const Text('Staff'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffScreen()));
              },
            ),
          ListTile(
            leading: const Icon(Icons.category_outlined, color: AppColors.primary),
            title: const Text('Categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showCategoriesManagerDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.scale_outlined, color: AppColors.primary),
            title: const Text('Units'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showUnitsManagerDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.sync, color: AppColors.primary),
            title: const Text('Sync Data'),
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

          const Divider(height: 24),

          // Logout
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
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
