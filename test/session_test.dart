import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/core/session/local_session.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/features/organization/domain/organization_models.dart';

void main() {
  final now = DateTime(2026);
  AppUser user({
    Set<String> companies = const {'company-a'},
    Set<String> areas = const {'area-a'},
  }) => AppUser(
    id: 'user-a',
    username: 'operador',
    displayName: 'Operador',
    privilege: PlatformPrivilege.user,
    companyIds: companies,
    operationalRole: AppRole.production,
    active: true,
    areaAccessMode: AreaAccessMode.selected,
    areaIds: areas,
    createdAt: now,
    updatedAt: now,
  );

  test('sesión inicia cerrada y no persiste credenciales', () async {
    final store = MemorySessionStore();
    final session = await LocalSession.load(store: store);
    expect(session.loggedIn, isFalse);
    expect(store.values.keys, isNot(contains('password')));
  });

  test('persiste identidad y contexto, no un rol seleccionable', () async {
    final store = MemorySessionStore();
    final session = await LocalSession.load(store: store);
    await session.start(user());
    await session.selectArea(companyId: 'company-a', areaId: 'area-a');

    final reloaded = await LocalSession.load(
      store: store,
      resolveUser: (id) async => id == 'user-a' ? user() : null,
    );
    expect(reloaded.user?.id, 'user-a');
    expect(reloaded.effectiveRole, AppRole.production);
    expect(reloaded.accessContext?.areaId, 'area-a');
    expect(store.values.keys.any((key) => key.contains('password')), isFalse);
  });

  test('conserva production como identificador persistido de Solicitante', () {
    expect(AppRole.production.name, 'production');
    expect(AppRole.production.label, 'Solicitante');
  });

  test('rechaza un área fuera del permiso normalizado', () async {
    final session = await LocalSession.load(store: MemorySessionStore());
    await session.start(user());
    await expectLater(
      session.selectArea(companyId: 'company-a', areaId: 'area-b'),
      throwsStateError,
    );
    await expectLater(
      session.selectArea(companyId: 'company-b', areaId: 'area-a'),
      throwsStateError,
    );
  });

  test('permite cambiar entre dos empresas asignadas', () async {
    final session = await LocalSession.load(store: MemorySessionStore());
    await session.start(
      user(
        companies: const {'company-a', 'company-b'},
        areas: const {'area-a', 'area-b'},
      ),
    );
    expect(session.selectedCompanyId, isNull);
    await session.selectArea(companyId: 'company-a', areaId: 'area-a');
    await session.selectArea(companyId: 'company-b', areaId: 'area-b');
    expect(session.selectedCompanyId, 'company-b');
    expect(session.selectedAreaId, 'area-b');
  });

  test('restauración limpia un contexto cuyo permiso fue retirado', () async {
    final store = MemorySessionStore();
    final session = await LocalSession.load(store: store);
    await session.start(
      user(
        companies: const {'company-a', 'company-b'},
        areas: const {'area-a', 'area-b'},
      ),
    );
    await session.selectArea(companyId: 'company-b', areaId: 'area-b');

    final restored = await LocalSession.load(
      store: store,
      resolveUser: (_) async => user(),
    );
    expect(restored.loggedIn, isTrue);
    expect(restored.selectedCompanyId, isNull);
    expect(restored.selectedAreaId, isNull);
  });

  test('logout elimina identidad y contexto', () async {
    final store = MemorySessionStore();
    final session = await LocalSession.load(store: store);
    await session.start(user());
    await session.selectArea(companyId: 'company-a', areaId: 'area-a');
    await session.logout();
    expect(session.loggedIn, isFalse);
    expect(session.accessContext, isNull);
    expect(store.values, isEmpty);
  });

  test(
    'limpiar contexto conserva la sesión y elimina su persistencia',
    () async {
      final store = MemorySessionStore();
      final session = await LocalSession.load(store: store);
      await session.start(user());
      await session.selectArea(companyId: 'company-a', areaId: 'area-a');

      await session.clearContext();

      expect(session.loggedIn, isTrue);
      expect(session.selectedCompanyId, isNull);
      expect(session.selectedAreaId, isNull);
      expect(store.values['session_user_id'], 'user-a');
      expect(store.values.containsKey('session_company_id'), isFalse);
      expect(store.values.containsKey('session_area_id'), isFalse);
    },
  );
}

class MemorySessionStore implements SessionStore {
  final values = <String, Object>{};
  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;
  @override
  Future<String?> getString(String key) async => values[key] as String?;
  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
}
