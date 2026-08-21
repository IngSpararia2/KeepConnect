import '../../../core/notifications/app_notification.dart';
import '../domain/create_ticket_input.dart';
import '../domain/maintenance_ticket.dart';
import '../domain/ticket_enums.dart';
import '../domain/ticket_event.dart';
import '../domain/ticket_question.dart';
import '../domain/ticket_update.dart';

abstract interface class MaintenanceRepository {
  Stream<List<MaintenanceTicket>> watchTickets();
  Stream<MaintenanceTicket?> watchTicket(String ticketId);
  Stream<List<TicketUpdate>> watchUpdates(String ticketId);
  Stream<List<TicketEvent>> watchEvents(String ticketId);
  Stream<List<AppNotification>> watchNotifications(AppRole recipient);
  Stream<int> watchUnreadCount(AppRole recipient);

  Future<CreatedTicketResult> createTicket(CreateTicketInput input);
  Future<void> changeStatus(
    String ticketId,
    TicketStatus status,
    AppRole actor,
  );
  Future<void> saveAnswers(
    String ticketId,
    Map<String, List<String>> answers,
    AppRole actor,
  );
  Future<void> addQuestion(
    String ticketId,
    TicketQuestion question,
    AppRole actor,
  );
  Future<void> addUpdate(
    String ticketId,
    TicketUpdateType type,
    String content,
    AppRole actor,
  );
  Future<void> markNotificationRead(String notificationId);
  Future<void> close();
}
