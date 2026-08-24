import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/core/database/database_service.dart';
import 'package:gestion_interna/core/notifications/notification_service.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_form_template_repository.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_maintenance_repository.dart';
import 'package:gestion_interna/features/maintenance/domain/create_ticket_input.dart';
import 'package:gestion_interna/features/maintenance/domain/form_template.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_question.dart';

void main() {
  late DatabaseService database;
  late SqliteFormTemplateRepository templates;

  setUp(() {
    database = DatabaseService.inMemory();
    templates = SqliteFormTemplateRepository(database);
  });
  tearDown(() async {
    await templates.close();
    database.close();
  });

  test(
    'cerrar mantenimiento no invalida repositorios que comparten DB',
    () async {
      final maintenance = SqliteMaintenanceRepository(
        database,
        notificationGateway: const NoopNotificationGateway(),
      );
      await maintenance.close();

      final template = _template();
      await templates.createTemplate(template);
      expect((await templates.getTemplate(template.id))?.name, template.name);
    },
  );

  test('crea, recupera y conserva orden y opciones', () async {
    final template = _template();
    await templates.createTemplate(template);
    final recovered = await templates.getTemplate(template.id);
    expect(recovered?.name, 'Revisión de máquina');
    expect(recovered?.questions.map((question) => question.prompt), [
      'Describa la falla',
      '¿Puede operar?',
      'Acciones realizadas',
    ]);
    expect(recovered?.questions[1].options, ['Sí', 'No']);
    expect(recovered?.questions[2].options, [
      'Limpieza',
      'Ajuste',
      'Lubricación',
    ]);
  });

  test('edita y elimina plantilla', () async {
    final original = _template();
    await templates.createTemplate(original);
    await templates.updateTemplate(
      FormTemplate(
        id: original.id,
        name: 'Revisión actualizada',
        description: 'Nueva descripción',
        questions: [original.questions.last, original.questions.first],
        createdAt: original.createdAt,
        updatedAt: original.updatedAt.add(const Duration(minutes: 1)),
      ),
    );
    final updated = await templates.getTemplate(original.id);
    expect(updated?.name, 'Revisión actualizada');
    expect(updated?.questions.map((question) => question.id), ['q3', 'q1']);
    await templates.deleteTemplate(original.id);
    expect(await templates.getTemplate(original.id), isNull);
  });

  test('valida nombre, preguntas y opciones de selección', () async {
    final now = DateTime(2026);
    final invalid = FormTemplate(
      id: 'invalid',
      name: '',
      questions: const [
        TicketQuestion(
          id: 'q',
          prompt: 'Seleccione',
          type: QuestionType.singleChoice,
          required: true,
          order: 0,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    await expectLater(templates.createTemplate(invalid), throwsArgumentError);
    expect(
      FormTemplate(
        id: 'empty',
        name: 'Vacía',
        questions: const [],
        createdAt: now,
        updatedAt: now,
      ).validate(),
      isNotEmpty,
    );
  });

  test('importa copias independientes con IDs nuevos', () {
    final template = _template();
    var sequence = 0;
    final imported = template.instantiateQuestions(() => 'copy-${sequence++}');
    expect(
      imported.map((question) => question.prompt),
      template.questions.map((question) => question.prompt),
    );
    expect(
      imported
          .map((question) => question.id)
          .toSet()
          .intersection(
            template.questions.map((question) => question.id).toSet(),
          ),
      isEmpty,
    );
    imported[1].options[0] = 'Tal vez';
    expect(template.questions[1].options, ['Sí', 'No']);
  });

  test('combina manuales y plantilla sin borrar preguntas', () {
    const manual = TicketQuestion(
      id: 'manual',
      prompt: 'Pregunta manual',
      type: QuestionType.freeText,
      required: false,
      order: 0,
    );
    var copyId = 0;
    final combined = <TicketQuestion>[
      manual,
      ..._template().instantiateQuestions(() => 'copy-${copyId++}'),
    ];
    expect(combined.first, same(manual));
    expect(combined, hasLength(4));
  });

  test('eliminar plantilla no modifica tickets existentes', () async {
    final maintenance = SqliteMaintenanceRepository(
      database,
      notificationGateway: const NoopNotificationGateway(),
    );
    final template = _template();
    await templates.createTemplate(template);
    var copyIndex = 0;
    final created = await maintenance.createTicket(
      CreateTicketInput(
        title: 'Falla',
        description: 'Detalle',
        location: 'Línea 1',
        priority: TicketPriority.medium,
        questions: template.instantiateQuestions(
          () => 'ticket-copy-${copyIndex++}',
        ),
      ),
    );
    await templates.deleteTemplate(template.id);
    final ticket = await maintenance.watchTicket(created.ticketId).first;
    expect(ticket?.questions, hasLength(3));
    expect(ticket?.questions.first.prompt, 'Describa la falla');
    await maintenance.close();
  });
}

FormTemplate _template() {
  final now = DateTime(2026, 8, 20);
  return FormTemplate(
    id: 'machine-review',
    name: 'Revisión de máquina',
    description: 'Diagnóstico estándar',
    questions: const [
      TicketQuestion(
        id: 'q1',
        prompt: 'Describa la falla',
        type: QuestionType.freeText,
        required: true,
        order: 0,
      ),
      TicketQuestion(
        id: 'q2',
        prompt: '¿Puede operar?',
        type: QuestionType.singleChoice,
        required: true,
        order: 1,
        options: ['Sí', 'No'],
      ),
      TicketQuestion(
        id: 'q3',
        prompt: 'Acciones realizadas',
        type: QuestionType.multipleChoice,
        required: false,
        order: 2,
        options: ['Limpieza', 'Ajuste', 'Lubricación'],
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}
