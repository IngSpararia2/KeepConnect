import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/app_user.dart';
import '../data/attachment_service.dart';
import '../data/maintenance_repository.dart';
import '../domain/form_template.dart';
import '../domain/maintenance_asset.dart';
import '../domain/maintenance_category.dart';
import '../domain/maintenance_settings.dart';
import '../domain/maintenance_ticket.dart';
import '../domain/ticket_attachment.dart';
import '../domain/ticket_comment.dart';
import '../domain/ticket_event.dart';
import '../domain/ticket_feed.dart';

final maintenanceRepositoryProvider = Provider<MaintenanceRepository?>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final functions = ref.watch(functionsProvider);
  if (firestore == null || functions == null) return null;
  return MaintenanceRepository(firestore, functions);
});

final attachmentServiceProvider = Provider<AttachmentService?>((ref) {
  final storage = ref.watch(storageProvider);
  final repository = ref.watch(maintenanceRepositoryProvider);
  if (storage == null || repository == null) return null;
  return AttachmentService(storage, repository);
});

final ticketsProvider = StreamProvider<TicketFeed>((ref) {
  final repository = ref.watch(maintenanceRepositoryProvider);
  final user = ref.watch(currentUserProfileProvider).value;
  if (repository == null || user == null || !user.active) {
    return Stream.value(
      const TicketFeed(
        tickets: [],
        isFromCache: false,
        hasPendingWrites: false,
      ),
    );
  }
  return repository.watchTickets(user);
});

final ticketProvider = StreamProvider.family<MaintenanceTicket?, String>((
  ref,
  ticketId,
) {
  return ref.watch(maintenanceRepositoryProvider)?.watchTicket(ticketId) ??
      Stream.value(null);
});

final ticketCommentsProvider =
    StreamProvider.family<List<TicketComment>, String>((ref, ticketId) {
      return ref
              .watch(maintenanceRepositoryProvider)
              ?.watchComments(ticketId) ??
          Stream.value(const []);
    });

final ticketEventsProvider = StreamProvider.family<List<TicketEvent>, String>((
  ref,
  ticketId,
) {
  return ref.watch(maintenanceRepositoryProvider)?.watchEvents(ticketId) ??
      Stream.value(const []);
});

final ticketAttachmentsProvider =
    StreamProvider.family<List<TicketAttachment>, String>((ref, ticketId) {
      return ref
              .watch(maintenanceRepositoryProvider)
              ?.watchAttachments(ticketId) ??
          Stream.value(const []);
    });

final maintenanceAssetsProvider = StreamProvider<List<MaintenanceAsset>>((ref) {
  return ref.watch(maintenanceRepositoryProvider)?.watchAssets() ??
      Stream.value(const []);
});

final maintenanceCategoriesProvider = StreamProvider<List<MaintenanceCategory>>(
  (ref) {
    return ref.watch(maintenanceRepositoryProvider)?.watchCategories() ??
        Stream.value(MaintenanceCategory.fallback);
  },
);

final activeFormTemplateProvider = StreamProvider<FormTemplate?>((ref) {
  return ref.watch(maintenanceRepositoryProvider)?.watchActiveTemplate() ??
      Stream.value(null);
});

final maintenanceSettingsProvider = StreamProvider<MaintenanceSettings>((ref) {
  return ref.watch(maintenanceRepositoryProvider)?.watchSettings() ??
      Stream.value(MaintenanceSettings.defaults);
});

bool canReadTicket(AppUser user, MaintenanceTicket ticket) {
  if (user.isAdmin) return true;
  if (user.isProduction) return ticket.requesterUid == user.uid;
  return user.isMaintenance && ticket.targetDepartmentId == user.departmentId;
}
