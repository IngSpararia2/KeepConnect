import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/core/database/database_service.dart';
import 'package:gestion_interna/core/notifications/notification_service.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_maintenance_repository.dart';
import 'package:gestion_interna/features/maintenance/domain/create_ticket_input.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_question.dart';
import 'package:gestion_interna/features/organization/domain/organization_models.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late DatabaseService database;
  late SqliteMaintenanceRepository repository;
  late AccessContext context;

  setUp(() {
    database = DatabaseService.inMemory(seedLegacyContext: false);
    _seedOrganization(database);
    context = _context(
      'production-a',
      AppRole.production,
      'company-a',
      'area-a',
    );
    repository = SqliteMaintenanceRepository(
      database,
      notificationGateway: const NoopNotificationGateway(),
      context: () => context,
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
      context = _context(
        'maintenance-a',
        AppRole.maintenance,
        'company-a',
        'area-a',
      );
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
    context = _context(
      'maintenance-a',
      AppRole.maintenance,
      'company-a',
      'area-a',
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

  test('Solicitante añade una pregunta sin destruir las anteriores', () async {
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
      (await () async {
        context = _context(
          'maintenance-a',
          AppRole.maintenance,
          'company-a',
          'area-a',
        );
        return repository.watchNotifications(AppRole.maintenance).first;
      }()).length,
      2,
    );
  });

  test('cada empresa mantiene su propio consecutivo', () async {
    final db = database.database;
    const stamp = '2026-08-20T12:00:00.000Z';
    db.execute("INSERT INTO companies VALUES ('company-b', 'B', 1, ?, ?)", [
      stamp,
      stamp,
    ]);
    db.execute(
      "INSERT INTO work_areas VALUES ('area-b', 'company-b', 'B', 1, ?, ?)",
      [stamp, stamp],
    );
    db.execute(
      "INSERT INTO user_company_permissions VALUES ('production-a', 'company-b')",
    );
    db.execute(
      "INSERT INTO user_area_permissions VALUES ('production-a', 'area-b')",
    );

    final a1 = await repository.createTicket(_input('A1'));
    context = _context(
      'production-a',
      AppRole.production,
      'company-b',
      'area-b',
      companies: const {'company-a', 'company-b'},
      areas: const {'area-a', 'area-b'},
    );
    final b1 = await repository.createTicket(_input('B1'));
    final b2 = await repository.createTicket(_input('B2'));
    context = _context(
      'production-a',
      AppRole.production,
      'company-a',
      'area-a',
      companies: const {'company-a', 'company-b'},
      areas: const {'area-a', 'area-b'},
    );
    final a2 = await repository.createTicket(_input('A2'));

    expect([a1.humanCode, a2.humanCode], ['MTTO-0001', 'MTTO-0002']);
    expect([b1.humanCode, b2.humanCode], ['MTTO-0001', 'MTTO-0002']);
  });

  test('creaciones próximas no duplican el consecutivo', () async {
    final created = await Future.wait([
      repository.createTicket(_input('Uno')),
      repository.createTicket(_input('Dos')),
    ]);
    expect(created.map((item) => item.humanCode).toSet(), {
      'MTTO-0001',
      'MTTO-0002',
    });
  });

  test('fan-out y lectura son personales', () async {
    final db = database.database;
    _insertUser(db, 'maintenance-2', AppRole.maintenance, active: true);
    _grant(db, 'maintenance-2', 'company-a', 'area-a');
    _insertUser(db, 'maintenance-disabled', AppRole.maintenance, active: false);
    _grant(db, 'maintenance-disabled', 'company-a', 'area-a');
    _insertUser(db, 'production-2', AppRole.production, active: true);
    _grant(db, 'production-2', 'company-a', 'area-a');

    await repository.createTicket(_input('Fan-out'));
    final rows = db.select(
      "SELECT id, recipient_user_id, is_read FROM app_notifications WHERE recipient = 'maintenance' ORDER BY recipient_user_id",
    );
    expect(rows.map((row) => row['recipient_user_id']), [
      'maintenance-2',
      'maintenance-a',
    ]);

    context = _context(
      'maintenance-a',
      AppRole.maintenance,
      'company-a',
      'area-a',
    );
    final own =
        (await repository.watchNotifications(AppRole.maintenance).first).single;
    expect(await repository.watchUnreadCount(AppRole.maintenance).first, 1);
    await repository.markNotificationRead(own.id);
    expect(await repository.watchUnreadCount(AppRole.maintenance).first, 0);

    context = _context(
      'maintenance-2',
      AppRole.maintenance,
      'company-a',
      'area-a',
    );
    final other =
        (await repository.watchNotifications(AppRole.maintenance).first).single;
    expect(other.read, isFalse);
    expect(await repository.watchUnreadCount(AppRole.maintenance).first, 1);

    context = _context(
      'maintenance-a',
      AppRole.maintenance,
      'company-a',
      'area-a',
    );
    await repository.markNotificationRead(other.id);
    expect(
      db.select('SELECT is_read FROM app_notifications WHERE id = ?', [
        other.id,
      ]).single['is_read'],
      0,
    );
  });

  test('fan-out respeta multiempresa en modos selected y all', () async {
    final db = database.database;
    const stamp = '2026-08-20T12:00:00.000Z';
    db.execute("INSERT INTO companies VALUES ('company-b', 'B', 1, ?, ?)", [
      stamp,
      stamp,
    ]);
    db.execute(
      "INSERT INTO work_areas VALUES ('area-b', 'company-b', 'B', 1, ?, ?)",
      [stamp, stamp],
    );
    db.execute(
      "INSERT INTO user_company_permissions VALUES ('production-a', 'company-b')",
    );
    db.execute(
      "INSERT INTO user_area_permissions VALUES ('production-a', 'area-b')",
    );
    _insertUser(db, 'maintenance-selected', AppRole.maintenance, active: true);
    _grant(db, 'maintenance-selected', 'company-a', 'area-a');
    db.execute(
      "INSERT INTO user_company_permissions VALUES ('maintenance-selected', 'company-b')",
    );
    _insertUser(
      db,
      'maintenance-all',
      AppRole.maintenance,
      active: true,
      mode: AreaAccessMode.all,
    );
    db.execute(
      "INSERT INTO user_company_permissions VALUES ('maintenance-all', 'company-a')",
    );
    db.execute(
      "INSERT INTO user_company_permissions VALUES ('maintenance-all', 'company-b')",
    );

    final ticketA = await repository.createTicket(_input('A'));
    context = _context(
      'production-a',
      AppRole.production,
      'company-b',
      'area-b',
      companies: const {'company-a', 'company-b'},
      areas: const {'area-a', 'area-b'},
    );
    final ticketB1 = await repository.createTicket(_input('B1'));
    db.execute(
      "INSERT INTO user_area_permissions VALUES ('maintenance-selected', 'area-b')",
    );
    final ticketB2 = await repository.createTicket(_input('B2'));

    Set<Object?> recipients(String ticketId) => db
        .select(
          'SELECT recipient_user_id FROM app_notifications WHERE ticket_id = ?',
          [ticketId],
        )
        .map((row) => row['recipient_user_id'])
        .toSet();
    expect(recipients(ticketA.ticketId), {
      'maintenance-a',
      'maintenance-all',
      'maintenance-selected',
    });
    expect(recipients(ticketB1.ticketId), {'maintenance-all'});
    expect(recipients(ticketB2.ticketId), {
      'maintenance-all',
      'maintenance-selected',
    });
  });
}

CreateTicketInput _input(String suffix) => CreateTicketInput(
  title: 'Ticket $suffix',
  description: 'Detalle',
  location: 'Zona',
  locationIsCustom: true,
  priority: TicketPriority.medium,
);

AccessContext _context(
  String userId,
  AppRole role,
  String companyId,
  String areaId, {
  Set<String> companies = const {'company-a'},
  Set<String> areas = const {'area-a'},
}) => AccessContext(
  userId: userId,
  privilege: PlatformPrivilege.user,
  operationalRole: role,
  companyId: companyId,
  areaId: areaId,
  allowedCompanyIds: companies,
  allowedAreaIds: areas,
);

void _seedOrganization(DatabaseService service) {
  final db = service.database;
  const stamp = '2026-08-20T12:00:00.000Z';
  db.execute("INSERT INTO companies VALUES ('company-a', 'A', 1, ?, ?)", [
    stamp,
    stamp,
  ]);
  db.execute(
    "INSERT INTO work_areas VALUES ('area-a', 'company-a', 'A', 1, ?, ?)",
    [stamp, stamp],
  );
  _insertUser(db, 'production-a', AppRole.production, active: true);
  _grant(db, 'production-a', 'company-a', 'area-a');
  _insertUser(db, 'maintenance-a', AppRole.maintenance, active: true);
  _grant(db, 'maintenance-a', 'company-a', 'area-a');
}

void _insertUser(
  Database db,
  String id,
  AppRole role, {
  required bool active,
  AreaAccessMode mode = AreaAccessMode.selected,
}) {
  const stamp = '2026-08-20T12:00:00.000Z';
  db.execute(
    'INSERT INTO app_users(id, username, display_name, privilege, operational_role, active, area_access_mode, created_at, updated_at) '
    "VALUES (?, ?, ?, 'user', ?, ?, ?, ?, ?)",
    [id, id, id, role.name, active ? 1 : 0, mode.name, stamp, stamp],
  );
}

void _grant(Database db, String userId, String companyId, String areaId) {
  db.execute('INSERT INTO user_company_permissions VALUES (?, ?)', [
    userId,
    companyId,
  ]);
  db.execute('INSERT INTO user_area_permissions VALUES (?, ?)', [
    userId,
    areaId,
  ]);
}
