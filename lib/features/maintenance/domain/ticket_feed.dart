import 'maintenance_ticket.dart';

/// A bounded ticket page together with Firestore synchronization metadata.
class TicketFeed {
  const TicketFeed({
    required this.tickets,
    required this.isFromCache,
    required this.hasPendingWrites,
  });

  final List<MaintenanceTicket> tickets;
  final bool isFromCache;
  final bool hasPendingWrites;
}
