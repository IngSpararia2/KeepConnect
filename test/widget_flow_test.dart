import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/app/app_providers.dart';
import 'package:gestion_interna/core/database/database_service.dart';
import 'package:gestion_interna/core/notifications/notification_service.dart';
import 'package:gestion_interna/core/session/local_session.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_maintenance_repository.dart';
import 'package:gestion_interna/features/maintenance/domain/create_ticket_input.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/features/maintenance/presentation/ticket_detail_screen.dart';
import 'package:gestion_interna/features/organization/domain/organization_models.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_CO'));
  testWidgets('diálogo de actualización cierra con system back sin excepción', (
    tester,
  ) async {
    final harness = await _TicketHarness.create();
    addTearDown(harness.dispose);
    await harness.pump(tester);
    await _openUpdateDialog(tester);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('update-content')), findsNothing);
    expect(find.text('Sin actualizaciones.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelar, tocar fuera y guardar actualización son seguros', (
    tester,
  ) async {
    final harness = await _TicketHarness.create();
    addTearDown(harness.dispose);
    await harness.pump(tester);

    await _openUpdateDialog(tester);
    await tester.tap(find.byKey(const Key('cancel-update')));
    await tester.pumpAndSettle();
    expect(
      await harness.repository.watchUpdates(harness.ticketId).first,
      isEmpty,
    );
    expect(tester.takeException(), isNull);

    await _openUpdateDialog(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update-content')), findsNothing);
    expect(tester.takeException(), isNull);

    await _openUpdateDialog(tester);
    await tester.enterText(
      find.byKey(const Key('update-content')),
      'Revisión segura',
    );
    await tester.tap(find.byKey(const Key('save-update')));
    await tester.pumpAndSettle();
    expect(
      (await harness.repository.watchUpdates(harness.ticketId).first)
          .single
          .content,
      'Revisión segura',
    );
    expect(find.byKey(const Key('update-content')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openUpdateDialog(WidgetTester tester) async {
  await tester.tap(find.text('Actualizaciones'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Añadir actualización'));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('update-content')), findsOneWidget);
}

class _TicketHarness {
  _TicketHarness(this.database, this.session, this.repository, this.ticketId);
  final DatabaseService database;
  final LocalSession session;
  final SqliteMaintenanceRepository repository;
  final String ticketId;

  static Future<_TicketHarness> create() async {
    final database = DatabaseService.inMemory();
    final session = await LocalSession.load(store: _MemorySessionStore());
    final now = DateTime(2026);
    await session.start(
      AppUser(
        id: DatabaseService.legacyUserId,
        username: 'produccion',
        displayName: 'Producción',
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
    final repository = SqliteMaintenanceRepository(
      database,
      notificationGateway: const NoopNotificationGateway(),
      context: () => session.accessContext,
    );
    final created = await repository.createTicket(
      const CreateTicketInput(
        title: 'Falla',
        description: 'Detalle',
        location: 'Zona manual',
        priority: TicketPriority.medium,
      ),
    );
    return _TicketHarness(database, session, repository, created.ticketId);
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localSessionProvider.overrideWithValue(session),
          maintenanceRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(home: TicketDetailScreen(ticketId: ticketId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    await repository.close();
  }
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
