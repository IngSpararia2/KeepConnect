import 'package:intl/intl.dart';

abstract final class AppDateTime {
  static String dateTime(DateTime? value) {
    if (value == null) return '—';
    return DateFormat('dd/MM/yyyy · h:mm a', 'es_CO').format(value.toLocal());
  }

  static String date(DateTime? value) {
    if (value == null) return '—';
    return DateFormat('dd/MM/yyyy', 'es_CO').format(value.toLocal());
  }

  static String elapsed(DateTime from, {DateTime? until}) {
    final duration = (until ?? DateTime.now()).toUtc().difference(from.toUtc());
    if (duration.isNegative) return 'ahora';
    if (duration.inDays > 0) {
      return '${duration.inDays} d ${duration.inHours.remainder(24)} h';
    }
    if (duration.inHours > 0) {
      return '${duration.inHours} h ${duration.inMinutes.remainder(60)} min';
    }
    return '${duration.inMinutes.clamp(0, 59)} min';
  }
}
