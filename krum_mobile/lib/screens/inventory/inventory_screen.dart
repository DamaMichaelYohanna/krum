import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/store_provider.dart';
import '../../utils/formatters.dart';
import 'product_form_screen.dart';
import 'stock_adjustment_dialog.dart';
import '../scanner/barcode_scanner_screen.dart';
import '../../widgets/app_search_bar.dart';
import 'low_stock_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  int? _selectedCategoryFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(
          title: 'Scan Inventory Barcode',
          hint: 'Point camera at product barcode',
        ),
      ),
    );
    if (scanned != null && scanned.trim().isNotEmpty && mounted) {
      final code = scanned.trim();
      final provider = context.read<StoreProvider>();
      final product = await provider.findProductOrLookup(code);
      if (!mounted) return;

      if (product != null) {
        _showProductDetails(context, product);
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Product Not Found'),
            content: Text('Item with code "$code" is not registered in your inventory yet. Would you like to create it?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProductFormScreen(initialBarcode: code),
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Create Product'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showAddCategoryDialog(BuildContext context) {
    final catController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Category'),
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
                final newCat = await context.read<StoreProvider>().createCategory(name);
                if (newCat != null && mounted) {
                  setState(() => _selectedCategoryFilter = newCat.id);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showProductDetails(BuildContext context, Product product) {
    final provider = context.read<StoreProvider>();
    final isOwnerOrManager = provider.isOwnerOrManager;
    final currency = provider.business?.currency ?? 'NGN';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                _stockBadge(product),
                if (isOwnerOrManager) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Edit Product',
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    tooltip: 'Delete Product',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Delete Product'),
                          content: Text('Are you sure you want to delete "${product.name}"?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () => Navigator.pop(dCtx, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && context.mounted) {
                        Navigator.pop(ctx);
                        await context.read<StoreProvider>().deleteProduct(product.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Deleted "${product.name}"')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${product.categoryName ?? "General"} · Barcode: ${product.barcode.isEmpty ? "None" : product.barcode}',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const Divider(height: 24),

            // Stock breakdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _detailStat('Current Stock', '${CurrencyFormatter.formatQty(product.stockBase)} ${product.baseUnitName}'),
                _detailStat('Reorder Level', '${CurrencyFormatter.formatQty(product.reorderLevel)} ${product.baseUnitName}'),
                if (isOwnerOrManager)
                  _detailStat('Avg Cost', CurrencyFormatter.format(product.averageCost, currency: currency))
                else
                  _detailStat('Base Price', CurrencyFormatter.format(product.baseUnit.sellingPrice, currency: currency)),
              ],
            ),
            const SizedBox(height: 18),

            // Configured Units & Pricing (Section 13)
            const Text(
              'Units & Pricing',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: product.units.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final u = product.units[i];
                  final unitCost = u.costPrice > 0 ? u.costPrice : (product.averageCost * u.conversionToBase);
                  return ListTile(
                    dense: true,
                    title: Text(u.unitName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      isOwnerOrManager
                          ? '1 ${u.unitName} = ${CurrencyFormatter.formatQty(u.conversionToBase)} ${product.baseUnitName}\nCost: ${CurrencyFormatter.format(unitCost, currency: currency)}'
                          : '1 ${u.unitName} = ${CurrencyFormatter.formatQty(u.conversionToBase)} ${product.baseUnitName}',
                    ),
                    isThreeLine: isOwnerOrManager,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          CurrencyFormatter.format(u.sellingPrice, currency: currency),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const Text(
                          'Selling Price',
                          style: TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                if (isOwnerOrManager) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        showDialog(
                          context: context,
                          builder: (_) => StockAdjustmentDialog(product: product),
                        );
                      },
                      icon: const Icon(Icons.tune),
                      label: const Text('Adjust Stock'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      context.read<StoreProvider>().addToCart(product);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added ${product.name} to Cart')),
                      );
                    },
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Add to Cart'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _stockBadge(Product p) {
    Color bg;
    Color fg;
    String text;

    if (p.isOutOfStock) {
      bg = Colors.red.shade50;
      fg = Colors.red.shade700;
      text = 'Out of stock';
    } else if (p.isLowStock) {
      bg = Colors.amber.shade50;
      fg = Colors.amber.shade900;
      text = 'Low stock';
    } else {
      bg = Colors.green.shade50;
      fg = AppColors.primary;
      text = 'In stock';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final currency = provider.business?.currency ?? 'NGN';
    final categories = provider.categories;

    final cleanQuery = _searchQuery.toLowerCase();
    final noZerosQuery = cleanQuery.replaceFirst(RegExp(r'^0+'), '');

    final filteredProducts = provider.products.where((p) {
      if (!p.active) return false;
      if (_selectedCategoryFilter != null && p.categoryId != _selectedCategoryFilter) return false;
      if (_searchQuery.isEmpty) return true;
      final pBarcode = p.barcode.toLowerCase();
      final pSku = p.sku.toLowerCase();
      final pName = p.name.toLowerCase();
      final pId = p.id.toString();

      if (pName.contains(cleanQuery) ||
          pBarcode.contains(cleanQuery) ||
          pSku.contains(cleanQuery) ||
          pId == cleanQuery) {
        return true;
      }

      if (noZerosQuery.isNotEmpty) {
        final bNoZero = pBarcode.replaceFirst(RegExp(r'^0+'), '');
        final sNoZero = pSku.replaceFirst(RegExp(r'^0+'), '');
        if (bNoZero.contains(noZerosQuery) || sNoZero.contains(noZerosQuery)) {
          return true;
        }
      }

      return false;
    }).toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Search & Filter Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: AppSearchBar(
                      controller: _searchController,
                      hintText: 'Search inventory by name, SKU, or barcode...',
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Barcode Scanner Action Button
                  Tooltip(
                    message: 'Scan barcode',
                    child: Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _scanBarcode,
                          child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Category Pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  _buildCategoryPill(
                    label: 'All Products',
                    isSelected: _selectedCategoryFilter == null,
                    onTap: () => setState(() => _selectedCategoryFilter = null),
                  ),
                  const SizedBox(width: 8),
                  ...categories.map((c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildCategoryPill(
                          label: c.name,
                          isSelected: _selectedCategoryFilter == c.id,
                          onTap: () => setState(() => _selectedCategoryFilter = c.id),
                        ),
                      )),
                  InkWell(
                    onTap: () => _showAddCategoryDialog(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.primaryBorder),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 16, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text(
                            'New Category',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Low Stock Alert Banner (1-Tap jump to LowStockScreen)
            if (provider.lowStockProducts.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${provider.lowStockProducts.length} product(s) at or below reorder level',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LowStockScreen()),
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              'Restock Hub',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                            ),
                            Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFFD97706)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

          // Product List
          Expanded(
            child: filteredProducts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          'No products found',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Tap + to add your first product.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = filteredProducts[index];
                      final basePrice = product.baseUnit.sellingPrice;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          title: Text(
                            product.name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          subtitle: Text(
                            'Sell: ${CurrencyFormatter.format(basePrice, currency: currency)} · Cost: ${CurrencyFormatter.format(product.averageCost, currency: currency)} · Stock: ${CurrencyFormatter.formatQty(product.stockBase)} ${product.baseUnitName}',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _stockBadge(product),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right, color: Colors.black38),
                            ],
                          ),
                          onTap: () => _showProductDetails(context, product),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
      floatingActionButton: context.watch<StoreProvider>().isOwnerOrManager
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProductFormScreen()),
                );
              },
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add Product', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  Widget _buildCategoryPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1.2,
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
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
