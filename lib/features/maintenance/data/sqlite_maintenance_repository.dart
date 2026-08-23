import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_service.dart';
import '../../../core/notifications/app_notification.dart';
import '../../../core/notifications/notification_service.dart';
import '../../organization/domain/organization_models.dart';
import '../domain/create_ticket_input.dart';
import '../domain/maintenance_ticket.dart';
import '../domain/status_transition_policy.dart';
import '../domain/ticket_enums.dart';
import '../domain/ticket_event.dart';
import '../domain/ticket_question.dart';
import '../domain/ticket_update.dart';
import 'maintenance_repository.dart';

final class SqliteMaintenanceRepository implements MaintenanceRepository {
  SqliteMaintenanceRepository(
    this._service, {
    NotificationGateway notificationGateway = const NoopNotificationGateway(),
    AccessContext? Function()? context,
    this._uuid = const Uuid(),
  }) : _notifications = notificationGateway,
       _context = context ?? (() => AccessContext.legacy);

  final DatabaseService _service;
  final NotificationGateway _notifications;
  final Uuid _uuid;
  final AccessContext? Function() _context;
  final _changes = StreamController<void>.broadcast();
  Database get _db => _service.database;

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  @override
  Stream<List<MaintenanceTicket>> watchTickets() =>
      _watch(() => _readTickets());
  @override
  Stream<MaintenanceTicket?> watchTicket(String ticketId) =>
      _watch(() => _readTicket(ticketId));
  @override
  Stream<List<TicketUpdate>> watchUpdates(String ticketId) =>
      _watch(() => _readUpdates(ticketId));
  @override
  Stream<List<TicketEvent>> watchEvents(String ticketId) =>
      _watch(() => _readEvents(ticketId));
  @override
  Stream<List<AppNotification>> watchNotifications(AppRole recipient) =>
      _watch(() => _readNotifications(recipient));
  @override
  Stream<int> watchUnreadCount(AppRole recipient) => _watch(() {
    final scope = _requireScope();
    return _db.select(
          'SELECT COUNT(*) AS total FROM app_notifications '
          'WHERE recipient = ? AND company_id = ? AND area_id = ? AND is_read = 0',
          [recipient.name, scope.companyId, scope.areaId],
        ).first['total']
        as int;
  });

  void _transaction(void Function() operation) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      operation();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<CreatedTicketResult> createTicket(CreateTicketInput input) async {
    final scope = _requireScope();
    final actor = _actualActor(AppRole.production);
    if (actor != AppRole.production) {
      throw StateError('Solo Producción puede crear solicitudes.');
    }
    final errors = input.validate();
    if (errors.isNotEmpty) throw ArgumentError(errors.join('\n'));
    _validateCatalogSelection(
      scope,
      CatalogKind.location,
      input.locationOptionId,
      input.location,
      input.locationIsCustom,
      required: true,
    );
    _validateCatalogSelection(
      scope,
      CatalogKind.equipment,
      input.equipmentOptionId,
      input.equipment,
      input.equipmentIsCustom,
      required: false,
    );
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    final sequence =
        (_db
                .select(
                  "SELECT COALESCE(MAX(CAST(SUBSTR(human_code, 6) AS INTEGER)), 0) "
                  'AS value FROM tickets',
                )
                .first['value']
            as int) +
        1;
    final code = 'MTTO-${sequence.toString().padLeft(4, '0')}';
    late final _PendingNotification pending;
    _transaction(() {
      _db.execute(
        '''INSERT INTO tickets(
        id, human_code, title, description, location, equipment, priority, status,
        created_at, updated_at, company_id, area_id, created_by_user_id,
        location_option_id, location_snapshot, location_is_custom,
        equipment_option_id, equipment_snapshot, equipment_is_custom)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          id,
          code,
          input.title.trim(),
          input.description.trim(),
          input.location.trim(),
          _nullable(input.equipment),
          input.priority.name,
          TicketStatus.pending.name,
          now.toIso8601String(),
          now.toIso8601String(),
          scope.companyId,
          scope.areaId,
          scope.userId,
          input.locationOptionId,
          input.location.trim(),
          input.locationIsCustom ? 1 : 0,
          input.equipmentOptionId,
          _nullable(input.equipment),
          input.equipmentIsCustom ? 1 : 0,
        ],
      );
      for (var i = 0; i < input.questions.length; i++) {
        final question = input.questions[i];
        _insertQuestion(id, question, i);
      }
      _insertEvent(
        id,
        actor,
        TicketEventType.created,
        'Planta creó la solicitud $code.',
        now,
      );
      pending = _insertNotification(
        id,
        AppRole.maintenance,
        'Nueva solicitud $code',
        input.title.trim(),
        'ticket_created',
        now,
      );
    });
    _changed();
    await _show(pending, urgent: input.priority == TicketPriority.critical);
    return CreatedTicketResult(ticketId: id, humanCode: code);
  }

  @override
  Future<void> changeStatus(
    String ticketId,
    TicketStatus status,
    AppRole actor,
  ) async {
    actor = _actualActor(actor);
    final ticket = _requireTicket(ticketId);
    if (!StatusTransitionPolicy.canTransition(
      from: ticket.status,
      to: status,
      role: actor,
    )) {
      throw StateError('Transición de estado no permitida.');
    }
    if (status == TicketStatus.closed && !ticket.isFormComplete) {
      final missing = ticket.missingRequiredQuestions
          .map((question) => question.prompt)
          .join(', ');
      throw StateError('Completa las preguntas obligatorias: $missing');
    }
    final now = DateTime.now().toUtc();
    late final _PendingNotification pending;
    _transaction(() {
      _db.execute(
        'UPDATE tickets SET status = ?, updated_at = ? WHERE id = ?',
        [status.name, now.toIso8601String(), ticketId],
      );
      _insertEvent(
        ticketId,
        actor,
        status == TicketStatus.closed
            ? TicketEventType.closed
            : TicketEventType.statusChanged,
        'Estado cambiado de ${ticket.status.label} a ${status.label}.',
        now,
      );
      pending = _insertNotification(
        ticketId,
        AppRole.production,
        '${ticket.humanCode}: ${status.label}',
        ticket.title,
        status.name,
        now,
      );
    });
    _changed();
    await _show(pending, urgent: status == TicketStatus.closed);
  }

  @override
  Future<void> saveAnswers(
    String ticketId,
    Map<String, List<String>> answers,
    AppRole actor,
  ) async {
    actor = _actualActor(actor);
    final ticket = _requireTicket(ticketId);
    if (actor != AppRole.maintenance) {
      throw StateError('Solo Mantenimiento puede responder el formulario.');
    }
    if (ticket.status == TicketStatus.closed) {
      throw StateError('El ticket finalizado no admite cambios.');
    }
    final questions = {for (final q in ticket.questions) q.id: q};
    for (final entry in answers.entries) {
      final question = questions[entry.key];
      if (question == null) throw StateError('La pregunta ya no existe.');
      if (entry.value.any(
        (value) =>
            question.type != QuestionType.freeText &&
            !question.options.contains(value),
      )) {
        throw ArgumentError('Respuesta no válida para ${question.prompt}.');
      }
    }
    final now = DateTime.now().toUtc();
    late final _PendingNotification pending;
    _transaction(() {
      for (final entry in answers.entries) {
        _db.execute(
          'INSERT INTO ticket_answers(question_id, selected_values, updated_at) '
          'VALUES (?, ?, ?) ON CONFLICT(question_id) DO UPDATE SET '
          'selected_values = excluded.selected_values, updated_at = excluded.updated_at',
          [entry.key, jsonEncode(entry.value), now.toIso8601String()],
        );
      }
      _db.execute('UPDATE tickets SET updated_at = ? WHERE id = ?', [
        now.toIso8601String(),
        ticketId,
      ]);
      _insertEvent(
        ticketId,
        actor,
        TicketEventType.answersSaved,
        'Mantenimiento guardó el progreso del formulario.',
        now,
      );
      if (_requiredQuestionsComplete(ticketId) &&
          _db.select(
            'SELECT 1 FROM ticket_events WHERE ticket_id = ? AND type = ? LIMIT 1',
            [ticketId, TicketEventType.formCompleted.name],
          ).isEmpty) {
        _insertEvent(
          ticketId,
          actor,
          TicketEventType.formCompleted,
          'El formulario obligatorio quedó completo.',
          now,
        );
      }
      pending = _insertNotification(
        ticketId,
        AppRole.production,
        'Formulario actualizado · ${ticket.humanCode}',
        'Mantenimiento guardó respuestas.',
        'answers_saved',
        now,
      );
    });
    _changed();
    await _show(pending);
  }

  @override
  Future<void> addQuestion(
    String ticketId,
    TicketQuestion question,
    AppRole actor,
  ) async {
    actor = _actualActor(actor);
    final ticket = _requireTicket(ticketId);
    if (actor != AppRole.production || ticket.status == TicketStatus.closed) {
      throw StateError('No es posible añadir preguntas a este ticket.');
    }
    if (question.validate() case final error?) throw ArgumentError(error);
    final now = DateTime.now().toUtc();
    late final _PendingNotification pending;
    _transaction(() {
      _insertQuestion(ticketId, question, ticket.questions.length);
      _db.execute('UPDATE tickets SET updated_at = ? WHERE id = ?', [
        now.toIso8601String(),
        ticketId,
      ]);
      _insertEvent(
        ticketId,
        actor,
        TicketEventType.questionAdded,
        'Planta añadió la pregunta: ${question.prompt}',
        now,
      );
      pending = _insertNotification(
        ticketId,
        AppRole.maintenance,
        'Nueva pregunta · ${ticket.humanCode}',
        question.prompt,
        'question_added',
        now,
      );
    });
    _changed();
    await _show(pending);
  }

  @override
  Future<void> addUpdate(
    String ticketId,
    TicketUpdateType type,
    String content,
    AppRole actor,
  ) async {
    actor = _actualActor(actor);
    final ticket = _requireTicket(ticketId);
    final clean = content.trim();
    if (clean.isEmpty) throw ArgumentError('Escribe una actualización.');
    final now = DateTime.now().toUtc();
    late final _PendingNotification pending;
    _transaction(() {
      _db.execute(
        'INSERT INTO ticket_updates(id, ticket_id, actor, type, content, created_at, actor_user_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          _uuid.v4(),
          ticketId,
          actor.name,
          type.name,
          clean,
          now.toIso8601String(),
          _requireScope().userId,
        ],
      );
      _db.execute('UPDATE tickets SET updated_at = ? WHERE id = ?', [
        now.toIso8601String(),
        ticketId,
      ]);
      _insertEvent(
        ticketId,
        actor,
        TicketEventType.updateAdded,
        '${actor.label} añadió una actualización (${type.label}).',
        now,
      );
      pending = _insertNotification(
        ticketId,
        actor.other,
        'Actualización · ${ticket.humanCode}',
        clean,
        'update_added',
        now,
      );
    });
    _changed();
    await _show(pending);
  }

  @override
  Future<void> markNotificationRead(String notificationId) async {
    final scope = _requireScope();
    _db.execute(
      'UPDATE app_notifications SET is_read = 1 WHERE id = ? AND company_id = ? AND area_id = ?',
      [notificationId, scope.companyId, scope.areaId],
    );
    _changed();
  }

  void _insertQuestion(String ticketId, TicketQuestion question, int order) {
    _db.execute('INSERT INTO ticket_questions VALUES (?, ?, ?, ?, ?, ?)', [
      question.id,
      ticketId,
      question.prompt.trim(),
      question.type.name,
      question.required ? 1 : 0,
      order,
    ]);
    for (var i = 0; i < question.options.length; i++) {
      _db.execute(
        'INSERT INTO question_options(question_id, value, sort_order) VALUES (?, ?, ?)',
        [question.id, question.options[i].trim(), i],
      );
    }
  }

  void _insertEvent(
    String ticketId,
    AppRole actor,
    TicketEventType type,
    String message,
    DateTime createdAt,
  ) {
    _db.execute(
      'INSERT INTO ticket_events(id, ticket_id, actor, type, message, created_at, actor_user_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        _uuid.v4(),
        ticketId,
        actor.name,
        type.name,
        message,
        createdAt.toIso8601String(),
        _requireScope().userId,
      ],
    );
  }

  _PendingNotification _insertNotification(
    String ticketId,
    AppRole recipient,
    String title,
    String message,
    String eventType,
    DateTime createdAt,
  ) {
    final pending = _PendingNotification(ticketId, title, message);
    final scope = _requireScope();
    _db.execute(
      'INSERT INTO app_notifications(id, ticket_id, title, message, recipient, event_type, is_read, '
      'created_at, company_id, area_id) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?)',
      [
        _uuid.v4(),
        ticketId,
        title,
        message,
        recipient.name,
        eventType,
        createdAt.toIso8601String(),
        scope.companyId,
        scope.areaId,
      ],
    );
    return pending;
  }

  Future<void> _show(_PendingNotification item, {bool urgent = false}) async {
    try {
      await _notifications.show(
        ticketId: item.ticketId,
        title: item.title,
        message: item.message,
        urgent: urgent,
      );
    } catch (_) {
      // La bandeja SQLite es la fuente persistente; el permiso del sistema es opcional.
    }
  }

  MaintenanceTicket _requireTicket(String id) =>
      _readTicket(id) ?? (throw StateError('La solicitud no existe.'));

  List<MaintenanceTicket> _readTickets() {
    final scope = _requireScope();
    return _db
        .select(
          'SELECT * FROM tickets WHERE company_id = ? AND area_id = ? ORDER BY updated_at DESC',
          [scope.companyId, scope.areaId],
        )
        .map(_ticketFromRow)
        .toList();
  }

  MaintenanceTicket? _readTicket(String id) {
    final scope = _requireScope();
    final rows = _db.select(
      'SELECT * FROM tickets WHERE id = ? AND company_id = ? AND area_id = ?',
      [id, scope.companyId, scope.areaId],
    );
    return rows.isEmpty ? null : _ticketFromRow(rows.first);
  }

  MaintenanceTicket _ticketFromRow(Row row) => MaintenanceTicket(
    id: row['id'] as String,
    humanCode: row['human_code'] as String,
    title: row['title'] as String,
    description: row['description'] as String,
    location: (row['location_snapshot'] ?? row['location']) as String,
    equipment: (row['equipment_snapshot'] ?? row['equipment']) as String?,
    companyId: row['company_id'] as String,
    areaId: row['area_id'] as String,
    createdByUserId: row['created_by_user_id'] as String,
    locationOptionId: row['location_option_id'] as String?,
    locationIsCustom: row['location_is_custom'] == 1,
    equipmentOptionId: row['equipment_option_id'] as String?,
    equipmentIsCustom: row['equipment_is_custom'] == 1,
    priority: TicketPriority.fromValue(row['priority']),
    status: TicketStatus.fromValue(row['status']),
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
    questions: _readQuestions(row['id'] as String),
  );

  List<TicketQuestion> _readQuestions(String ticketId) => _db
      .select(
        'SELECT * FROM ticket_questions WHERE ticket_id = ? ORDER BY sort_order',
        [ticketId],
      )
      .map((row) {
        final id = row['id'] as String;
        final answerRows = _db.select(
          'SELECT selected_values FROM ticket_answers WHERE question_id = ?',
          [id],
        );
        return TicketQuestion(
          id: id,
          prompt: row['prompt'] as String,
          type: QuestionType.fromValue(row['type']),
          required: row['required'] == 1,
          order: row['sort_order'] as int,
          options: _db
              .select(
                'SELECT value FROM question_options WHERE question_id = ? ORDER BY sort_order',
                [id],
              )
              .map((option) => option['value'] as String)
              .toList(),
          answer: answerRows.isEmpty
              ? const []
              : (jsonDecode(answerRows.first['selected_values'] as String)
                        as List<dynamic>)
                    .cast<String>(),
        );
      })
      .toList();

  bool _requiredQuestionsComplete(String ticketId) => _db
      .select(
        '''
    SELECT 1 FROM ticket_questions q
    LEFT JOIN ticket_answers a ON a.question_id = q.id
    WHERE q.ticket_id = ? AND q.required = 1
      AND (a.selected_values IS NULL OR a.selected_values = '[]' OR a.selected_values = '[""]')
    LIMIT 1
  ''',
        [ticketId],
      )
      .isEmpty;

  List<TicketUpdate> _readUpdates(String ticketId) {
    _requireTicket(ticketId);
    return _db
        .select(
          'SELECT * FROM ticket_updates WHERE ticket_id = ? ORDER BY created_at',
          [ticketId],
        )
        .map(
          (row) => TicketUpdate(
            id: row['id'] as String,
            ticketId: ticketId,
            actor: AppRole.values.byName(row['actor'] as String),
            type: TicketUpdateType.values.byName(row['type'] as String),
            content: row['content'] as String,
            createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
            actorUserId: row['actor_user_id'] as String?,
          ),
        )
        .toList();
  }

  List<TicketEvent> _readEvents(String ticketId) {
    _requireTicket(ticketId);
    return _db
        .select(
          'SELECT * FROM ticket_events WHERE ticket_id = ? ORDER BY created_at DESC',
          [ticketId],
        )
        .map(
          (row) => TicketEvent(
            id: row['id'] as String,
            ticketId: ticketId,
            type: TicketEventType.fromValue(row['type']),
            actor: AppRole.values.byName(row['actor'] as String),
            message: row['message'] as String,
            createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
            actorUserId: row['actor_user_id'] as String?,
          ),
        )
        .toList();
  }

  List<AppNotification> _readNotifications(AppRole recipient) {
    final scope = _requireScope();
    return _db
        .select(
          'SELECT * FROM app_notifications WHERE recipient = ? AND company_id = ? AND area_id = ? ORDER BY created_at DESC',
          [recipient.name, scope.companyId, scope.areaId],
        )
        .map(
          (row) => AppNotification(
            id: row['id'] as String,
            ticketId: row['ticket_id'] as String,
            title: row['title'] as String,
            message: row['message'] as String,
            recipient: recipient,
            eventType: row['event_type'] as String,
            read: row['is_read'] == 1,
            createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
            companyId: row['company_id'] as String?,
            areaId: row['area_id'] as String?,
            recipientUserId: row['recipient_user_id'] as String?,
          ),
        )
        .toList();
  }

  AccessContext _requireScope() {
    final scope = _context();
    if (scope == null || scope.companyId == null || scope.areaId == null) {
      throw StateError('Selecciona una empresa y un área antes de continuar.');
    }
    if (!scope.permits(scope.companyId!, scope.areaId!)) {
      throw StateError('No tienes acceso al contexto seleccionado.');
    }
    return scope;
  }

  AppRole _actualActor(AppRole requested) {
    final scope = _requireScope();
    if (!scope.isSuperAdmin && requested != scope.operationalRole) {
      throw StateError(
        'El rol indicado no coincide con el usuario autenticado.',
      );
    }
    return scope.isSuperAdmin ? requested : scope.operationalRole;
  }

  void _validateCatalogSelection(
    AccessContext scope,
    CatalogKind kind,
    String? itemId,
    String? snapshot,
    bool custom, {
    required bool required,
  }) {
    final clean = snapshot?.trim() ?? '';
    if (custom) {
      if (required && clean.isEmpty) {
        throw ArgumentError('El valor personalizado es obligatorio.');
      }
      if (itemId != null) {
        throw ArgumentError(
          'Un valor personalizado no puede usar un ID de catálogo.',
        );
      }
      return;
    }
    if (clean.isEmpty && !required && itemId == null) {
      return;
    }
    if (itemId == null) {
      throw ArgumentError('Selecciona una opción administrada.');
    }
    final rows = _db.select(
      'SELECT name FROM catalog_items WHERE id = ? AND company_id = ? AND area_id = ? AND kind = ? AND active = 1',
      [itemId, scope.companyId, scope.areaId, kind.name],
    );
    if (rows.isEmpty || rows.first['name'] != clean) {
      throw StateError(
        'La opción de catálogo no es válida para el área actual.',
      );
    }
  }

  String? _nullable(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  void _changed() => _changes.add(null);

  @override
  Future<void> close() async {
    await _changes.close();
    _service.close();
  }
}

final class _PendingNotification {
  const _PendingNotification(this.ticketId, this.title, this.message);
  final String ticketId;
  final String title;
  final String message;
}
