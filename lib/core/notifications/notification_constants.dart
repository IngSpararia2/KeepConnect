import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Stable Android notification resources shared by FCM and local messages.
///
/// Channel identifiers must never be repurposed after release: Android keeps a
/// channel's sound and vibration preferences once it has been created.
abstract final class NotificationConstants {
  static const String normalChannelId = 'gestion_interna_normal_v1';
  static const String urgentChannelId = 'gestion_interna_urgent_v1';
  static const String notificationIcon = 'ic_stat_maintenance';
  static const String installationIdPreference =
      'notifications.installation_id.v1';
  static const String installationCreatedAtPreference =
      'notifications.installation_created_at.v1';

  static const AndroidNotificationChannel normalChannel =
      AndroidNotificationChannel(
        normalChannelId,
        'Actualizaciones de solicitudes',
        description: 'Nuevas solicitudes y cambios normales de seguimiento.',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

  static const AndroidNotificationChannel
  urgentChannel = AndroidNotificationChannel(
    urgentChannelId,
    'Solicitudes críticas y urgentes',
    description:
        'Emergencias, producción detenida y escalamientos de alta prioridad.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );
}
