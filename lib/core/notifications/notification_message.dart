import 'package:firebase_messaging/firebase_messaging.dart';

/// UI-agnostic representation of an incoming notification.
final class NotificationMessage {
  const NotificationMessage({
    required this.messageId,
    required this.ticketId,
    required this.title,
    required this.body,
    required this.isUrgent,
  });

  factory NotificationMessage.fromRemoteMessage(RemoteMessage message) {
    final data = message.data;
    final ticketId =
        _nonEmpty(data['ticketId']) ?? _nonEmpty(data['ticket_id']);
    final priority =
        (_nonEmpty(data['priority']) ??
                _nonEmpty(data['urgency']) ??
                _nonEmpty(data['channel']) ??
                _nonEmpty(data['channelId']) ??
                '')
            .toLowerCase();
    final urgentFlag = data['urgent'];
    final normalizedUrgentFlag = urgentFlag?.toString().toLowerCase();
    final hasExplicitUrgentFlag = data.containsKey('urgent');
    final isUrgent = hasExplicitUrgentFlag
        ? urgentFlag == true ||
              urgentFlag == 1 ||
              normalizedUrgentFlag == 'true' ||
              normalizedUrgentFlag == '1'
        : const <String>{
            'critical',
            'critica',
            'crítica',
            'urgent',
            'urgente',
            'emergency',
            'high',
          }.contains(priority);

    return NotificationMessage(
      messageId: message.messageId,
      ticketId: ticketId,
      title:
          _nonEmpty(message.notification?.title) ??
          _nonEmpty(data['title']) ??
          _nonEmpty(data['notificationTitle']) ??
          'Gestión Interna',
      body:
          _nonEmpty(message.notification?.body) ??
          _nonEmpty(data['body']) ??
          _nonEmpty(data['notificationBody']) ??
          (ticketId == null
              ? 'Hay una nueva actualización.'
              : 'Hay una actualización en una solicitud.'),
      isUrgent: isUrgent,
    );
  }

  final String? messageId;
  final String? ticketId;
  final String title;
  final String body;
  final bool isUrgent;

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
