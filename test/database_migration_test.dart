import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/core/database/database_service.dart';
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
}
