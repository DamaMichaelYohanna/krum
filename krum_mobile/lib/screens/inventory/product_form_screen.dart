import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/store_provider.dart';
import '../scanner/barcode_scanner_screen.dart';

class ProductFormScreen extends StatefulWidget {
  final String? initialBarcode;
  final Product? product;
  const ProductFormScreen({super.key, this.initialBarcode, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _skuController = TextEditingController();
  final _brandController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _reorderLevelController = TextEditingController(text: '5');
  final _openingStockController = TextEditingController(text: '0');

  int? _selectedCategoryId;
  int? _selectedBaseUnitId;
  int? _selectedSupplierId;

  // Alternative units list to add after product creation
  final List<Map<String, dynamic>> _alternativeUnits = [];

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      final p = widget.product!;
      _nameController.text = p.name;
      _barcodeController.text = p.barcode;
      _skuController.text = p.sku;
      _brandController.text = p.brand;
      _selectedCategoryId = p.categoryId;
      _selectedBaseUnitId = p.baseUnitId;
      _selectedSupplierId = p.preferredSupplierId;
      _costPriceController.text = p.baseUnit.costPrice > 0
          ? p.baseUnit.costPrice.toStringAsFixed(2)
          : (p.averageCost > 0 ? p.averageCost.toStringAsFixed(2) : '');
      _sellingPriceController.text = p.baseUnit.sellingPrice > 0
          ? p.baseUnit.sellingPrice.toStringAsFixed(2)
          : '';
      _reorderLevelController.text = p.reorderLevel.toStringAsFixed(0);
      _openingStockController.text = p.stockBase.toStringAsFixed(0);

      for (final u in p.units.where((u) => u.conversionToBase != 1.0)) {
        _alternativeUnits.add({
          'unit_id': u.unitId,
          'unit_name': u.unitName,
          'conversion_to_base': u.conversionToBase,
          'selling_price': u.sellingPrice,
          'cost_price': u.costPrice,
        });
      }
    } else if (widget.initialBarcode != null) {
      final initCode = widget.initialBarcode!.trim();
      _barcodeController.text = initCode;
      _skuController.text = initCode;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _skuController.dispose();
    _brandController.dispose();
    _costPriceController.dispose();
    _sellingPriceController.dispose();
    _reorderLevelController.dispose();
    _openingStockController.dispose();
    super.dispose();
  }

  void _showNewCategoryDialog() {
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
            hintText: 'e.g. Beverages, Toiletries, Food Cupboard',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = catController.text.trim();
              if (name.isNotEmpty) {
                final provider = context.read<StoreProvider>();
                final newCat = await provider.createCategory(name);
                if (newCat != null && mounted) {
                  setState(() => _selectedCategoryId = newCat.id);
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

  void _showNewUnitDialog() {
    final unitNameController = TextEditingController();
    final unitSymbolController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Custom Unit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: unitNameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Unit Name',
                hintText: 'e.g. Mudu, Paint Bucket, Crate, Carton',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: unitSymbolController,
              decoration: const InputDecoration(
                labelText: 'Symbol (optional)',
                hintText: 'e.g. crt, pk',
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
                final newUnit = await provider.createCustomUnit(name, symbol: unitSymbolController.text.trim());
                if (newUnit != null && mounted) {
                  setState(() => _selectedBaseUnitId = newUnit.id);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Create Unit'),
          ),
        ],
      ),
    );
  }

  void _showAddAlternativeUnitDialog(List<Unit> units) {
    int? altUnitId;
    final conversionController = TextEditingController();
    final altSellingPriceController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Alternative Unit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: altUnitId,
                decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
                items: units.map((u) => DropdownMenuItem(value: u.id, child: Text(u.name))).toList(),
                onChanged: (val) => setDialogState(() => altUnitId = val),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: conversionController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Conversion to Base Unit',
                  hintText: 'e.g. 12 (if 1 Crate = 12 Bottles)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: altSellingPriceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Selling Price for this Unit (₦)',
                  hintText: 'e.g. 3500',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final conv = double.tryParse(conversionController.text) ?? 0.0;
                final price = double.tryParse(altSellingPriceController.text) ?? 0.0;
                if (altUnitId != null && conv > 0 && price > 0) {
                  final unitObj = units.firstWhere((u) => u.id == altUnitId);
                  setState(() {
                    _alternativeUnits.add({
                      'unit_id': altUnitId,
                      'unit_name': unitObj.name,
                      'conversion_to_base': conv,
                      'selling_price': price,
                    });
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final categories = provider.categories;
    final units = provider.units;
    final suppliers = provider.suppliers;

    if (_selectedBaseUnitId == null && units.isNotEmpty) {
      _selectedBaseUnitId = units.first.id;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product != null ? 'Edit Product' : 'Add Product'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Product Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Product Name *',
                    hintText: 'e.g. Milo 500g, Indomie Chicken, Peak Milk',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.shopping_bag_outlined),
                  ),
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Product name is required' : null,
                ),
                const SizedBox(height: 14),

                // Barcode with scan button
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _barcodeController,
                        decoration: const InputDecoration(
                          labelText: 'Barcode (Optional)',
                          hintText: 'Scan or type',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.barcode_reader),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Scan barcode with camera',
                      onPressed: () async {
                        final scanned = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BarcodeScannerScreen(
                              title: 'Scan Product Barcode',
                              hint: 'Point camera at product barcode',
                            ),
                          ),
                        );
                        if (scanned != null && scanned.trim().isNotEmpty) {
                          final code = scanned.trim();
                          setState(() {
                            _barcodeController.text = code;
                            if (_skuController.text.trim().isEmpty) {
                              _skuController.text = code;
                            }
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Item Code / SKU (Optional)
                TextFormField(
                  controller: _skuController,
                  decoration: const InputDecoration(
                    labelText: 'Item Code / SKU (Optional)',
                    hintText: 'e.g. PRD-0001 or barcode ID',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.tag),
                  ),
                ),
                const SizedBox(height: 14),

                // Category dropdown + Add Category button
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _selectedCategoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('No Category', overflow: TextOverflow.ellipsis)),
                          ...categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (val) => setState(() => _selectedCategoryId = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      icon: const Icon(Icons.add),
                      tooltip: 'New Category',
                      onPressed: _showNewCategoryDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Base Unit dropdown + Add Unit button (Section 11, 36)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedBaseUnitId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Base Unit *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.scale_outlined),
                        ),
                        items: units.map((u) => DropdownMenuItem(value: u.id, child: Text(u.name, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (val) => setState(() => _selectedBaseUnitId = val),
                        validator: (val) => val == null ? 'Please select a base unit' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      icon: const Icon(Icons.add),
                      tooltip: 'New Unit',
                      onPressed: _showNewUnitDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Preferred Supplier dropdown
                DropdownButtonFormField<int?>(
                  initialValue: _selectedSupplierId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Preferred Supplier (Optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.local_shipping_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('No Preferred Supplier', overflow: TextOverflow.ellipsis)),
                    ...suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (val) => setState(() => _selectedSupplierId = val),
                ),
                const SizedBox(height: 14),

                // Cost Price and Selling Price
                if (provider.isOwnerOrManager)
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _costPriceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Cost Price (₦)',
                            hintText: 'e.g. 1000',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _sellingPriceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Selling Price (₦) *',
                            hintText: 'e.g. 1200',
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) => (val == null || double.tryParse(val) == null || double.parse(val) <= 0)
                              ? 'Valid selling price required'
                              : null,
                        ),
                      ),
                    ],
                  )
                else
                  TextFormField(
                    controller: _sellingPriceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Selling Price (₦) *',
                      hintText: 'e.g. 1200',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) => (val == null || double.tryParse(val) == null || double.parse(val) <= 0)
                        ? 'Valid selling price required'
                        : null,
                  ),
                const SizedBox(height: 14),

                // Opening Stock & Reorder Level
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _openingStockController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Opening Stock',
                          hintText: 'e.g. 20',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _reorderLevelController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Reorder Level',
                          hintText: 'e.g. 5',
                          border: OutlineInputBorder(),
                          helperText: 'Alerts when stock is low',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Alternative Units Section (Section 12, 13)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Alternative Units & Prices',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: units.isEmpty ? null : () => _showAddAlternativeUnitDialog(units),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Unit'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                if (_alternativeUnits.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: const Text(
                      'Sell in packs, cartons, or crates? Tap "Add Unit" to set multi-unit prices.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  )
                else
                  Column(
                    children: _alternativeUnits.asMap().entries.map((entry) {
                      final i = entry.key;
                      final u = entry.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          title: Text('${u['unit_name']} (1 = ${u['conversion_to_base']} base)'),
                          subtitle: Text('Selling Price: ₦${u['selling_price']}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => setState(() => _alternativeUnits.removeAt(i)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 28),

                FilledButton(
                  onPressed: provider.isLoading
                      ? null
                      : () async {
                          if (!_formKey.currentState!.validate()) return;

                          final cost = double.tryParse(_costPriceController.text) ?? 0.0;
                          final selling = double.parse(_sellingPriceController.text);
                          final opening = double.tryParse(_openingStockController.text) ?? 0.0;
                          final reorder = double.tryParse(_reorderLevelController.text) ?? 0.0;

                          bool success;
                          if (widget.product != null) {
                            final baseUnitObj = units.firstWhere(
                              (u) => u.id == _selectedBaseUnitId!,
                              orElse: () => Unit(id: _selectedBaseUnitId!, name: 'Piece'),
                            );
                            String? catName;
                            if (_selectedCategoryId != null) {
                              final catMatch = categories.where((c) => c.id == _selectedCategoryId);
                              if (catMatch.isNotEmpty) catName = catMatch.first.name;
                            }

                            int uIdCounter = DateTime.now().millisecondsSinceEpoch ~/ 1000;
                            final List<ProductUnit> updatedUnits = [
                              ProductUnit(
                                id: widget.product!.baseUnit.id != 0 ? widget.product!.baseUnit.id : uIdCounter++,
                                unitId: _selectedBaseUnitId!,
                                unitName: baseUnitObj.name,
                                conversionToBase: 1.0,
                                costPrice: cost,
                                sellingPrice: selling,
                                minimumPrice: cost,
                              ),
                            ];

                            for (final alt in _alternativeUnits) {
                              final altUnitId = alt['unit_id'] as int;
                              final altName = alt['unit_name'] as String? ??
                                  units.firstWhere((u) => u.id == altUnitId, orElse: () => Unit(id: altUnitId, name: 'Unit')).name;
                              final conv = (alt['conversion_to_base'] as num).toDouble();
                              final sPrice = (alt['selling_price'] as num).toDouble();
                              final cPrice = (alt['cost_price'] as num?)?.toDouble() ?? (cost * conv);

                              updatedUnits.add(ProductUnit(
                                id: uIdCounter++,
                                unitId: altUnitId,
                                unitName: altName,
                                conversionToBase: conv,
                                costPrice: cPrice,
                                sellingPrice: sPrice,
                                minimumPrice: cPrice,
                              ));
                            }

                            String? supName;
                            if (_selectedSupplierId != null) {
                              final match = suppliers.where((s) => s.id == _selectedSupplierId);
                              if (match.isNotEmpty) supName = match.first.name;
                            }

                            final updatedProd = widget.product!.copyWith(
                              name: _nameController.text.trim(),
                              barcode: _barcodeController.text.trim(),
                              sku: _skuController.text.trim(),
                              categoryId: _selectedCategoryId,
                              categoryName: catName,
                              preferredSupplierId: _selectedSupplierId,
                              preferredSupplierName: supName,
                              baseUnitId: _selectedBaseUnitId!,
                              baseUnitName: baseUnitObj.name,
                              brand: _brandController.text.trim(),
                              reorderLevel: reorder,
                              stockBase: opening,
                              averageCost: cost,
                              units: updatedUnits,
                            );

                            success = await provider.updateProduct(updatedProd);
                          } else {
                            success = await provider.createProduct(
                              name: _nameController.text.trim(),
                              barcode: _barcodeController.text.trim(),
                              sku: _skuController.text.trim(),
                              categoryId: _selectedCategoryId,
                              preferredSupplierId: _selectedSupplierId,
                              baseUnitId: _selectedBaseUnitId!,
                              brand: _brandController.text.trim(),
                              costPrice: cost,
                              sellingPrice: selling,
                              openingStock: opening,
                              reorderLevel: reorder,
                              alternativeUnits: _alternativeUnits,
                            );
                          }

                          if (success && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(widget.product != null ? 'Product updated successfully!' : 'Product created successfully!'),
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
                  child: provider.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(widget.product != null ? 'Update Product' : 'Save Product', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
