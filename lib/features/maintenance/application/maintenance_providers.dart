import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_providers.dart';
import '../../../core/notifications/app_notification.dart';
import '../../organization/domain/organization_models.dart';
import '../domain/maintenance_ticket.dart';
import '../domain/ticket_event.dart';
import '../domain/ticket_update.dart';

final _maintenanceContextProvider = Provider<AccessContext?>((ref) {
  final session = ref.watch(sessionProvider);
  return session.hasSelectedContext ? session.accessContext : null;
});

final ticketsProvider = StreamProvider<List<MaintenanceTicket>>((ref) {
  final scope = ref.watch(_maintenanceContextProvider);
  if (scope == null) return Stream.value(const <MaintenanceTicket>[]);
  return ref.watch(maintenanceRepositoryProvider).watchTickets();
});
final ticketProvider = StreamProvider.family<MaintenanceTicket?, String>((
  ref,
  id,
) {
  final scope = ref.watch(_maintenanceContextProvider);
  if (scope == null) return Stream.value(null);
  return ref.watch(maintenanceRepositoryProvider).watchTicket(id);
});
final ticketUpdatesProvider = StreamProvider.family<List<TicketUpdate>, String>(
  (ref, id) {
    final scope = ref.watch(_maintenanceContextProvider);
    if (scope == null) return Stream.value(const <TicketUpdate>[]);
    return ref.watch(maintenanceRepositoryProvider).watchUpdates(id);
  },
);
final ticketEventsProvider = StreamProvider.family<List<TicketEvent>, String>((
  ref,
  id,
) {
  final scope = ref.watch(_maintenanceContextProvider);
  if (scope == null) return Stream.value(const <TicketEvent>[]);
  return ref.watch(maintenanceRepositoryProvider).watchEvents(id);
});
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final scope = ref.watch(_maintenanceContextProvider);
  if (scope == null) return Stream.value(const <AppNotification>[]);
  return ref
      .watch(maintenanceRepositoryProvider)
      .watchNotifications(scope.operationalRole);
});
final unreadNotificationsProvider = StreamProvider<int>((ref) {
  final scope = ref.watch(_maintenanceContextProvider);
  if (scope == null) return Stream.value(0);
  return ref
      .watch(maintenanceRepositoryProvider)
      .watchUnreadCount(scope.operationalRole);
});
