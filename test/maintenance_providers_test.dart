import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/app/app_providers.dart';
import 'package:gestion_interna/core/database/database_service.dart';
import 'package:gestion_interna/core/notifications/notification_service.dart';
import 'package:gestion_interna/core/session/local_session.dart';
import 'package:gestion_interna/features/maintenance/application/maintenance_providers.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_maintenance_repository.dart';
import 'package:gestion_interna/features/maintenance/domain/create_ticket_input.dart';
import 'package:gestion_interna/features/maintenance/domain/maintenance_ticket.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/features/organization/domain/organization_models.dart';

void main() {
  test('ticketsProvider se vuelve a suscribir al cambiar de área', () async {
    final database = DatabaseService.inMemory();
    final session = await LocalSession.load(store: _MemorySessionStore());
    final now = DateTime(2026);
    await session.start(
      AppUser(
        id: DatabaseService.legacyUserId,
        username: 'operator',
        displayName: 'Solicitante',
        privilege: PlatformPrivilege.user,
        companyIds: const {DatabaseService.legacyCompanyId},
        operationalRole: AppRole.production,
        active: true,
        areaAccessMode: AreaAccessMode.all,
        areaIds: const {},
        createdAt: now,
        updatedAt: now,
      ),
    );
    final repository = SqliteMaintenanceRepository(
      database,
      notificationGateway: const NoopNotificationGateway(),
      context: () => session.accessContext,
    );
    addTearDown(() async {
      await repository.close();
      database.close();
    });

    await session.selectArea(
      companyId: DatabaseService.legacyCompanyId,
      areaId: DatabaseService.legacyPlantAreaId,
    );
    final ticketA = await repository.createTicket(_input('Área A'));
    await session.selectArea(
      companyId: DatabaseService.legacyCompanyId,
      areaId: 'legacy-area-crushing',
    );
    final ticketB = await repository.createTicket(_input('Área B'));
    await session.selectArea(
      companyId: DatabaseService.legacyCompanyId,
      areaId: DatabaseService.legacyPlantAreaId,
    );

    final container = ProviderContainer(
      overrides: [
        localSessionProvider.overrideWithValue(session),
        maintenanceRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final areaAReceived = Completer<void>();
    final areaBReceived = Completer<void>();
    final subscription = container.listen<AsyncValue<List<MaintenanceTicket>>>(
      ticketsProvider,
      (_, next) {
        if (next is! AsyncData<List<MaintenanceTicket>>) return;
        final ticketIds = next.value.map((ticket) => ticket.id).toList();
        if (ticketIds.length == 1 &&
            ticketIds.single == ticketA.ticketId &&
            !areaAReceived.isCompleted) {
          areaAReceived.complete();
        }
        if (ticketIds.length == 1 &&
            ticketIds.single == ticketB.ticketId &&
            !areaBReceived.isCompleted) {
          areaBReceived.complete();
        }
      },
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await areaAReceived.future.timeout(const Duration(seconds: 5));

    await container
        .read(sessionProvider.notifier)
        .selectArea(DatabaseService.legacyCompanyId, 'legacy-area-crushing');

    await areaBReceived.future.timeout(const Duration(seconds: 5));
  });
}

CreateTicketInput _input(String title) => CreateTicketInput(
  title: title,
  description: 'Detalle',
  location: 'Zona',
  locationIsCustom: true,
  priority: TicketPriority.medium,
);

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
