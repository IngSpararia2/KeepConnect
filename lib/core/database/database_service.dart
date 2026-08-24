import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

final class DatabaseService {
  DatabaseService._(this.database);

  static const schemaVersion = 4;
  static const legacyCompanyId = 'legacy-company';
  static const legacyPlantAreaId = 'legacy-area-plant';
  static const legacyUserId = 'legacy-system-user';

  final Database database;

  static Future<DatabaseService> open() async {
    final directory = await getApplicationDocumentsDirectory();
    return DatabaseService.fromPath(p.join(directory.path, 'keepconnect.db'));
  }

  factory DatabaseService.fromPath(String path) {
    final existed = File(path).existsSync();
    final service = DatabaseService._(sqlite3.open(path));
    service._migrate(existingFile: existed);
    return service;
  }

  factory DatabaseService.inMemory({bool seedLegacyContext = true}) {
    final service = DatabaseService._(sqlite3.openInMemory());
    service._migrate(existingFile: false);
    if (seedLegacyContext) service.seedLegacyContext();
    return service;
  }

  int get version => database.userVersion;

  void _migrate({required bool existingFile}) {
    database.execute('PRAGMA foreign_keys = ON');
    final hasLegacySchema = _hasTable('tickets');
    final current = database.userVersion;
    if (current > schemaVersion) {
      throw StateError(
        'La base de datos requiere una versión más nueva de KeepConnect.',
      );
    }
    if (!hasLegacySchema && current == 0) {
      _transaction(() {
        _createLatestSchema();
        database.userVersion = schemaVersion;
      });
      return;
    }
    if (current < 1) database.userVersion = 1;
    if (database.userVersion < 2) _migrateLegacyToMultiTenant();
    if (database.userVersion < 3) _migrateUsersToMultipleCompanies();
    if (database.userVersion < 4) _migrateToPersonalNotifications();
  }

  void _migrateToPersonalNotifications() {
    final foreignKeys =
        database.select('PRAGMA foreign_keys').single['foreign_keys'] as int;
    database.execute('PRAGMA foreign_keys = OFF');
    try {
      _transaction(() {
        database.execute('''
          DROP TRIGGER IF EXISTS notifications_ticket_scope_insert;
          DROP TRIGGER IF EXISTS notifications_ticket_scope_update;
          CREATE TABLE tickets_v4 (
            id TEXT PRIMARY KEY,
            human_code TEXT NOT NULL,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            location TEXT NOT NULL,
            equipment TEXT,
            priority TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            company_id TEXT NOT NULL REFERENCES companies(id),
            area_id TEXT NOT NULL REFERENCES work_areas(id),
            created_by_user_id TEXT NOT NULL REFERENCES app_users(id),
            location_option_id TEXT REFERENCES catalog_items(id),
            location_snapshot TEXT NOT NULL,
            location_is_custom INTEGER NOT NULL DEFAULT 0,
            equipment_option_id TEXT REFERENCES catalog_items(id),
            equipment_snapshot TEXT,
            equipment_is_custom INTEGER NOT NULL DEFAULT 0
          );
          INSERT INTO tickets_v4(
            id, human_code, title, description, location, equipment, priority,
            status, created_at, updated_at, company_id, area_id,
            created_by_user_id, location_option_id, location_snapshot,
            location_is_custom, equipment_option_id, equipment_snapshot,
            equipment_is_custom)
          SELECT
            id, human_code, title, description, location, equipment, priority,
            status, created_at, updated_at, company_id, area_id,
            created_by_user_id, location_option_id, location_snapshot,
            location_is_custom, equipment_option_id, equipment_snapshot,
            equipment_is_custom
          FROM tickets;
          DROP TABLE tickets;
          ALTER TABLE tickets_v4 RENAME TO tickets;
        ''');
        _fanOutLegacyNotifications();
        _createIndexesAndGuards();
        final violations = database.select('PRAGMA foreign_key_check');
        if (violations.isNotEmpty) {
          throw StateError('La migración v4 detectó relaciones inválidas.');
        }
        database.userVersion = 4;
      });
    } finally {
      database.execute('PRAGMA foreign_keys = $foreignKeys');
    }
  }

  void _fanOutLegacyNotifications() {
    database.execute('''
      INSERT INTO app_notifications(
        id, ticket_id, title, message, recipient, event_type, is_read,
        created_at, company_id, area_id, recipient_user_id)
      SELECT
        lower(hex(randomblob(16))), n.ticket_id, n.title, n.message,
        n.recipient, n.event_type, n.is_read, n.created_at,
        n.company_id, n.area_id, u.id
      FROM app_notifications n
      INNER JOIN app_users u
        ON u.privilege = 'user'
        AND u.active = 1
        AND u.operational_role = n.recipient
      INNER JOIN user_company_permissions company_permission
        ON company_permission.user_id = u.id
        AND company_permission.company_id = n.company_id
      INNER JOIN companies company
        ON company.id = n.company_id AND company.active = 1
      INNER JOIN work_areas area
        ON area.id = n.area_id
        AND area.company_id = n.company_id
        AND area.active = 1
      WHERE n.recipient_user_id IS NULL
        AND (
          u.area_access_mode = 'all'
          OR EXISTS (
            SELECT 1 FROM user_area_permissions area_permission
            WHERE area_permission.user_id = u.id
              AND area_permission.area_id = n.area_id
          )
        )
    ''');
  }

  void _migrateUsersToMultipleCompanies() {
    _transaction(() {
      _createUserCompanyPermissions();
      database.execute('''
        INSERT OR IGNORE INTO user_company_permissions(user_id, company_id)
        SELECT id, company_id FROM app_users WHERE company_id IS NOT NULL
      ''');
      database.userVersion = 3;
    });
  }

  void _migrateLegacyToMultiTenant() {
    _transaction(() {
      _createOrganizationTables();
      seedLegacyContext();
      _addColumnIfMissing('tickets', 'company_id', 'TEXT');
      _addColumnIfMissing('tickets', 'area_id', 'TEXT');
      _addColumnIfMissing('tickets', 'created_by_user_id', 'TEXT');
      _addColumnIfMissing('tickets', 'location_option_id', 'TEXT');
      _addColumnIfMissing('tickets', 'location_snapshot', 'TEXT');
      _addColumnIfMissing(
        'tickets',
        'location_is_custom',
        'INTEGER NOT NULL DEFAULT 1',
      );
      _addColumnIfMissing('tickets', 'equipment_option_id', 'TEXT');
      _addColumnIfMissing('tickets', 'equipment_snapshot', 'TEXT');
      _addColumnIfMissing(
        'tickets',
        'equipment_is_custom',
        'INTEGER NOT NULL DEFAULT 0',
      );
      database.execute('''
        UPDATE tickets SET
          company_id = COALESCE(company_id, '$legacyCompanyId'),
          area_id = COALESCE(area_id, '$legacyPlantAreaId'),
          created_by_user_id = COALESCE(created_by_user_id, '$legacyUserId'),
          location_snapshot = COALESCE(location_snapshot, location),
          location_is_custom = CASE WHEN location_option_id IS NULL THEN 1 ELSE 0 END,
          equipment_snapshot = COALESCE(equipment_snapshot, equipment),
          equipment_is_custom = CASE
            WHEN equipment IS NULL OR equipment = '' THEN 0
            WHEN equipment_option_id IS NULL THEN 1 ELSE 0 END
      ''');
      for (final table in ['ticket_updates', 'ticket_events']) {
        _addColumnIfMissing(table, 'actor_user_id', 'TEXT');
        database.execute(
          "UPDATE $table SET actor_user_id = COALESCE(actor_user_id, '$legacyUserId')",
        );
      }
      _addColumnIfMissing('app_notifications', 'company_id', 'TEXT');
      _addColumnIfMissing('app_notifications', 'area_id', 'TEXT');
      _addColumnIfMissing('app_notifications', 'recipient_user_id', 'TEXT');
      database.execute('''
        UPDATE app_notifications SET
          company_id = COALESCE(company_id, '$legacyCompanyId'),
          area_id = COALESCE(area_id, '$legacyPlantAreaId')
      ''');
      _addColumnIfMissing('form_templates', 'company_id', 'TEXT');
      _addColumnIfMissing('form_templates', 'area_id', 'TEXT');
      database.execute('''
        UPDATE form_templates SET
          company_id = COALESCE(company_id, '$legacyCompanyId'),
          area_id = COALESCE(area_id, '$legacyPlantAreaId')
      ''');
      _createIndexesAndGuards();
      database.userVersion = 2;
    });
  }

  void _createLatestSchema() {
    _createOrganizationTables();
    database.execute('''
      CREATE TABLE tickets (
        id TEXT PRIMARY KEY,
        human_code TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        location TEXT NOT NULL,
        equipment TEXT,
        priority TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        company_id TEXT NOT NULL REFERENCES companies(id),
        area_id TEXT NOT NULL REFERENCES work_areas(id),
        created_by_user_id TEXT NOT NULL REFERENCES app_users(id),
        location_option_id TEXT REFERENCES catalog_items(id),
        location_snapshot TEXT NOT NULL,
        location_is_custom INTEGER NOT NULL DEFAULT 0,
        equipment_option_id TEXT REFERENCES catalog_items(id),
        equipment_snapshot TEXT,
        equipment_is_custom INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE ticket_questions (
        id TEXT PRIMARY KEY,
        ticket_id TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
        prompt TEXT NOT NULL,
        type TEXT NOT NULL,
        required INTEGER NOT NULL,
        sort_order INTEGER NOT NULL
      );
      CREATE TABLE question_options (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id TEXT NOT NULL REFERENCES ticket_questions(id) ON DELETE CASCADE,
        value TEXT NOT NULL,
        sort_order INTEGER NOT NULL
      );
      CREATE TABLE ticket_answers (
        question_id TEXT PRIMARY KEY REFERENCES ticket_questions(id) ON DELETE CASCADE,
        selected_values TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE TABLE ticket_updates (
        id TEXT PRIMARY KEY,
        ticket_id TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
        actor TEXT NOT NULL,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        actor_user_id TEXT REFERENCES app_users(id)
      );
      CREATE TABLE ticket_events (
        id TEXT PRIMARY KEY,
        ticket_id TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
        actor TEXT NOT NULL,
        type TEXT NOT NULL,
        message TEXT NOT NULL,
        created_at TEXT NOT NULL,
        actor_user_id TEXT REFERENCES app_users(id)
      );
      CREATE TABLE app_notifications (
        id TEXT PRIMARY KEY,
        ticket_id TEXT NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        recipient TEXT NOT NULL,
        event_type TEXT NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        company_id TEXT NOT NULL REFERENCES companies(id),
        area_id TEXT NOT NULL REFERENCES work_areas(id),
        recipient_user_id TEXT REFERENCES app_users(id)
      );
      CREATE TABLE form_templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        company_id TEXT NOT NULL REFERENCES companies(id),
        area_id TEXT REFERENCES work_areas(id)
      );
      CREATE TABLE form_template_questions (
        id TEXT PRIMARY KEY,
        template_id TEXT NOT NULL REFERENCES form_templates(id) ON DELETE CASCADE,
        prompt TEXT NOT NULL,
        type TEXT NOT NULL,
        required INTEGER NOT NULL,
        sort_order INTEGER NOT NULL
      );
      CREATE TABLE form_template_question_options (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id TEXT NOT NULL REFERENCES form_template_questions(id) ON DELETE CASCADE,
        value TEXT NOT NULL,
        sort_order INTEGER NOT NULL
      );
    ''');
    _createIndexesAndGuards();
  }

  void _createOrganizationTables() {
    database.execute('''
      CREATE TABLE IF NOT EXISTS companies (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL COLLATE NOCASE,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE UNIQUE INDEX IF NOT EXISTS companies_name_unique
        ON companies(lower(trim(name)));
      CREATE TABLE IF NOT EXISTS work_areas (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id),
        name TEXT NOT NULL COLLATE NOCASE,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE UNIQUE INDEX IF NOT EXISTS work_areas_name_unique
        ON work_areas(company_id, lower(trim(name)));
      CREATE TABLE IF NOT EXISTS app_users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL COLLATE NOCASE,
        display_name TEXT NOT NULL,
        privilege TEXT NOT NULL,
        company_id TEXT REFERENCES companies(id),
        operational_role TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        area_access_mode TEXT NOT NULL DEFAULT 'selected',
        password_hash TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_seen_at TEXT
      );
      CREATE UNIQUE INDEX IF NOT EXISTS app_users_username_unique
        ON app_users(lower(trim(username)));
    ''');
    _createUserCompanyPermissions();
    database.execute('''
      CREATE TABLE IF NOT EXISTS user_area_permissions (
        user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
        area_id TEXT NOT NULL REFERENCES work_areas(id) ON DELETE CASCADE,
        PRIMARY KEY(user_id, area_id)
      );
      CREATE TABLE IF NOT EXISTS catalog_items (
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id),
        area_id TEXT NOT NULL REFERENCES work_areas(id),
        kind TEXT NOT NULL,
        name TEXT NOT NULL COLLATE NOCASE,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE UNIQUE INDEX IF NOT EXISTS catalog_items_name_unique
        ON catalog_items(company_id, area_id, kind, lower(trim(name)));
    ''');
  }

  void _createUserCompanyPermissions() {
    database.execute('''
      CREATE TABLE IF NOT EXISTS user_company_permissions (
        user_id TEXT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
        PRIMARY KEY(user_id, company_id)
      );
      CREATE INDEX IF NOT EXISTS user_company_permissions_company_index
        ON user_company_permissions(company_id);
    ''');
  }

  void _createIndexesAndGuards() {
    database.execute('''
      CREATE INDEX IF NOT EXISTS tickets_scope_index
        ON tickets(company_id, area_id, updated_at);
      CREATE UNIQUE INDEX IF NOT EXISTS tickets_company_code_unique
        ON tickets(company_id, human_code);
      CREATE INDEX IF NOT EXISTS notifications_scope_index
        ON app_notifications(company_id, area_id, recipient, is_read);
      CREATE INDEX IF NOT EXISTS notifications_personal_inbox_index
        ON app_notifications(
          recipient_user_id, company_id, area_id, recipient, is_read, created_at
        );
      CREATE INDEX IF NOT EXISTS templates_scope_index
        ON form_templates(company_id, area_id);
      CREATE TRIGGER IF NOT EXISTS tickets_scope_required_insert
      BEFORE INSERT ON tickets
      WHEN NEW.company_id IS NULL OR NEW.area_id IS NULL OR NEW.created_by_user_id IS NULL
      BEGIN SELECT RAISE(ABORT, 'ticket scope is required'); END;
      CREATE TRIGGER IF NOT EXISTS tickets_scope_required_update
      BEFORE UPDATE OF company_id, area_id, created_by_user_id ON tickets
      WHEN NEW.company_id IS NULL OR NEW.area_id IS NULL OR NEW.created_by_user_id IS NULL
      BEGIN SELECT RAISE(ABORT, 'ticket scope is required'); END;
      CREATE TRIGGER IF NOT EXISTS tickets_company_area_insert
      BEFORE INSERT ON tickets
      WHEN NOT EXISTS (
        SELECT 1 FROM work_areas area
        WHERE area.id = NEW.area_id AND area.company_id = NEW.company_id
      )
      BEGIN SELECT RAISE(ABORT, 'ticket area does not belong to company'); END;
      CREATE TRIGGER IF NOT EXISTS tickets_company_area_update
      BEFORE UPDATE OF company_id, area_id ON tickets
      WHEN NOT EXISTS (
        SELECT 1 FROM work_areas area
        WHERE area.id = NEW.area_id AND area.company_id = NEW.company_id
      )
      BEGIN SELECT RAISE(ABORT, 'ticket area does not belong to company'); END;
      CREATE TRIGGER IF NOT EXISTS notifications_personal_insert
      BEFORE INSERT ON app_notifications
      WHEN NEW.recipient_user_id IS NULL
      BEGIN SELECT RAISE(ABORT, 'notification recipient user is required'); END;
      CREATE TRIGGER IF NOT EXISTS notifications_ticket_scope_insert
      BEFORE INSERT ON app_notifications
      WHEN NOT EXISTS (
        SELECT 1 FROM tickets ticket
        WHERE ticket.id = NEW.ticket_id
          AND ticket.company_id = NEW.company_id
          AND ticket.area_id = NEW.area_id
      )
      BEGIN SELECT RAISE(ABORT, 'notification scope does not match ticket'); END;
      CREATE TRIGGER IF NOT EXISTS notifications_ticket_scope_update
      BEFORE UPDATE OF ticket_id, company_id, area_id ON app_notifications
      WHEN NOT EXISTS (
        SELECT 1 FROM tickets ticket
        WHERE ticket.id = NEW.ticket_id
          AND ticket.company_id = NEW.company_id
          AND ticket.area_id = NEW.area_id
      )
      BEGIN SELECT RAISE(ABORT, 'notification scope does not match ticket'); END;
      CREATE TRIGGER IF NOT EXISTS notifications_recipient_insert
      BEFORE INSERT ON app_notifications
      WHEN NEW.recipient_user_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM app_users user
        INNER JOIN user_company_permissions company_permission
          ON company_permission.user_id = user.id
          AND company_permission.company_id = NEW.company_id
        INNER JOIN companies company
          ON company.id = NEW.company_id AND company.active = 1
        INNER JOIN work_areas area
          ON area.id = NEW.area_id
          AND area.company_id = NEW.company_id
          AND area.active = 1
        WHERE user.id = NEW.recipient_user_id
          AND user.privilege = 'user'
          AND user.active = 1
          AND user.operational_role = NEW.recipient
          AND (
            user.area_access_mode = 'all'
            OR EXISTS (
              SELECT 1 FROM user_area_permissions area_permission
              WHERE area_permission.user_id = user.id
                AND area_permission.area_id = NEW.area_id
            )
          )
      )
      BEGIN SELECT RAISE(ABORT, 'notification recipient is not eligible'); END;
      CREATE TRIGGER IF NOT EXISTS notifications_recipient_update
      BEFORE UPDATE OF recipient_user_id, recipient, company_id, area_id
      ON app_notifications
      WHEN NEW.recipient_user_id IS NULL OR NOT EXISTS (
        SELECT 1
        FROM app_users user
        INNER JOIN user_company_permissions company_permission
          ON company_permission.user_id = user.id
          AND company_permission.company_id = NEW.company_id
        INNER JOIN work_areas area
          ON area.id = NEW.area_id AND area.company_id = NEW.company_id
        WHERE user.id = NEW.recipient_user_id
          AND user.privilege = 'user'
          AND user.operational_role = NEW.recipient
          AND (
            user.area_access_mode = 'all'
            OR EXISTS (
              SELECT 1 FROM user_area_permissions area_permission
              WHERE area_permission.user_id = user.id
                AND area_permission.area_id = NEW.area_id
            )
          )
      )
      BEGIN SELECT RAISE(ABORT, 'notification recipient is invalid'); END;
      CREATE TRIGGER IF NOT EXISTS user_area_company_insert
      BEFORE INSERT ON user_area_permissions
      WHEN NOT EXISTS (
        SELECT 1
        FROM work_areas area
        INNER JOIN user_company_permissions company_permission
          ON company_permission.user_id = NEW.user_id
          AND company_permission.company_id = area.company_id
        WHERE area.id = NEW.area_id
      )
      BEGIN SELECT RAISE(ABORT, 'area permission requires company permission'); END;
      CREATE TRIGGER IF NOT EXISTS user_area_company_update
      BEFORE UPDATE OF user_id, area_id ON user_area_permissions
      WHEN NOT EXISTS (
        SELECT 1
        FROM work_areas area
        INNER JOIN user_company_permissions company_permission
          ON company_permission.user_id = NEW.user_id
          AND company_permission.company_id = area.company_id
        WHERE area.id = NEW.area_id
      )
      BEGIN SELECT RAISE(ABORT, 'area permission requires company permission'); END;
    ''');
  }

  void seedLegacyContext() {
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute('INSERT OR IGNORE INTO companies VALUES (?, ?, 1, ?, ?)', [
      legacyCompanyId,
      'PRECONCRETOS S.A.',
      now,
      now,
    ]);
    for (final entry in const [
      ('legacy-area-plant', 'Planta'),
      ('legacy-area-crushing', 'Trituración'),
      ('legacy-area-admin', 'Administración'),
    ]) {
      database.execute(
        'INSERT OR IGNORE INTO work_areas VALUES (?, ?, ?, 1, ?, ?)',
        [entry.$1, legacyCompanyId, entry.$2, now, now],
      );
    }
    database.execute(
      'INSERT OR IGNORE INTO app_users '
      '(id, username, display_name, privilege, company_id, operational_role, active, '
      'area_access_mode, password_hash, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, 0, ?, NULL, ?, ?)',
      [
        legacyUserId,
        '__legacy_import__',
        'Importación histórica',
        'user',
        legacyCompanyId,
        'production',
        'all',
        now,
        now,
      ],
    );
    database.execute(
      'INSERT OR IGNORE INTO user_company_permissions(user_id, company_id) VALUES (?, ?)',
      [legacyUserId, legacyCompanyId],
    );
  }

  bool _hasTable(String name) => database.select(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
    [name],
  ).isNotEmpty;

  void _addColumnIfMissing(String table, String column, String definition) {
    final exists = database
        .select('PRAGMA table_info($table)')
        .any((row) => row['name'] == column);
    if (!exists) {
      database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  void _transaction(void Function() operation) {
    database.execute('BEGIN IMMEDIATE');
    try {
      operation();
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => database.dispose();
}
