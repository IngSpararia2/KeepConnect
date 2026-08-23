import 'ticket_enums.dart';

class TicketEvent {
  const TicketEvent({
    required this.id,
    required this.ticketId,
    required this.type,
    required this.actor,
    required this.message,
    required this.createdAt,
    this.actorUserId,
  });
  final String id;
  final String ticketId;
  final TicketEventType type;
  final AppRole actor;
  final String message;
  final DateTime createdAt;
  final String? actorUserId;
}
