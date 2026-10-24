import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../providers/store_provider.dart';
import '../../utils/formatters.dart';

class StockAdjustmentDialog extends StatefulWidget {
  final Product product;
  const StockAdjustmentDialog({super.key, required this.product});

  @override
  State<StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<StockAdjustmentDialog> {
  final _qtyController = TextEditingController();
  final _referenceController = TextEditingController();
  String _reason = 'physical_count';
  bool _isAddition = false;

  @override
  void dispose() {
    _qtyController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final currentStock = widget.product.stockBase;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.tune, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('Adjust Stock: ${widget.product.name}')),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current stock: ${CurrencyFormatter.formatQty(currentStock)} ${widget.product.baseUnitName}',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
              ),
              const SizedBox(height: 16),

              // Operation Type: Decrease vs Increase
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Reduce (-)')),
                  ButtonSegment(value: true, label: Text('Add (+)')),
                ],
                selected: {_isAddition},
                onSelectionChanged: (set) => setState(() => _isAddition = set.first),
              ),

              const SizedBox(height: 14),

              TextField(
                controller: _qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantity (${widget.product.baseUnitName})',
                  hintText: 'e.g. 5',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(_isAddition ? Icons.add : Icons.remove),
                ),
              ),

              const SizedBox(height: 14),

              // Reason Selector (Section 26: Damaged, Expired, Missing, Physical count adjustment, Opening stock, Other)
              DropdownButtonFormField<String>(
                initialValue: _reason,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.help_outline),
                ),
                items: const [
                  DropdownMenuItem(value: 'physical_count', child: Text('Physical count adjustment', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'damaged', child: Text('Damaged goods', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'expired', child: Text('Expired goods', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'missing', child: Text('Missing / Shrinkage', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'opening', child: Text('Opening stock correction', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'other', child: Text('Other', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _reason = val);
                },
              ),

              const SizedBox(height: 14),

              TextField(
                controller: _referenceController,
                decoration: const InputDecoration(
                  labelText: 'Notes / Reference (Optional)',
                  hintText: 'e.g. Stocktaking count',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final qty = double.tryParse(_qtyController.text.trim()) ?? 0.0;
            if (qty <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a quantity greater than 0')),
              );
              return;
            }

            final delta = _isAddition ? qty : -qty;

            if (currentStock + delta < 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cannot reduce stock below zero.')),
              );
              return;
            }

            Navigator.pop(context);
            await provider.adjustStock(
              productId: widget.product.id,
              quantityDelta: delta,
              reason: _reason,
              reference: _referenceController.text.trim(),
            );

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Stock adjustment applied and saved!'),
                  backgroundColor: AppColors.primary,
                ),
              );
            }
          },
          child: const Text('Save Adjustment'),
        ),
      ],
    );
  }
}
