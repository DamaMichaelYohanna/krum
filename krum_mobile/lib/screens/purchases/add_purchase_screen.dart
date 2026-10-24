import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/store_provider.dart';
import '../../utils/formatters.dart';

class AddPurchaseScreen extends StatefulWidget {
  const AddPurchaseScreen({super.key});

  @override
  State<AddPurchaseScreen> createState() => _AddPurchaseScreenState();
}

class _AddPurchaseScreenState extends State<AddPurchaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _unitCostController = TextEditingController();
  final _amountPaidController = TextEditingController();
  final _refController = TextEditingController();

  int? _selectedSupplierId;
  Product? _selectedProduct;
  ProductUnit? _selectedUnit;

  @override
  void dispose() {
    _qtyController.dispose();
    _unitCostController.dispose();
    _amountPaidController.dispose();
    _refController.dispose();
    super.dispose();
  }

  void _showNewSupplierDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Supplier Name', hintText: 'e.g. Alaba Wholesale'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                final provider = context.read<StoreProvider>();
                final sup = await provider.createSupplier(name, phone: phoneController.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                if (sup != null) {
                  setState(() => _selectedSupplierId = sup.id);
                }
              }
            },
            child: const Text('Save Supplier'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final suppliers = provider.suppliers;
    final products = provider.products.where((p) => p.active).toList();
    final currency = provider.business?.currency ?? 'NGN';

    final qty = double.tryParse(_qtyController.text) ?? 0.0;
    final cost = double.tryParse(_unitCostController.text) ?? 0.0;
    final totalCost = qty * cost;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Stock (Purchase)'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Supplier dropdown + Add Supplier
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _selectedSupplierId,
                        decoration: const InputDecoration(
                          labelText: 'Supplier (Optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.local_shipping_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('Direct / General Supplier')),
                          ...suppliers.map((s) => DropdownMenuItem<int?>(value: s.id, child: Text(s.name))),
                        ],
                        onChanged: (val) => setState(() => _selectedSupplierId = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      icon: const Icon(Icons.add),
                      tooltip: 'New Supplier',
                      onPressed: _showNewSupplierDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Product Selection
                DropdownButtonFormField<Product>(
                  initialValue: _selectedProduct,
                  decoration: const InputDecoration(
                    labelText: 'Product *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  items: products.map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
                  onChanged: (prod) {
                    setState(() {
                      _selectedProduct = prod;
                      _selectedUnit = prod?.baseUnit;
                      if (prod != null && prod.averageCost > 0) {
                        _unitCostController.text = prod.averageCost.toStringAsFixed(0);
                      }
                    });
                  },
                  validator: (val) => val == null ? 'Please select a product' : null,
                ),
                const SizedBox(height: 16),

                // Unit Selection (e.g. Carton vs Piece)
                if (_selectedProduct != null) ...[
                  DropdownButtonFormField<ProductUnit>(
                    initialValue: _selectedUnit,
                    decoration: const InputDecoration(
                      labelText: 'Purchase Unit *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.scale_outlined),
                    ),
                    items: _selectedProduct!.units.map((u) {
                      return DropdownMenuItem(
                        value: u,
                        child: Text('${u.unitName} (Contains ${CurrencyFormatter.formatQty(u.conversionToBase)} ${_selectedProduct!.baseUnitName})'),
                      );
                    }).toList(),
                    onChanged: (u) => setState(() => _selectedUnit = u),
                  ),
                  const SizedBox(height: 16),
                ],

                // Quantity & Unit Cost
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _qtyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Quantity *',
                          hintText: 'e.g. 10',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) {
                          setState(() {
                            _amountPaidController.text = (qty * cost).toStringAsFixed(0);
                          });
                        },
                        validator: (val) => (val == null || double.tryParse(val) == null || double.parse(val) <= 0)
                            ? 'Enter valid quantity'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _unitCostController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Unit Cost (₦) *',
                          hintText: 'e.g. 8500',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) {
                          setState(() {
                            _amountPaidController.text = (qty * cost).toStringAsFixed(0);
                          });
                        },
                        validator: (val) => (val == null || double.tryParse(val) == null || double.parse(val) < 0)
                            ? 'Enter valid cost'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Total Cost Banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Purchase Cost:', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        CurrencyFormatter.format(totalCost, currency: currency),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Amount Paid Input
                TextFormField(
                  controller: _amountPaidController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount Paid to Supplier (₦)',
                    hintText: 'Full or partial amount',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _refController,
                  decoration: const InputDecoration(
                    labelText: 'Invoice / Receipt # (Optional)',
                    hintText: 'e.g. INV-2026-09',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),

                FilledButton(
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) return;
                    final unit = _selectedUnit ?? _selectedProduct!.baseUnit;
                    final quantity = double.parse(_qtyController.text);
                    final unitCost = double.parse(_unitCostController.text);
                    final paid = double.tryParse(_amountPaidController.text) ?? totalCost;

                    await provider.receivePurchase(
                      supplierId: _selectedSupplierId,
                      productId: _selectedProduct!.id,
                      productUnitId: unit.id,
                      quantity: quantity,
                      unitCost: unitCost,
                      amountPaid: paid,
                      reference: _refController.text.trim(),
                    );

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Stock received successfully and inventory increased!'),
                          backgroundColor: AppColors.primary,
                        ),
                      );
                      Navigator.pop(context);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Record Stock Receipt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
