import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/models.dart';
import 'formatters.dart';

class PdfReceiptHelper {
  /// Generates a PDF byte array for a sale receipt.
  static Future<Uint8List> generateReceiptPdf({
    required Map<String, dynamic> sale,
    required Business? business,
  }) async {
    final pdf = pw.Document();

    pw.Font? regularFont;
    pw.Font? boldFont;
    try {
      regularFont = await PdfGoogleFonts.robotoRegular();
      boldFont = await PdfGoogleFonts.robotoBold();
    } catch (_) {
      regularFont = pw.Font.helvetica();
      boldFont = pw.Font.helveticaBold();
    }

    final theme = pw.ThemeData.withFont(
      base: regularFont,
      bold: boldFont,
    );

    final storeName = business?.name.isNotEmpty == true ? business!.name : 'Krum Store';
    final storePhone = business?.phone ?? '';
    final currency = business?.currency ?? 'NGN';
    final currencySymbol = currency == 'NGN' ? 'NGN ' : '$currency ';

    final ref = (sale['client_reference'] ??
            sale['reference'] ??
            sale['id'] ??
            'REC-${DateTime.now().millisecondsSinceEpoch % 100000}')
        .toString();

    final dateStr = (sale['occurred_at'] ?? sale['created_at'] ?? '').toString();
    String formattedDate = dateStr;
    if (dateStr.isNotEmpty) {
      try {
        final dt = DateTime.parse(dateStr).toLocal();
        formattedDate =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    final customerName = (sale['customer_name'] ?? 'Walk-in Customer').toString();
    final paymentMethod = (sale['payment_method'] ?? 'cash').toString().toUpperCase();

    final total = (sale['total_amount'] as num?)?.toDouble() ??
        (sale['total'] as num?)?.toDouble() ??
        0.0;
    final discount = (sale['discount'] as num?)?.toDouble() ?? 0.0;
    final amountPaid = (sale['amount_paid'] as num?)?.toDouble() ?? total;
    final balance = (total - amountPaid) > 0 ? (total - amountPaid) : 0.0;
    final isCredit = balance > 0;

    final rawItems = sale['items'] as List<dynamic>? ?? [];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        theme: theme,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Store Header
              pw.Text(
                storeName.toUpperCase(),
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              if (storePhone.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  'Tel: $storePhone',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
              pw.SizedBox(height: 4),
              pw.Text(
                'SALES RECEIPT',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.8),

              // Transaction Meta
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Receipt #: $ref', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Date: $formattedDate', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Customer: $customerName', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Payment: $paymentMethod', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(
                      'Status: ${isCredit ? "PARTIAL / CREDIT" : "PAID (FULL)"}',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.8),

              // Items Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Text('Item', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('Qty', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text('Total', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right),
                  ),
                ],
              ),
              pw.Divider(thickness: 0.5),

              // Item Rows
              ...rawItems.map((raw) {
                if (raw is! Map<String, dynamic>) return pw.SizedBox();
                final pName = (raw['product_name'] ?? raw['product'] ?? 'Item').toString();
                final uName = (raw['unit_name'] ?? raw['unit'] ?? '').toString();
                final qty = (raw['quantity'] as num?)?.toDouble() ?? 1.0;
                final uPrice = (raw['unit_price'] as num?)?.toDouble() ?? 0.0;
                final lineTotal = (raw['total'] as num?)?.toDouble() ?? (qty * uPrice);

                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            flex: 5,
                            child: pw.Text(
                              pName,
                              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              CurrencyFormatter.formatQty(qty),
                              style: const pw.TextStyle(fontSize: 8),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(
                              '$currencySymbol${CurrencyFormatter.format(lineTotal, currency: "")}',
                              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                              textAlign: pw.TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                      pw.Text(
                        '${uName.isNotEmpty ? uName : "unit"} @ $currencySymbol${CurrencyFormatter.format(uPrice, currency: "")}',
                        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                );
              }),

              pw.Divider(thickness: 0.8),

              // Summary
              if (discount > 0) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Subtotal:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('$currencySymbol${CurrencyFormatter.format(total + discount, currency: "")}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Discount:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('-$currencySymbol${CurrencyFormatter.format(discount, currency: "")}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.SizedBox(height: 2),
              ],

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL PAYABLE:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    '$currencySymbol${CurrencyFormatter.format(total, currency: "")}',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Amount Paid:', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('$currencySymbol${CurrencyFormatter.format(amountPaid, currency: "")}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),

              if (isCredit) ...[
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('BALANCE DUE:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                    pw.Text(
                      '$currencySymbol${CurrencyFormatter.format(balance, currency: "")}',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
                    ),
                  ],
                ),
              ],

              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.5),

              // Barcode / QR Code
              pw.SizedBox(height: 4),
              pw.BarcodeWidget(
                data: ref,
                barcode: pw.Barcode.code128(),
                width: 140,
                height: 28,
                drawText: false,
              ),
              pw.SizedBox(height: 2),
              pw.Text(ref, style: const pw.TextStyle(fontSize: 7)),

              pw.SizedBox(height: 8),
              pw.Text(
                'Thank you for your patronage!',
                style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                'Generated by Krum Store Manager',
                style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600),
                textAlign: pw.TextAlign.center,
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Opens the native print dialog or "Save as PDF"
  static Future<void> printOrSavePdf({
    required Map<String, dynamic> sale,
    required Business? business,
  }) async {
    final pdfBytes = await generateReceiptPdf(sale: sale, business: business);
    final ref = (sale['client_reference'] ?? sale['reference'] ?? 'receipt').toString();
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'receipt_$ref.pdf',
    );
  }

  /// Opens the native Share sheet to share the PDF file (WhatsApp, Mail, Drive, Bluetooth printer)
  static Future<void> shareReceiptPdf({
    required Map<String, dynamic> sale,
    required Business? business,
  }) async {
    final pdfBytes = await generateReceiptPdf(sale: sale, business: business);
    final ref = (sale['client_reference'] ?? sale['reference'] ?? 'receipt').toString();
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'receipt_$ref.pdf',
    );
  }

  /// Generates a clean WhatsApp/SMS formatted text receipt
  static String generateReceiptText({
    required Map<String, dynamic> sale,
    required Business? business,
  }) {
    final storeName = business?.name.isNotEmpty == true ? business!.name : 'Krum Store';
    final storePhone = business?.phone ?? '';
    final curr = business?.currency ?? 'NGN';
    final ref = (sale['client_reference'] ?? sale['reference'] ?? sale['id'] ?? 'REC').toString();

    final dateStr = (sale['occurred_at'] ?? sale['created_at'] ?? '').toString();
    String formattedDate = dateStr;
    if (dateStr.isNotEmpty) {
      try {
        final dt = DateTime.parse(dateStr).toLocal();
        formattedDate =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    final customerName = (sale['customer_name'] ?? 'Walk-in Customer').toString();
    final paymentMethod = (sale['payment_method'] ?? 'cash').toString().toUpperCase();

    final total = (sale['total_amount'] as num?)?.toDouble() ??
        (sale['total'] as num?)?.toDouble() ??
        0.0;
    final discount = (sale['discount'] as num?)?.toDouble() ?? 0.0;
    final amountPaid = (sale['amount_paid'] as num?)?.toDouble() ?? total;
    final balance = (total - amountPaid) > 0 ? (total - amountPaid) : 0.0;
    final isCredit = balance > 0;

    final rawItems = sale['items'] as List<dynamic>? ?? [];

    final buffer = StringBuffer();
    buffer.writeln('🧾 *${storeName.toUpperCase()}*');
    if (storePhone.isNotEmpty) buffer.writeln('📞 Tel: $storePhone');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📄 *SALES RECEIPT*');
    buffer.writeln('• Receipt #: $ref');
    buffer.writeln('• Date: $formattedDate');
    buffer.writeln('• Customer: $customerName');
    buffer.writeln('• Payment: $paymentMethod');
    buffer.writeln('• Status: ${isCredit ? "PARTIAL / CREDIT" : "PAID (FULL)"}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('🛒 *ITEMS:*');

    for (final raw in rawItems) {
      if (raw is Map<String, dynamic>) {
        final pName = (raw['product_name'] ?? raw['product'] ?? 'Item').toString();
        final uName = (raw['unit_name'] ?? raw['unit'] ?? '').toString();
        final qty = (raw['quantity'] as num?)?.toDouble() ?? 1.0;
        final uPrice = (raw['unit_price'] as num?)?.toDouble() ?? 0.0;
        final lineTotal = (raw['total'] as num?)?.toDouble() ?? (qty * uPrice);

        buffer.writeln(
          '• $pName (${CurrencyFormatter.formatQty(qty)} ${uName.isNotEmpty ? uName : "unit"} × $curr ${CurrencyFormatter.format(uPrice, currency: "")}) = $curr ${CurrencyFormatter.format(lineTotal, currency: "")}',
        );
      }
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    if (discount > 0) {
      buffer.writeln('• Subtotal: $curr ${CurrencyFormatter.format(total + discount, currency: "")}');
      buffer.writeln('• Discount: -$curr ${CurrencyFormatter.format(discount, currency: "")}');
    }
    buffer.writeln('💰 *TOTAL PAYABLE: $curr ${CurrencyFormatter.format(total, currency: "")}*');
    buffer.writeln('• Amount Paid: $curr ${CurrencyFormatter.format(amountPaid, currency: "")}');
    if (isCredit) {
      buffer.writeln('⚠️ *BALANCE DUE (DEBT): $curr ${CurrencyFormatter.format(balance, currency: "")}*');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('Thank you for your patronage! 🙏');
    buffer.writeln('Generated by Krum Store Manager');

    return buffer.toString();
  }
}
