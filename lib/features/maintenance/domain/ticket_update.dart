import 'ticket_enums.dart';

class TicketUpdate {
  const TicketUpdate({
    required this.id,
    required this.ticketId,
    required this.actor,
    required this.type,
    required this.content,
    required this.createdAt,
  });
  final String id;
  final String ticketId;
  final AppRole actor;
  final TicketUpdateType type;
  final String content;
  final DateTime createdAt;
}
