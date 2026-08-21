import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/core/database/database_service.dart';
import 'package:gestion_interna/core/notifications/notification_service.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_maintenance_repository.dart';
import 'package:gestion_interna/features/maintenance/domain/create_ticket_input.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_question.dart';

void main() {
  late SqliteMaintenanceRepository repository;

  setUp(() {
    repository = SqliteMaintenanceRepository(
      DatabaseService.inMemory(),
      notificationGateway: const NoopNotificationGateway(),
    );
  });
  tearDown(() => repository.close());

  test(
    'persiste agregado, respuestas parciales, eventos y notificaciones',
    () async {
      const question = TicketQuestion(
        id: 'q1',
        prompt: '¿Qué encontró?',
        type: QuestionType.freeText,
        required: true,
        order: 0,
      );
      final created = await repository.createTicket(
        const CreateTicketInput(
          title: 'Motor detenido',
          description: 'No enciende',
          location: 'Línea 2',
          equipment: 'Motor 7',
          priority: TicketPriority.critical,
          questions: [question],
        ),
      );

      var ticket = await repository.watchTicket(created.ticketId).first;
      expect(ticket?.humanCode, 'MTTO-0001');
      expect(ticket?.questions.single.options, isEmpty);
      expect(
        (await repository.watchNotifications(AppRole.maintenance).first),
        hasLength(1),
      );

      await repository.changeStatus(
        created.ticketId,
        TicketStatus.acknowledged,
        AppRole.maintenance,
      );
      await repository.saveAnswers(created.ticketId, const {
        'q1': ['Hallazgo parcial'],
      }, AppRole.maintenance);
      await repository.addUpdate(
        created.ticketId,
        TicketUpdateType.observation,
        'Se revisó alimentación.',
        AppRole.maintenance,
      );
      ticket = await repository.watchTicket(created.ticketId).first;
      expect(ticket?.questions.single.answer, ['Hallazgo parcial']);
      expect(
        (await repository.watchUpdates(created.ticketId).first),
        hasLength(1),
      );
      expect(
        (await repository.watchEvents(created.ticketId).first).length,
        greaterThanOrEqualTo(4),
      );
    },
  );

  test('impide finalizar incompleto y permite finalizar completo', () async {
    final created = await repository.createTicket(
      const CreateTicketInput(
        title: 'Falla',
        description: 'Detalle',
        location: 'Zona',
        priority: TicketPriority.medium,
        questions: [
          TicketQuestion(
            id: 'required',
            prompt: 'Diagnóstico',
            type: QuestionType.freeText,
            required: true,
            order: 0,
          ),
        ],
      ),
    );
    await repository.changeStatus(
      created.ticketId,
      TicketStatus.acknowledged,
      AppRole.maintenance,
    );
    await repository.changeStatus(
      created.ticketId,
      TicketStatus.inProgress,
      AppRole.maintenance,
    );
    await expectLater(
      repository.changeStatus(
        created.ticketId,
        TicketStatus.closed,
        AppRole.maintenance,
      ),
      throwsStateError,
    );
    await repository.saveAnswers(created.ticketId, const {
      'required': ['Correa rota'],
    }, AppRole.maintenance);
    await repository.changeStatus(
      created.ticketId,
      TicketStatus.closed,
      AppRole.maintenance,
    );
    expect(
      (await repository.watchTicket(created.ticketId).first)?.status,
      TicketStatus.closed,
    );
  });

  test('Planta añade una pregunta sin destruir las anteriores', () async {
    final created = await repository.createTicket(
      const CreateTicketInput(
        title: 'Falla',
        description: 'Detalle',
        location: 'Zona',
        priority: TicketPriority.low,
        questions: [
          TicketQuestion(
            id: 'q1',
            prompt: 'Primera',
            type: QuestionType.freeText,
            required: false,
            order: 0,
          ),
        ],
      ),
    );
    await repository.addQuestion(
      created.ticketId,
      const TicketQuestion(
        id: 'q2',
        prompt: 'Segunda',
        type: QuestionType.singleChoice,
        required: true,
        order: 1,
        options: ['Sí', 'No'],
      ),
      AppRole.production,
    );
    final ticket = await repository.watchTicket(created.ticketId).first;
    expect(ticket?.questions.map((q) => q.prompt), ['Primera', 'Segunda']);
    expect(
      (await repository.watchNotifications(AppRole.maintenance).first).length,
      2,
    );
  });
}
