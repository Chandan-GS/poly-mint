import 'package:intl/intl.dart';

/// Small formatting helpers shared across the UI so numbers/dates read
/// consistently everywhere.
abstract class Formatters {
  static final NumberFormat _credits = NumberFormat('#,##0.00');
  static final NumberFormat _weight = NumberFormat('#,##0.0');
  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _dateTime = DateFormat('d MMM, h:mm a');

  static String credits(double v) => _credits.format(v);
  static String weight(double v) => '${_weight.format(v)} kg';
  static String co2(double v) => '${_weight.format(v)} kg';
  static String percent(double fraction) =>
      '${(fraction * 100).toStringAsFixed(1)}%';
  static String date(DateTime d) => _date.format(d);
  static String dateTime(DateTime d) => _dateTime.format(d);

  static String compact(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return _weight.format(v);
  }

  static String relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _date.format(d);
  }
}
