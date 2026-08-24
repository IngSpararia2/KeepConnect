import 'dart:async';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database_service.dart';
import '../../maintenance/domain/ticket_enums.dart';
import '../domain/organization_models.dart';
import 'organization_repository.dart';
import 'password_hasher.dart';

final class SqliteOrganizationRepository
    implements OrganizationRepository, AuthenticationRepository {
  SqliteOrganizationRepository(
    this._service, {
    AccessContext? Function()? context,
    this.hasher = const PasswordHasher(),
    this.uuid = const Uuid(),
  }) : _context = context ?? (() => AccessContext.legacy);

  final DatabaseService _service;
  final AccessContext? Function() _context;
  final PasswordHasher hasher;
  final Uuid uuid;
  final _changes = StreamController<void>.broadcast();
  Database get _db => _service.database;

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  void _requireAdmin() {
    if (_context()?.isSuperAdmin != true) {
      throw StateError(
        'Esta operación requiere una cuenta superadministradora.',
      );
    }
  }

  @override
  Stream<List<Company>> watchCompanies({bool includeInactive = true}) {
    final access = _context();
    if (access == null) {
      throw StateError('Debes iniciar sesión.');
    }
    final clauses = <String>[];
    final args = <Object?>[];
    if (!access.isSuperAdmin) {
      if (access.allowedCompanyIds.isEmpty) return Stream.value(const []);
      clauses.add(
        'id IN (${List.filled(access.allowedCompanyIds.length, '?').join(',')})',
      );
      args.addAll(access.allowedCompanyIds);
    }
    if (!includeInactive) clauses.add('active = 1');
    return _watch(
      () => _db
          .select(
            'SELECT * FROM companies ${clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}'} ORDER BY name COLLATE NOCASE',
            args,
          )
          .map(_companyFromRow)
          .toList(),
    );
  }

  @override
  Stream<List<WorkArea>> watchAreas(
    String companyId, {
    bool includeInactive = true,
  }) {
    final access = _context();
    if (access == null || !access.canAccessCompany(companyId)) {
      throw StateError('No tienes acceso a esta empresa.');
    }
    final clauses = <String>['company_id = ?'];
    final args = <Object?>[companyId];
    if (!includeInactive) {
      clauses.add('active = 1');
    }
    if (!access.isSuperAdmin && !access.allCompanyAreas) {
      if (access.allowedAreaIds.isEmpty) {
        return Stream.value(const []);
      }
      clauses.add(
        'id IN (${List.filled(access.allowedAreaIds.length, '?').join(',')})',
      );
      args.addAll(access.allowedAreaIds);
    }
    return _watch(
      () => _db
          .select(
            'SELECT * FROM work_areas WHERE ${clauses.join(' AND ')} ORDER BY name COLLATE NOCASE',
            args,
          )
          .map(_areaFromRow)
          .toList(),
    );
  }

  @override
  Stream<List<AppUser>> watchUsers() {
    _requireAdmin();
    return _watch(
      () => _db
          .select(
            "SELECT * FROM app_users WHERE username != '__legacy_import__' ORDER BY display_name COLLATE NOCASE",
          )
          .map(_userFromRow)
          .toList(),
    );
  }

  @override
  Stream<List<CatalogItem>> watchCatalog(
    String companyId,
    String areaId,
    CatalogKind kind, {
    bool includeInactive = false,
  }) {
    final access = _context();
    if (access == null || !access.permits(companyId, areaId)) {
      throw StateError('No tienes acceso a este catálogo.');
    }
    return _watch(
      () => _db
          .select(
            'SELECT * FROM catalog_items WHERE company_id = ? AND area_id = ? AND kind = ? '
            '${includeInactive ? '' : 'AND active = 1'} ORDER BY name COLLATE NOCASE',
            [companyId, areaId, kind.name],
          )
          .map(_catalogFromRow)
          .toList(),
    );
  }

  @override
  Future<Company?> getCompany(String id) async {
    final access = _context();
    if (access == null || !access.canAccessCompany(id)) {
      throw StateError('No tienes acceso a esta empresa.');
    }
    final rows = _db.select('SELECT * FROM companies WHERE id = ?', [id]);
    return rows.isEmpty ? null : _companyFromRow(rows.first);
  }

  @override
  Future<WorkArea?> getArea(String id) async {
    final rows = _db.select('SELECT * FROM work_areas WHERE id = ?', [id]);
    if (rows.isEmpty) {
      return null;
    }
    final area = _areaFromRow(rows.first);
    final access = _context();
    if (access == null || !access.canAccessArea(area.companyId, area.id)) {
      throw StateError('No tienes acceso a esta área.');
    }
    return area;
  }

  @override
  Future<AppUser?> getUser(String id) async {
    _requireAdmin();
    return findUser(id);
  }

  @override
  Future<void> saveCompany(Company company) async {
    _requireAdmin();
    final name = company.name.trim();
    if (name.isEmpty) {
      throw ArgumentError('El nombre de la empresa es obligatorio.');
    }
    _db.execute(
      'INSERT INTO companies(id, name, active, created_at, updated_at) VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET name = excluded.name, active = excluded.active, updated_at = excluded.updated_at',
      [
        company.id,
        name,
        company.active ? 1 : 0,
        _date(company.createdAt),
        _date(company.updatedAt),
      ],
    );
    _changed();
  }

  @override
  Future<void> saveArea(WorkArea area) async {
    _requireAdmin();
    if (await getCompany(area.companyId) == null) {
      throw StateError('La empresa no existe.');
    }
    final name = area.name.trim();
    if (name.isEmpty) {
      throw ArgumentError('El nombre del área es obligatorio.');
    }
    _db.execute(
      'INSERT INTO work_areas(id, company_id, name, active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET name = excluded.name, active = excluded.active, updated_at = excluded.updated_at',
      [
        area.id,
        area.companyId,
        name,
        area.active ? 1 : 0,
        _date(area.createdAt),
        _date(area.updatedAt),
      ],
    );
    _changed();
  }

  @override
  Future<void> saveUser(AppUser user, {String? newPassword}) async {
    _requireAdmin();
    final existingHash = _passwordHash(user.id);
    _validateUser(
      user,
      needsPassword: existingHash == null && newPassword == null,
    );
    final hash = newPassword == null ? existingHash : hasher.hash(newPassword);
    _transaction(() {
      _db.execute(
        'INSERT INTO app_users(id, username, display_name, privilege, company_id, operational_role, active, '
        'area_access_mode, password_hash, created_at, updated_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET username = excluded.username, display_name = excluded.display_name, '
        'privilege = excluded.privilege, company_id = excluded.company_id, operational_role = excluded.operational_role, '
        'active = excluded.active, area_access_mode = excluded.area_access_mode, password_hash = excluded.password_hash, '
        'updated_at = excluded.updated_at',
        [
          user.id,
          user.username.trim(),
          user.displayName.trim(),
          user.privilege.name,
          user.isSuperAdmin || user.companyIds.isEmpty
              ? null
              : (user.companyIds.toList()..sort()).first,
          user.isSuperAdmin ? null : user.operationalRole?.name,
          user.active ? 1 : 0,
          user.areaAccessMode.name,
          hash,
          _date(user.createdAt),
          _date(user.updatedAt),
          user.lastSeenAt == null ? null : _date(user.lastSeenAt!),
        ],
      );
      _db.execute('DELETE FROM user_area_permissions WHERE user_id = ?', [
        user.id,
      ]);
      _db.execute('DELETE FROM user_company_permissions WHERE user_id = ?', [
        user.id,
      ]);
      if (!user.isSuperAdmin) {
        for (final companyId in user.companyIds) {
          _db.execute(
            'INSERT INTO user_company_permissions(user_id, company_id) VALUES (?, ?)',
            [user.id, companyId],
          );
        }
      }
      if (!user.isSuperAdmin &&
          user.areaAccessMode == AreaAccessMode.selected) {
        for (final areaId in user.areaIds) {
          final rows = _db.select(
            'SELECT company_id FROM work_areas WHERE id = ?',
            [areaId],
          );
          if (rows.isEmpty ||
              !user.companyIds.contains(rows.first['company_id'])) {
            throw ArgumentError(
              'Todas las áreas deben pertenecer a una empresa asignada.',
            );
          }
          _db.execute('INSERT INTO user_area_permissions VALUES (?, ?)', [
            user.id,
            areaId,
          ]);
        }
      }
    });
    _changed();
  }

  @override
  Future<void> resetPassword(String userId, String newPassword) async {
    _requireAdmin();
    if (await findUser(userId) == null) {
      throw StateError('El usuario no existe.');
    }
    _db.execute(
      'UPDATE app_users SET password_hash = ?, updated_at = ? WHERE id = ?',
      [hasher.hash(newPassword), _date(DateTime.now()), userId],
    );
    _changed();
  }

  @override
  Future<void> saveCatalogItem(CatalogItem item) async {
    _requireAdmin();
    final name = item.name.trim();
    if (name.isEmpty || name.toLowerCase() == 'otra') {
      throw ArgumentError(
        'Escribe un nombre válido; “Otra” es una opción reservada.',
      );
    }
    final area = await getArea(item.areaId);
    if (area == null || area.companyId != item.companyId) {
      throw ArgumentError('El área no pertenece a la empresa indicada.');
    }
    _db.execute(
      'INSERT INTO catalog_items(id, company_id, area_id, kind, name, active, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, '
      'active = excluded.active, updated_at = excluded.updated_at',
      [
        item.id,
        item.companyId,
        item.areaId,
        item.kind.name,
        name,
        item.active ? 1 : 0,
        _date(item.createdAt),
        _date(item.updatedAt),
      ],
    );
    _changed();
  }

  @override
  Future<bool> needsBootstrap() async =>
      (_db
              .select(
                "SELECT COUNT(*) AS count FROM app_users WHERE privilege = 'superAdmin'",
              )
              .first['count']
          as int) ==
      0;

  @override
  Future<AppUser> bootstrapOwner({
    required String username,
    required String displayName,
    required String password,
  }) async {
    if (!await needsBootstrap()) {
      throw StateError('La cuenta propietaria inicial ya fue creada.');
    }
    final cleanUsername = username.trim();
    final cleanName = displayName.trim();
    if (cleanUsername.isEmpty || cleanName.isEmpty) {
      throw ArgumentError('Nombre y usuario son obligatorios.');
    }
    final now = DateTime.now();
    final user = AppUser(
      id: uuid.v4(),
      username: cleanUsername,
      displayName: cleanName,
      privilege: PlatformPrivilege.superAdmin,
      companyIds: const {},
      active: true,
      areaAccessMode: AreaAccessMode.all,
      areaIds: const {},
      createdAt: now,
      updatedAt: now,
    );
    _db.execute(
      'INSERT INTO app_users(id, username, display_name, privilege, company_id, operational_role, active, '
      'area_access_mode, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, NULL, NULL, 1, ?, ?, ?, ?)',
      [
        user.id,
        user.username,
        user.displayName,
        user.privilege.name,
        user.areaAccessMode.name,
        hasher.hash(password),
        _date(now),
        _date(now),
      ],
    );
    _changed();
    return user;
  }

  @override
  Future<AppUser> authenticate(String username, String password) async {
    final rows = _db.select(
      'SELECT * FROM app_users WHERE lower(trim(username)) = lower(trim(?))',
      [username],
    );
    if (rows.isEmpty ||
        rows.first['password_hash'] == null ||
        !hasher.verify(password, rows.first['password_hash'] as String)) {
      throw StateError('Usuario o contraseña incorrectos.');
    }
    final user = _userFromRow(rows.first);
    if (!user.active) {
      throw StateError('Esta cuenta está deshabilitada.');
    }
    if (!user.isSuperAdmin) {
      final companies = _db.select(
        'SELECT c.active FROM companies c '
        'INNER JOIN user_company_permissions p ON p.company_id = c.id '
        'WHERE p.user_id = ? AND c.active = 1',
        [user.id],
      );
      if (companies.isEmpty) {
        throw StateError('Las empresas de esta cuenta están deshabilitadas.');
      }
    }
    await recordActivity(user.id);
    return (await findUser(user.id))!;
  }

  @override
  Future<AppUser?> findUser(String id) async {
    final rows = _db.select('SELECT * FROM app_users WHERE id = ?', [id]);
    return rows.isEmpty ? null : _userFromRow(rows.first);
  }

  @override
  Future<void> recordActivity(String userId) async {
    _db.execute('UPDATE app_users SET last_seen_at = ? WHERE id = ?', [
      _date(DateTime.now()),
      userId,
    ]);
  }

  @override
  Future<bool> isContextAvailable(
    AppUser user,
    String companyId,
    String areaId,
  ) async {
    if (!user.canAccessArea(companyId, areaId)) return false;
    final rows = _db.select(
      'SELECT 1 FROM work_areas a INNER JOIN companies c ON c.id = a.company_id '
      'WHERE a.id = ? AND a.company_id = ? AND a.active = 1 AND c.active = 1',
      [areaId, companyId],
    );
    return rows.isNotEmpty;
  }

  void _validateUser(AppUser user, {required bool needsPassword}) {
    if (user.username.trim().isEmpty || user.displayName.trim().isEmpty) {
      throw ArgumentError('Nombre y usuario son obligatorios.');
    }
    if (needsPassword) {
      throw ArgumentError('Define una contraseña inicial.');
    }
    if (!user.isSuperAdmin) {
      if (user.companyIds.isEmpty || user.operationalRole == null) {
        throw ArgumentError('Empresa(s) y rol operativo son obligatorios.');
      }
      if (user.areaAccessMode == AreaAccessMode.selected &&
          user.areaIds.isEmpty) {
        throw ArgumentError('Selecciona al menos un área.');
      }
      final companies = _db.select(
        'SELECT id FROM companies WHERE id IN (${List.filled(user.companyIds.length, '?').join(',')})',
        user.companyIds.toList(),
      );
      if (companies.length != user.companyIds.length) {
        throw ArgumentError('Una de las empresas asignadas no existe.');
      }
      if (user.areaAccessMode == AreaAccessMode.selected) {
        final areas = _db.select(
          'SELECT id, company_id FROM work_areas WHERE id IN (${List.filled(user.areaIds.length, '?').join(',')})',
          user.areaIds.toList(),
        );
        if (areas.length != user.areaIds.length ||
            areas.any((row) => !user.companyIds.contains(row['company_id']))) {
          throw ArgumentError(
            'Todas las áreas deben pertenecer a una empresa asignada.',
          );
        }
        final coveredCompanies = areas
            .map((row) => row['company_id'] as String)
            .toSet();
        if (!coveredCompanies.containsAll(user.companyIds)) {
          throw ArgumentError(
            'Selecciona al menos un área de cada empresa asignada.',
          );
        }
      }
    }
  }

  String? _passwordHash(String id) {
    final rows = _db.select(
      'SELECT password_hash FROM app_users WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : rows.first['password_hash'] as String?;
  }

  Company _companyFromRow(Row row) => Company(
    id: row['id'] as String,
    name: row['name'] as String,
    active: row['active'] == 1,
    createdAt: _parse(row['created_at']),
    updatedAt: _parse(row['updated_at']),
  );
  WorkArea _areaFromRow(Row row) => WorkArea(
    id: row['id'] as String,
    companyId: row['company_id'] as String,
    name: row['name'] as String,
    active: row['active'] == 1,
    createdAt: _parse(row['created_at']),
    updatedAt: _parse(row['updated_at']),
  );
  AppUser _userFromRow(Row row) {
    final id = row['id'] as String;
    return AppUser(
      id: id,
      username: row['username'] as String,
      displayName: row['display_name'] as String,
      privilege: PlatformPrivilege.values.byName(row['privilege'] as String),
      companyIds: _db
          .select(
            'SELECT company_id FROM user_company_permissions WHERE user_id = ?',
            [id],
          )
          .map((r) => r['company_id'] as String)
          .toSet(),
      operationalRole: row['operational_role'] == null
          ? null
          : AppRole.values.byName(row['operational_role'] as String),
      active: row['active'] == 1,
      areaAccessMode: AreaAccessMode.values.byName(
        row['area_access_mode'] as String,
      ),
      areaIds: _db
          .select(
            'SELECT area_id FROM user_area_permissions WHERE user_id = ?',
            [id],
          )
          .map((r) => r['area_id'] as String)
          .toSet(),
      createdAt: _parse(row['created_at']),
      updatedAt: _parse(row['updated_at']),
      lastSeenAt: row['last_seen_at'] == null
          ? null
          : _parse(row['last_seen_at']),
    );
  }

  CatalogItem _catalogFromRow(Row row) => CatalogItem(
    id: row['id'] as String,
    companyId: row['company_id'] as String,
    areaId: row['area_id'] as String,
    kind: CatalogKind.values.byName(row['kind'] as String),
    name: row['name'] as String,
    active: row['active'] == 1,
    createdAt: _parse(row['created_at']),
    updatedAt: _parse(row['updated_at']),
  );

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

  String _date(DateTime value) => value.toUtc().toIso8601String();
  DateTime _parse(Object? value) => DateTime.parse(value as String).toLocal();
  void _changed() => _changes.add(null);
  @override
  Future<void> close() => _changes.close();
}
