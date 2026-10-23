import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final _numberFormat = NumberFormat('#,##0.00', 'en_US');
  static final _wholeFormat = NumberFormat('#,##0', 'en_US');

  static String format(double amount, {String currency = 'NGN', bool showDecimals = false}) {
    final symbol = currency == 'NGN' ? '₦' : '$currency ';
    final formatted = showDecimals ? _numberFormat.format(amount) : _wholeFormat.format(amount);
    return '$symbol$formatted';
  }

  static String formatQty(double qty) {
    if (qty == qty.roundToDouble()) {
      return qty.toInt().toString();
    }
    return qty.toStringAsFixed(2);
  }
}

class DateFormatter {
  static String format(String? rawDate, {bool includeTime = false}) {
    if (rawDate == null || rawDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(rawDate);
      final local = dt.isUtc ? dt.toLocal() : dt;
      final now = DateTime.now();
      final isToday = local.year == now.year && local.month == now.month && local.day == now.day;
      final yesterday = now.subtract(const Duration(days: 1));
      final isYesterday = local.year == yesterday.year && local.month == yesterday.month && local.day == yesterday.day;

      final dateStr = isToday
          ? 'Today'
          : isYesterday
              ? 'Yesterday'
              : DateFormat('d MMM yyyy').format(local);

      if (includeTime && rawDate.contains('T')) {
        return '$dateStr, ${DateFormat('h:mm a').format(local)}';
      }
      return dateStr;
    } catch (_) {
      return rawDate;
    }
  }

  static String formatRange(DateTime start, DateTime end) {
    if (start.year == end.year && start.month == end.month && start.day == end.day) {
      return DateFormat('d MMM yyyy').format(start);
    }
    if (start.year == end.year) {
      return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(end)}';
    }
    return '${DateFormat('d MMM yyyy').format(start)} – ${DateFormat('d MMM yyyy').format(end)}';
  }
}
