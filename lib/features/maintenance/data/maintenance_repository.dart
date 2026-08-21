import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../../../config/app_config.dart';
import '../../../core/errors/app_exception.dart';
import '../../auth/domain/app_user.dart';
import '../domain/create_ticket_input.dart';
import '../domain/form_template.dart';
import '../domain/maintenance_asset.dart';
import '../domain/maintenance_category.dart';
import '../domain/maintenance_settings.dart';
import '../domain/maintenance_ticket.dart';
import '../domain/ticket_attachment.dart';
import '../domain/ticket_comment.dart';
import '../domain/ticket_enums.dart';
import '../domain/ticket_event.dart';
import '../domain/ticket_feed.dart';

class MaintenanceRepository {
  MaintenanceRepository(this._firestore, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final Uuid _uuid = const Uuid();

  Stream<TicketFeed> watchTickets(AppUser user) {
    Query<Map<String, dynamic>> query = _firestore.collection('tickets');
    query = switch (user.role) {
      UserRole.admin => query,
      UserRole.production => query.where('requesterUid', isEqualTo: user.uid),
      UserRole.maintenance => query.where(
        'targetDepartmentId',
        isEqualTo: user.departmentId,
      ),
    };
    return query
        .orderBy('updatedAt', descending: true)
        .limit(AppConfig.ticketPageSize)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => TicketFeed(
            tickets: snapshot.docs
                .map(MaintenanceTicket.fromFirestore)
                .toList(growable: false),
            isFromCache: snapshot.metadata.isFromCache,
            hasPendingWrites: snapshot.metadata.hasPendingWrites,
          ),
        );
  }

  Stream<MaintenanceTicket?> watchTicket(String ticketId) {
    return _firestore
        .collection('tickets')
        .doc(ticketId)
        .snapshots()
        .map(
          (document) => document.exists
              ? MaintenanceTicket.fromFirestore(document)
              : null,
        );
  }

  Stream<List<TicketComment>> watchComments(String ticketId) {
    return _firestore
        .collection('tickets')
        .doc(ticketId)
        .collection('comments')
        .orderBy('createdAt')
        .limitToLast(200)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(TicketComment.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<List<TicketEvent>> watchEvents(String ticketId) {
    return _firestore
        .collection('tickets')
        .doc(ticketId)
        .collection('events')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(TicketEvent.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<List<TicketAttachment>> watchAttachments(String ticketId) {
    return _firestore
        .collection('tickets')
        .doc(ticketId)
        .collection('attachments')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(TicketAttachment.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<List<MaintenanceAsset>> watchAssets() {
    return _firestore
        .collection('assets')
        .where('active', isEqualTo: true)
        .orderBy('name')
        .limit(200)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(MaintenanceAsset.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<List<MaintenanceCategory>> watchCategories() {
    return _firestore
        .collection('ticket_categories')
        .where('moduleId', isEqualTo: AppConfig.maintenanceModuleId)
        .where('active', isEqualTo: true)
        .orderBy('sortOrder')
        .limit(100)
        .snapshots()
        .map((snapshot) {
          final categories = snapshot.docs
              .map(MaintenanceCategory.fromFirestore)
              .toList(growable: false);
          return categories.isEmpty ? MaintenanceCategory.fallback : categories;
        });
  }

  Stream<FormTemplate?> watchActiveTemplate() {
    return _firestore
        .collection('form_templates')
        .where('moduleId', isEqualTo: AppConfig.maintenanceModuleId)
        .where('active', isEqualTo: true)
        .orderBy('version', descending: true)
        .limit(1)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.isEmpty
              ? null
              : FormTemplate.fromFirestore(snapshot.docs.first),
        );
  }

  Stream<MaintenanceSettings> watchSettings() {
    return _firestore
        .collection('settings')
        .doc('maintenance')
        .snapshots()
        .map(
          (snapshot) => snapshot.exists
              ? MaintenanceSettings.fromMap(snapshot.data()!)
              : MaintenanceSettings.defaults,
        );
  }

  Future<CreatedTicketResult> createTicket(CreateTicketInput input) async {
    final data = await _call(
      'createTicket',
      input.toCallableData(requestId: _uuid.v4()),
    );
    final ticketId = data['ticketId'] as String?;
    if (ticketId == null || ticketId.isEmpty) {
      throw const AppException('El servidor no devolvió el ticket creado.');
    }
    return CreatedTicketResult(
      ticketId: ticketId,
      humanCode: (data['humanCode'] as String?) ?? ticketId,
    );
  }

  Future<void> transitionTicket({
    required String ticketId,
    required TicketStatus to,
    String? reason,
    String? diagnosis,
    String? workPerformed,
    String? resolutionNotes,
  }) async {
    await _call('transitionTicket', {
      'ticketId': ticketId,
      'toStatus': to.name,
      'reason': reason?.trim(),
      'diagnosis': diagnosis?.trim(),
      'workPerformed': workPerformed?.trim(),
      'resolutionNotes': resolutionNotes?.trim(),
      'requestId': _uuid.v4(),
    });
  }

  Future<void> assignTicket({
    required String ticketId,
    required String primaryAssigneeUid,
    List<String> participantUids = const [],
  }) async {
    await _call('assignTicket', {
      'ticketId': ticketId,
      'primaryAssigneeUid': primaryAssigneeUid,
      'participantUids': participantUids,
      'requestId': _uuid.v4(),
    });
  }

  Future<void> addComment({
    required String ticketId,
    required String text,
  }) async {
    await _call('addComment', {
      'ticketId': ticketId,
      'text': text.trim(),
      'requestId': _uuid.v4(),
    });
  }

  Future<void> updatePriority({
    required String ticketId,
    required TicketPriority priority,
    required String reason,
  }) async {
    await _call('updatePriority', {
      'ticketId': ticketId,
      'priority': priority.name,
      'reason': reason.trim(),
      'requestId': _uuid.v4(),
    });
  }

  Future<void> updateProductionImpact({
    required String ticketId,
    required bool productionStopped,
    required String reason,
  }) async {
    await _call('updateProductionImpact', {
      'ticketId': ticketId,
      'productionStopped': productionStopped,
      'reason': reason.trim(),
      'requestId': _uuid.v4(),
    });
  }

  Future<void> escalateTicket({
    required String ticketId,
    String? reason,
  }) async {
    await _call('escalateTicket', {
      'ticketId': ticketId,
      'reason': reason?.trim(),
      'requestId': _uuid.v4(),
    });
  }

  Future<void> registerAttachment({
    required String ticketId,
    required String attachmentId,
    required String storagePath,
    required String fileName,
    required String contentType,
    required int bytes,
  }) async {
    await _call('registerAttachment', {
      'ticketId': ticketId,
      'attachmentId': attachmentId,
      'storagePath': storagePath,
      'fileName': fileName,
      'contentType': contentType,
      'bytes': bytes,
      'requestId': attachmentId,
    });
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, Object?> payload,
  ) async {
    try {
      final result = await _functions.httpsCallable(name).call(payload);
      final raw = result.data;
      if (raw is Map) {
        return raw.map((key, value) => MapEntry(key.toString(), value));
      }
      return const {};
    } catch (error) {
      throw AppException.from(error);
    }
  }
}
