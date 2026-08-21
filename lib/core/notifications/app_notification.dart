import '../../features/maintenance/domain/ticket_enums.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.ticketId,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.recipient,
    required this.read,
    required this.eventType,
  });
  final String id;
  final String ticketId;
  final String title;
  final String message;
  final DateTime createdAt;
  final AppRole recipient;
  final bool read;
  final String eventType;
}
