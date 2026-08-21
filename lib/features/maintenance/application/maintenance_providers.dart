import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/notifications/app_notification.dart';
import '../domain/maintenance_ticket.dart';
import '../domain/ticket_event.dart';
import '../domain/ticket_update.dart';

final ticketsProvider = StreamProvider<List<MaintenanceTicket>>(
  (ref) => ref.watch(maintenanceRepositoryProvider).watchTickets(),
);
final ticketProvider = StreamProvider.family<MaintenanceTicket?, String>(
  (ref, id) => ref.watch(maintenanceRepositoryProvider).watchTicket(id),
);
final ticketUpdatesProvider = StreamProvider.family<List<TicketUpdate>, String>(
  (ref, id) => ref.watch(maintenanceRepositoryProvider).watchUpdates(id),
);
final ticketEventsProvider = StreamProvider.family<List<TicketEvent>, String>(
  (ref, id) => ref.watch(maintenanceRepositoryProvider).watchEvents(id),
);
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final role = ref.watch(
    sessionProvider.select((state) => state.effectiveRole),
  );
  return ref.watch(maintenanceRepositoryProvider).watchNotifications(role);
});
final unreadNotificationsProvider = StreamProvider<int>((ref) {
  final role = ref.watch(
    sessionProvider.select((state) => state.effectiveRole),
  );
  return ref.watch(maintenanceRepositoryProvider).watchUnreadCount(role);
});
