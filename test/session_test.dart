import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/core/database/database_service.dart';
import 'package:gestion_interna/core/notifications/notification_service.dart';
import 'package:gestion_interna/core/session/local_session.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_maintenance_repository.dart';
import 'package:gestion_interna/features/maintenance/domain/create_ticket_input.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';

void main() {
  test('sesión inicia cerrada', () async {
    final session = await LocalSession.load(store: MemorySessionStore());
    expect(session.loggedIn, isFalse);
    expect(session.accountRole, isNull);
  });

  for (final accountRole in AccountRole.values) {
    test(
      'login ${accountRole.label} persiste y resuelve effectiveRole',
      () async {
        final store = MemorySessionStore();
        final session = await LocalSession.load(store: store);
        await session.login(accountRole);
        final reloaded = await LocalSession.load(store: store);
        expect(reloaded.loggedIn, isTrue);
        expect(reloaded.accountRole, accountRole);
        expect(
          reloaded.effectiveRole,
          accountRole == AccountRole.maintenance
              ? AppRole.maintenance
              : AppRole.production,
        );
      },
    );
  }

  test('solo Administrador puede cambiar effectiveRole', () async {
    final normal = await LocalSession.load(store: MemorySessionStore());
    await normal.login(AccountRole.production);
    await expectLater(
      normal.setEffectiveRole(AppRole.maintenance),
      throwsStateError,
    );
    expect(normal.effectiveRole, AppRole.production);

    final adminStore = MemorySessionStore();
    final admin = await LocalSession.load(store: adminStore);
    await admin.login(AccountRole.administrator);
    await admin.setEffectiveRole(AppRole.maintenance);
    expect(admin.effectiveRole, AppRole.maintenance);
    expect(
      (await LocalSession.load(store: adminStore)).effectiveRole,
      AppRole.maintenance,
    );
  });

  test('logout termina sesión sin tocar SQLite', () async {
    final store = MemorySessionStore();
    final session = await LocalSession.load(store: store);
    await session.login(AccountRole.production);
    final repository = SqliteMaintenanceRepository(
      DatabaseService.inMemory(),
      notificationGateway: const NoopNotificationGateway(),
    );
    final created = await repository.createTicket(
      const CreateTicketInput(
        title: 'Persistente',
        description: 'No borrar',
        location: 'Planta',
        priority: TicketPriority.medium,
      ),
    );
    await session.logout();
    expect(session.loggedIn, isFalse);
    expect(session.accountRole, isNull);
    expect(await repository.watchTicket(created.ticketId).first, isNotNull);
    await repository.close();
  });
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
