import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/app/app_providers.dart';
import 'package:gestion_interna/app/router.dart';
import 'package:gestion_interna/core/database/database_service.dart';
import 'package:gestion_interna/core/notifications/notification_service.dart';
import 'package:gestion_interna/core/session/local_session.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_maintenance_repository.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/features/organization/data/password_hasher.dart';
import 'package:gestion_interna/features/organization/data/sqlite_organization_repository.dart';
import 'package:gestion_interna/features/organization/domain/organization_models.dart';

void main() {
  testWidgets('primera instalación abre bootstrap, sin selector de rol', (
    tester,
  ) async {
    final database = DatabaseService.inMemory(seedLegacyContext: false);
    final session = await LocalSession.load(store: _MemorySessionStore());
    final organizations = SqliteOrganizationRepository(
      database,
      hasher: const PasswordHasher(iterations: 10000),
    );
    final container = ProviderContainer(
      overrides: [
        localSessionProvider.overrideWithValue(session),
        organizationRepositoryProvider.overrideWithValue(organizations),
        authenticationRepositoryProvider.overrideWithValue(organizations),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await organizations.close();
      database.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: container.read(appRouterProvider),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bootstrap-submit')), findsOneWidget);
    expect(find.byKey(const Key('account-role')), findsNothing);
  });

  testWidgets('usuario regular no accede por URL a administración', (
    tester,
  ) async {
    final database = DatabaseService.inMemory();
    final session = await LocalSession.load(store: _MemorySessionStore());
    final now = DateTime(2026);
    await session.start(
      AppUser(
        id: 'regular',
        username: 'regular',
        displayName: 'Regular',
        privilege: PlatformPrivilege.user,
        companyIds: const {DatabaseService.legacyCompanyId},
        operationalRole: AppRole.production,
        active: true,
        areaAccessMode: AreaAccessMode.selected,
        areaIds: const {DatabaseService.legacyPlantAreaId},
        createdAt: now,
        updatedAt: now,
      ),
    );
    await session.selectArea(
      companyId: DatabaseService.legacyCompanyId,
      areaId: DatabaseService.legacyPlantAreaId,
    );
    final organizations = SqliteOrganizationRepository(
      database,
      context: () => session.accessContext,
      hasher: const PasswordHasher(iterations: 10000),
    );
    final container = ProviderContainer(
      overrides: [
        localSessionProvider.overrideWithValue(session),
        organizationRepositoryProvider.overrideWithValue(organizations),
        authenticationRepositoryProvider.overrideWithValue(organizations),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await organizations.close();
      database.close();
    });
    final router = container.read(appRouterProvider)..go('/admin');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logout-from-areas')), findsOneWidget);
    expect(find.text('Administración'), findsNothing);
  });

  testWidgets('logout desde inicio llega al login sin excepciones', (
    tester,
  ) async {
    final database = DatabaseService.inMemory();
    final session = await LocalSession.load(store: _MemorySessionStore());
    final now = DateTime(2026);
    await session.start(
      AppUser(
        id: 'regular',
        username: 'regular',
        displayName: 'Regular',
        privilege: PlatformPrivilege.user,
        companyIds: const {DatabaseService.legacyCompanyId},
        operationalRole: AppRole.production,
        active: true,
        areaAccessMode: AreaAccessMode.selected,
        areaIds: const {DatabaseService.legacyPlantAreaId},
        createdAt: now,
        updatedAt: now,
      ),
    );
    await session.selectArea(
      companyId: DatabaseService.legacyCompanyId,
      areaId: DatabaseService.legacyPlantAreaId,
    );
    final organizations = SqliteOrganizationRepository(
      database,
      context: () => session.accessContext,
      hasher: const PasswordHasher(iterations: 10000),
    );
    final maintenance = SqliteMaintenanceRepository(
      database,
      notificationGateway: const NoopNotificationGateway(),
      context: () => session.accessContext,
    );
    final container = ProviderContainer(
      overrides: [
        localSessionProvider.overrideWithValue(session),
        organizationRepositoryProvider.overrideWithValue(organizations),
        authenticationRepositoryProvider.overrideWithValue(organizations),
        maintenanceRepositoryProvider.overrideWithValue(maintenance),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await maintenance.close();
      await organizations.close();
      database.close();
    });
    final router = container.read(appRouterProvider)..go('/home');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-logo-login')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logout desde selector de empresa no muestra error fugaz', (
    tester,
  ) async {
    final database = DatabaseService.inMemory();
    final session = await LocalSession.load(store: _MemorySessionStore());
    final now = DateTime(2026);
    await session.start(
      AppUser(
        id: 'regular-areas',
        username: 'regular-areas',
        displayName: 'Regular',
        privilege: PlatformPrivilege.user,
        companyIds: const {DatabaseService.legacyCompanyId},
        operationalRole: AppRole.production,
        active: true,
        areaAccessMode: AreaAccessMode.selected,
        areaIds: const {DatabaseService.legacyPlantAreaId},
        createdAt: now,
        updatedAt: now,
      ),
    );
    final organizations = SqliteOrganizationRepository(
      database,
      context: () => session.accessContext,
      hasher: const PasswordHasher(iterations: 10000),
    );
    final container = ProviderContainer(
      overrides: [
        localSessionProvider.overrideWithValue(session),
        organizationRepositoryProvider.overrideWithValue(organizations),
        authenticationRepositoryProvider.overrideWithValue(organizations),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await organizations.close();
      database.close();
    });
    final router = container.read(appRouterProvider)..go('/areas');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('logout-from-areas')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-logo-login')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MemorySessionStore implements SessionStore {
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
