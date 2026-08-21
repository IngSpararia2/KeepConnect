import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/notification_service.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw StateError('notificationServiceProvider debe sobrescribirse.'),
);
