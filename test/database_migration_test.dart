import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/core/database/database_service.dart';
import 'package:gestion_interna/core/notifications/notification_service.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_maintenance_repository.dart';
import 'package:gestion_interna/features/maintenance/domain/create_ticket_input.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/features/organization/data/sqlite_organization_repository.dart';
import 'package:gestion_interna/features/organization/domain/organization_models.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('migra esquema legacy, conserva datos y asigna empresa/área', () async {
    final directory = await Directory.systemTemp.createTemp(
      'keepconnect-migration-',
    );
    final path = '${directory.path}${Platform.pathSeparator}legacy.db';
    final legacy = sqlite3.open(path);
    legacy.execute('''
      CREATE TABLE tickets (
        id TEXT PRIMARY KEY, human_code TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
        description TEXT NOT NULL, location TEXT NOT NULL, equipment TEXT,
        priority TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      );
      CREATE TABLE ticket_questions (
        id TEXT PRIMARY KEY, ticket_id TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
        prompt TEXT NOT NULL, type TEXT NOT NULL, required INTEGER NOT NULL, sort_order INTEGER NOT NULL
      );
      CREATE TABLE question_options (
        id INTEGER PRIMARY KEY AUTOINCREMENT, question_id TEXT NOT NULL REFERENCES ticket_questions(id) ON DELETE CASCADE,
        value TEXT NOT NULL, sort_order INTEGER NOT NULL
      );
      CREATE TABLE ticket_answers (
        question_id TEXT PRIMARY KEY REFERENCES ticket_questions(id) ON DELETE CASCADE,
        selected_values TEXT NOT NULL, updated_at TEXT NOT NULL
      );
      CREATE TABLE ticket_updates (
        id TEXT PRIMARY KEY, ticket_id TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
        actor TEXT NOT NULL, type TEXT NOT NULL, content TEXT NOT NULL, created_at TEXT NOT NULL
      );
      CREATE TABLE ticket_events (
        id TEXT PRIMARY KEY, ticket_id TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
        actor TEXT NOT NULL, type TEXT NOT NULL, message TEXT NOT NULL, created_at TEXT NOT NULL
      );
      CREATE TABLE app_notifications (
        id TEXT PRIMARY KEY, ticket_id TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
        title TEXT NOT NULL, message TEXT NOT NULL, recipient TEXT NOT NULL,
        event_type TEXT NOT NULL, is_read INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL
      );
      CREATE TABLE form_templates (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      );
      CREATE TABLE form_template_questions (
        id TEXT PRIMARY KEY, template_id TEXT NOT NULL REFERENCES form_templates(id) ON DELETE CASCADE,
        prompt TEXT NOT NULL, type TEXT NOT NULL, required INTEGER NOT NULL, sort_order INTEGER NOT NULL
      );
      CREATE TABLE form_template_question_options (
        id INTEGER PRIMARY KEY AUTOINCREMENT, question_id TEXT NOT NULL REFERENCES form_template_questions(id) ON DELETE CASCADE,
        value TEXT NOT NULL, sort_order INTEGER NOT NULL
      );
    ''');
    const stamp = '2026-08-20T12:00:00.000Z';
    legacy
        .execute('INSERT INTO tickets VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
          'ticket-1',
          'MTTO-0001',
          'Motor',
          'No enciende',
          'Línea 1',
          'Motor 7',
          'critical',
          'pending',
          stamp,
          stamp,
        ]);
    legacy.execute('INSERT INTO ticket_questions VALUES (?, ?, ?, ?, ?, ?)', [
      'q1',
      'ticket-1',
      'Diagnóstico',
      'freeText',
      1,
      0,
    ]);
    legacy.execute('INSERT INTO ticket_answers VALUES (?, ?, ?)', [
      'q1',
      '["Correa"]',
      stamp,
    ]);
    legacy.execute('INSERT INTO ticket_updates VALUES (?, ?, ?, ?, ?, ?)', [
      'u1',
      'ticket-1',
      'maintenance',
      'observation',
      'Revisado',
      stamp,
    ]);
    legacy.execute('INSERT INTO ticket_events VALUES (?, ?, ?, ?, ?, ?)', [
      'e1',
      'ticket-1',
      'production',
      'created',
      'Creado',
      stamp,
    ]);
    legacy.execute(
      'INSERT INTO app_notifications VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      ['n1', 'ticket-1', 'Nueva', 'Motor', 'maintenance', 'created', 0, stamp],
    );
    legacy.execute('INSERT INTO form_templates VALUES (?, ?, ?, ?, ?)', [
      'f1',
      'Revisión',
      null,
      stamp,
      stamp,
    ]);
    legacy.execute(
      'INSERT INTO form_template_questions VALUES (?, ?, ?, ?, ?, ?)',
      ['fq1', 'f1', 'Pregunta', 'freeText', 1, 0],
    );
    legacy.dispose();

    final migrated = DatabaseService.fromPath(path);
    addTearDown(() {
      migrated.close();
      directory.deleteSync(recursive: true);
    });
    final db = migrated.database;
    expect(migrated.version, DatabaseService.schemaVersion);
    final ticket = db.select('SELECT * FROM tickets WHERE id = ?', [
      'ticket-1',
    ]).single;
    expect(ticket['company_id'], DatabaseService.legacyCompanyId);
    expect(ticket['area_id'], DatabaseService.legacyPlantAreaId);
    expect(ticket['created_by_user_id'], DatabaseService.legacyUserId);
    expect(ticket['location_snapshot'], 'Línea 1');
    expect(ticket['equipment_snapshot'], 'Motor 7');
    expect(db.select('SELECT * FROM ticket_questions'), hasLength(1));
    expect(db.select('SELECT * FROM ticket_answers'), hasLength(1));
    expect(
      db.select('SELECT * FROM ticket_updates').single['actor_user_id'],
      DatabaseService.legacyUserId,
    );
    expect(
      db.select('SELECT * FROM ticket_events').single['actor_user_id'],
      DatabaseService.legacyUserId,
    );
    expect(
      db.select('SELECT * FROM app_notifications').single['area_id'],
      DatabaseService.legacyPlantAreaId,
    );
    expect(
      db.select('SELECT * FROM form_templates').single['company_id'],
      DatabaseService.legacyCompanyId,
    );
    expect(db.select('SELECT * FROM work_areas'), hasLength(3));
  });

  test(
    'instalación nueva queda lista para bootstrap sin datos hardcodeados',
    () {
      final database = DatabaseService.inMemory(seedLegacyContext: false);
      addTearDown(database.close);
      expect(database.version, DatabaseService.schemaVersion);
      expect(database.database.select('SELECT * FROM companies'), isEmpty);
      expect(database.database.select('SELECT * FROM app_users'), isEmpty);
    },
  );

  test('migra v3 a v4 conservando relaciones y fan-out legacy', () async {
    final directory = await Directory.systemTemp.createTemp(
      'keepconnect-v3-migration-',
    );
    final path = '${directory.path}${Platform.pathSeparator}v3.db';
    final v3 = sqlite3.open(path);
    _createVersion3Fixture(v3);
    v3.dispose();

    final migrated = DatabaseService.fromPath(path);
    addTearDown(() {
      migrated.close();
      directory.deleteSync(recursive: true);
    });
    final db = migrated.database;
    expect(migrated.version, DatabaseService.schemaVersion);
    expect(
      db
          .select('SELECT id, human_code FROM tickets ORDER BY id')
          .map((row) => [row['id'], row['human_code']]),
      [
        ['ticket-a', 'MTTO-0001'],
        ['ticket-b', 'MTTO-0002'],
      ],
    );
    expect(db.select('SELECT * FROM ticket_questions'), hasLength(1));
    expect(db.select('SELECT * FROM question_options'), hasLength(1));
    expect(db.select('SELECT * FROM ticket_answers'), hasLength(1));
    expect(db.select('SELECT * FROM ticket_updates'), hasLength(1));
    expect(db.select('SELECT * FROM ticket_events'), hasLength(1));

    final legacy = db.select(
      'SELECT * FROM app_notifications WHERE recipient_user_id IS NULL ORDER BY id',
    );
    expect(legacy.map((row) => row['id']), [
      'notification-read',
      'notification-unread',
    ]);
    final copies = db.select(
      "SELECT recipient_user_id, is_read FROM app_notifications WHERE id NOT IN ('notification-read', 'notification-unread', 'notification-personal') ORDER BY is_read",
    );
    expect(copies, hasLength(2));
    expect(copies.map((row) => row['recipient_user_id']).toSet(), {
      'maintenance-a',
    });
    expect(copies.map((row) => row['is_read']), [0, 1]);
    expect(
      db
          .select(
            "SELECT COUNT(*) AS count FROM app_notifications WHERE id = 'notification-personal'",
          )
          .single['count'],
      1,
    );

    _insertTicket(
      db,
      'ticket-b-same-code',
      'MTTO-0001',
      'company-b',
      'area-b',
      'user-b',
    );
    expect(
      () => _insertTicket(
        db,
        'ticket-a-duplicate',
        'MTTO-0001',
        'company-a',
        'area-a',
        'user-a',
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => _insertTicket(
        db,
        'ticket-cross-scope',
        'MTTO-0099',
        'company-a',
        'area-b',
        'user-a',
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => db.execute(
        "INSERT INTO user_area_permissions VALUES ('user-a', 'area-b')",
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => db.execute(
        "INSERT INTO app_notifications VALUES ('new-null', 'ticket-a', 'N', 'M', 'maintenance', 'created', 0, '2026-08-20T12:00:00.000Z', 'company-a', 'area-a', NULL)",
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => db.execute(
        "INSERT INTO app_notifications VALUES ('cross-scope', 'ticket-a', 'N', 'M', 'maintenance', 'created', 0, '2026-08-20T12:00:00.000Z', 'company-b', 'area-b', 'maintenance-a')",
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');

    var context = const AccessContext(
      userId: 'user-a',
      privilege: PlatformPrivilege.user,
      operationalRole: AppRole.production,
      companyId: 'company-a',
      areaId: 'area-a',
      allowedCompanyIds: {'company-a'},
      allowedAreaIds: {'area-a'},
    );
    final repository = SqliteMaintenanceRepository(
      migrated,
      notificationGateway: const NoopNotificationGateway(),
      context: () => context,
    );
    final nextA = await repository.createTicket(_ticketInput('A'));
    context = const AccessContext(
      userId: 'user-b',
      privilege: PlatformPrivilege.user,
      operationalRole: AppRole.production,
      companyId: 'company-b',
      areaId: 'area-b',
      allowedCompanyIds: {'company-b'},
      allowedAreaIds: {'area-b'},
    );
    final nextB = await repository.createTicket(_ticketInput('B'));
    expect(nextA.humanCode, 'MTTO-0002');
    expect(nextB.humanCode, 'MTTO-0003');
  });

  test('migra v2 a v3 y conserva la empresa del usuario existente', () async {
    final directory = await Directory.systemTemp.createTemp(
      'keepconnect-v2-migration-',
    );
    final path = '${directory.path}${Platform.pathSeparator}v2.db';
    final v2 = sqlite3.open(path);
    _createVersion3Fixture(v2, version: 2, companyPermissions: false);
    v2.dispose();

    final migrated = DatabaseService.fromPath(path);
    final organizations = SqliteOrganizationRepository(migrated);
    addTearDown(() async {
      await organizations.close();
      migrated.close();
      directory.deleteSync(recursive: true);
    });

    expect(migrated.version, DatabaseService.schemaVersion);
    expect(
      migrated.database.select(
        'SELECT company_id FROM user_company_permissions WHERE user_id = ?',
        ['user-a'],
      ).single['company_id'],
      'company-a',
    );
    final user = await organizations.findUser('user-a');
    expect(user?.companyIds, {'company-a'});
    expect(user?.areaIds, {'area-a'});
  });
}

CreateTicketInput _ticketInput(String suffix) => CreateTicketInput(
  title: 'Migrado $suffix',
  description: 'Detalle',
  location: 'Zona',
  locationIsCustom: true,
  priority: TicketPriority.medium,
);

void _createVersion3Fixture(
  Database db, {
  int version = 3,
  bool companyPermissions = true,
}) {
  const stamp = '2026-08-20T12:00:00.000Z';
  db.execute('''
    PRAGMA foreign_keys = ON;
    PRAGMA user_version = $version;
    CREATE TABLE companies (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, active INTEGER NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    CREATE TABLE work_areas (
      id TEXT PRIMARY KEY, company_id TEXT NOT NULL REFERENCES companies(id),
      name TEXT NOT NULL, active INTEGER NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    CREATE TABLE app_users (
      id TEXT PRIMARY KEY, username TEXT NOT NULL, display_name TEXT NOT NULL,
      privilege TEXT NOT NULL, company_id TEXT REFERENCES companies(id),
      operational_role TEXT, active INTEGER NOT NULL,
      area_access_mode TEXT NOT NULL, password_hash TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, last_seen_at TEXT
    );
    CREATE TABLE user_area_permissions (
      user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
      area_id TEXT NOT NULL REFERENCES work_areas(id) ON DELETE CASCADE,
      PRIMARY KEY(user_id, area_id)
    );
    CREATE TABLE catalog_items (
      id TEXT PRIMARY KEY, company_id TEXT NOT NULL REFERENCES companies(id),
      area_id TEXT NOT NULL REFERENCES work_areas(id), kind TEXT NOT NULL,
      name TEXT NOT NULL, active INTEGER NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    CREATE TABLE tickets (
      id TEXT PRIMARY KEY, human_code TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
      description TEXT NOT NULL, location TEXT NOT NULL, equipment TEXT,
      priority TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL, company_id TEXT NOT NULL REFERENCES companies(id),
      area_id TEXT NOT NULL REFERENCES work_areas(id),
      created_by_user_id TEXT NOT NULL REFERENCES app_users(id),
      location_option_id TEXT REFERENCES catalog_items(id),
      location_snapshot TEXT NOT NULL, location_is_custom INTEGER NOT NULL,
      equipment_option_id TEXT REFERENCES catalog_items(id),
      equipment_snapshot TEXT, equipment_is_custom INTEGER NOT NULL
    );
    CREATE TABLE ticket_questions (
      id TEXT PRIMARY KEY, ticket_id TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
      prompt TEXT NOT NULL, type TEXT NOT NULL, required INTEGER NOT NULL, sort_order INTEGER NOT NULL
    );
    CREATE TABLE question_options (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      question_id TEXT NOT NULL REFERENCES ticket_questions(id) ON DELETE CASCADE,
      value TEXT NOT NULL, sort_order INTEGER NOT NULL
    );
    CREATE TABLE ticket_answers (
      question_id TEXT PRIMARY KEY REFERENCES ticket_questions(id) ON DELETE CASCADE,
      selected_values TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    CREATE TABLE ticket_updates (
      id TEXT PRIMARY KEY, ticket_id TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
      actor TEXT NOT NULL, type TEXT NOT NULL, content TEXT NOT NULL,
      created_at TEXT NOT NULL, actor_user_id TEXT REFERENCES app_users(id)
    );
    CREATE TABLE ticket_events (
      id TEXT PRIMARY KEY, ticket_id TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
      actor TEXT NOT NULL, type TEXT NOT NULL, message TEXT NOT NULL,
      created_at TEXT NOT NULL, actor_user_id TEXT REFERENCES app_users(id)
    );
    CREATE TABLE app_notifications (
      id TEXT PRIMARY KEY, ticket_id TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
      title TEXT NOT NULL, message TEXT NOT NULL, recipient TEXT NOT NULL,
      event_type TEXT NOT NULL, is_read INTEGER NOT NULL, created_at TEXT NOT NULL,
      company_id TEXT NOT NULL REFERENCES companies(id),
      area_id TEXT NOT NULL REFERENCES work_areas(id),
      recipient_user_id TEXT REFERENCES app_users(id)
    );
    CREATE TABLE form_templates (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      company_id TEXT NOT NULL REFERENCES companies(id), area_id TEXT REFERENCES work_areas(id)
    );
    CREATE TABLE form_template_questions (
      id TEXT PRIMARY KEY, template_id TEXT NOT NULL REFERENCES form_templates(id) ON DELETE CASCADE,
      prompt TEXT NOT NULL, type TEXT NOT NULL, required INTEGER NOT NULL, sort_order INTEGER NOT NULL
    );
    CREATE TABLE form_template_question_options (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      question_id TEXT NOT NULL REFERENCES form_template_questions(id) ON DELETE CASCADE,
      value TEXT NOT NULL, sort_order INTEGER NOT NULL
    );
    INSERT INTO companies VALUES ('company-a', 'Empresa A', 1, '$stamp', '$stamp');
    INSERT INTO companies VALUES ('company-b', 'Empresa B', 1, '$stamp', '$stamp');
    INSERT INTO work_areas VALUES ('area-a', 'company-a', 'Área A', 1, '$stamp', '$stamp');
    INSERT INTO work_areas VALUES ('area-b', 'company-b', 'Área B', 1, '$stamp', '$stamp');
    INSERT INTO app_users VALUES ('user-a', 'user-a', 'A', 'user', 'company-a', 'production', 1, 'selected', 'hash', '$stamp', '$stamp', NULL);
    INSERT INTO app_users VALUES ('user-b', 'user-b', 'B', 'user', 'company-b', 'production', 1, 'selected', 'hash', '$stamp', '$stamp', NULL);
    INSERT INTO app_users VALUES ('maintenance-a', 'maintenance-a', 'M', 'user', 'company-a', 'maintenance', 1, 'selected', 'hash', '$stamp', '$stamp', NULL);
    INSERT INTO app_users VALUES ('maintenance-disabled', 'maintenance-disabled', 'MD', 'user', 'company-a', 'maintenance', 0, 'selected', 'hash', '$stamp', '$stamp', NULL);
    INSERT INTO user_area_permissions VALUES ('user-a', 'area-a');
    INSERT INTO user_area_permissions VALUES ('user-b', 'area-b');
    INSERT INTO user_area_permissions VALUES ('maintenance-a', 'area-a');
    INSERT INTO user_area_permissions VALUES ('maintenance-disabled', 'area-a');
    INSERT INTO form_templates VALUES ('template-a', 'Plantilla', NULL, '$stamp', '$stamp', 'company-a', 'area-a');
  ''');
  if (companyPermissions) {
    db.execute('''
      CREATE TABLE user_company_permissions (
        user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
        PRIMARY KEY(user_id, company_id)
      );
      INSERT INTO user_company_permissions VALUES ('user-a', 'company-a');
      INSERT INTO user_company_permissions VALUES ('user-b', 'company-b');
      INSERT INTO user_company_permissions VALUES ('maintenance-a', 'company-a');
      INSERT INTO user_company_permissions VALUES ('maintenance-disabled', 'company-a');
    ''');
  }
  _insertTicket(db, 'ticket-a', 'MTTO-0001', 'company-a', 'area-a', 'user-a');
  _insertTicket(db, 'ticket-b', 'MTTO-0002', 'company-b', 'area-b', 'user-b');
  db.execute('''
    INSERT INTO ticket_questions VALUES ('question-a', 'ticket-a', 'Pregunta', 'singleChoice', 1, 0);
    INSERT INTO question_options(question_id, value, sort_order) VALUES ('question-a', 'Sí', 0);
    INSERT INTO ticket_answers VALUES ('question-a', '["Sí"]', '$stamp');
    INSERT INTO ticket_updates VALUES ('update-a', 'ticket-a', 'maintenance', 'observation', 'Revisado', '$stamp', 'maintenance-a');
    INSERT INTO ticket_events VALUES ('event-a', 'ticket-a', 'production', 'created', 'Creado', '$stamp', 'user-a');
    INSERT INTO app_notifications VALUES ('notification-unread', 'ticket-a', 'Nueva', 'Mensaje', 'maintenance', 'created', 0, '$stamp', 'company-a', 'area-a', NULL);
    INSERT INTO app_notifications VALUES ('notification-read', 'ticket-a', 'Leída', 'Mensaje', 'maintenance', 'created', 1, '$stamp', 'company-a', 'area-a', NULL);
    INSERT INTO app_notifications VALUES ('notification-personal', 'ticket-a', 'Personal', 'Mensaje', 'maintenance', 'created', 0, '$stamp', 'company-a', 'area-a', 'maintenance-a');
  ''');
}

void _insertTicket(
  Database db,
  String id,
  String code,
  String companyId,
  String areaId,
  String userId,
) {
  const stamp = '2026-08-20T12:00:00.000Z';
  db.execute(
    'INSERT INTO tickets VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, NULL, ?, 1, NULL, NULL, 0)',
    [
      id,
      code,
      id,
      'Detalle',
      'Zona',
      'medium',
      'pending',
      stamp,
      stamp,
      companyId,
      areaId,
      userId,
      'Zona',
    ],
  );
}
