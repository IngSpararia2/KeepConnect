import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/core/database/database_service.dart';
import 'package:gestion_interna/core/notifications/notification_service.dart';
import 'package:gestion_interna/core/session/local_session.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_form_template_repository.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_maintenance_repository.dart';
import 'package:gestion_interna/features/maintenance/domain/create_ticket_input.dart';
import 'package:gestion_interna/features/maintenance/domain/form_template.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_question.dart';
import 'package:gestion_interna/features/organization/data/password_hasher.dart';
import 'package:gestion_interna/features/organization/data/sqlite_organization_repository.dart';
import 'package:gestion_interna/features/organization/domain/organization_models.dart';

void main() {
  late DatabaseService database;
  late AccessContext? context;
  late SqliteOrganizationRepository organizations;
  late AppUser owner;
  final now = DateTime(2026, 8, 23);

  AccessContext adminContext([String? companyId, String? areaId]) =>
      AccessContext(
        userId: owner.id,
        privilege: PlatformPrivilege.superAdmin,
        operationalRole: AppRole.production,
        companyId: companyId,
        areaId: areaId,
      );

  setUp(() async {
    database = DatabaseService.inMemory(seedLegacyContext: false);
    context = null;
    organizations = SqliteOrganizationRepository(
      database,
      context: () => context,
      hasher: const PasswordHasher(iterations: 10000),
    );
    owner = await organizations.bootstrapOwner(
      username: 'owner@example.com',
      displayName: 'Propietario',
      password: 'Segura-2026!',
    );
    context = adminContext();
  });

  tearDown(() async {
    await organizations.close();
    database.close();
  });

  test(
    'bootstrap del superadministrador solo está disponible una vez',
    () async {
      expect(await organizations.needsBootstrap(), isFalse);
      await expectLater(
        organizations.bootstrapOwner(
          username: 'otro',
          displayName: 'Otro',
          password: 'Otra-Segura-2026!',
        ),
        throwsStateError,
      );
      final authenticated = await organizations.authenticate(
        'OWNER@example.com',
        'Segura-2026!',
      );
      expect(authenticated.isSuperAdmin, isTrue);
    },
  );

  test('crea, modifica y desactiva empresas y áreas sin borrarlas', () async {
    final company = _company('company-a', 'Empresa A', now);
    await organizations.saveCompany(company);
    await organizations.saveCompany(
      company.copyWith(
        name: 'Empresa Alfa',
        updatedAt: now.add(const Duration(minutes: 1)),
      ),
    );
    await organizations.saveCompany(
      company.copyWith(
        name: 'Empresa Alfa',
        active: false,
        updatedAt: now.add(const Duration(minutes: 2)),
      ),
    );
    expect((await organizations.getCompany(company.id))?.active, isFalse);

    final area = _area('area-a', company.id, 'Planta', now);
    await organizations.saveArea(area);
    await organizations.saveArea(
      area.copyWith(
        name: 'Producción',
        updatedAt: now.add(const Duration(minutes: 1)),
      ),
    );
    await organizations.saveArea(
      area.copyWith(
        name: 'Producción',
        active: false,
        updatedAt: now.add(const Duration(minutes: 2)),
      ),
    );
    expect((await organizations.getArea(area.id))?.active, isFalse);
    expect(await organizations.watchAreas(company.id).first, hasLength(1));
  });

  test('administra usuarios, permisos, credenciales y bloqueo', () async {
    final company = _company('company-a', 'Empresa A', now);
    final areaA = _area('area-a', company.id, 'Planta', now);
    final areaB = _area('area-b', company.id, 'Trituración', now);
    await organizations.saveCompany(company);
    await organizations.saveArea(areaA);
    await organizations.saveArea(areaB);
    final user = _user('user-a', company.id, {areaA.id}, now);
    await organizations.saveUser(user, newPassword: 'Usuario-2026!');
    expect((await organizations.getUser(user.id))?.areaIds, {areaA.id});
    expect(
      (await organizations.authenticate(user.username, 'Usuario-2026!')).id,
      user.id,
    );

    await organizations.resetPassword(user.id, 'Nueva-Usuario-2026!');
    await expectLater(
      organizations.authenticate(user.username, 'Usuario-2026!'),
      throwsStateError,
    );
    expect(
      (await organizations.authenticate(
        user.username,
        'Nueva-Usuario-2026!',
      )).id,
      user.id,
    );

    await organizations.saveUser(_copyUser(user, active: false));
    await expectLater(
      organizations.authenticate(user.username, 'Nueva-Usuario-2026!'),
      throwsStateError,
    );
  });

  test('usuario conserva dos empresas y solo sus áreas autorizadas', () async {
    final companyA = _company('company-a', 'Empresa A', now);
    final companyB = _company('company-b', 'Empresa B', now);
    final companyC = _company('company-c', 'Empresa C', now);
    final areaA = _area('area-a', companyA.id, 'Planta', now);
    final areaB = _area('area-b', companyB.id, 'Trituración', now);
    final areaB2 = _area('area-b2', companyB.id, 'Administración', now);
    final areaC = _area('area-c', companyC.id, 'Empaque', now);
    for (final company in [companyA, companyB, companyC]) {
      await organizations.saveCompany(company);
    }
    for (final area in [areaA, areaB, areaB2, areaC]) {
      await organizations.saveArea(area);
    }
    final user = AppUser(
      id: 'multi-user',
      username: 'multi@example.com',
      displayName: 'Multiempresa',
      privilege: PlatformPrivilege.user,
      companyIds: {companyA.id, companyB.id},
      operationalRole: AppRole.maintenance,
      active: true,
      areaAccessMode: AreaAccessMode.selected,
      areaIds: {areaA.id, areaB.id},
      createdAt: now,
      updatedAt: now,
    );
    await organizations.saveUser(user, newPassword: 'Multi-2026!');
    final authenticated = await organizations.authenticate(
      user.username,
      'Multi-2026!',
    );
    expect(authenticated.companyIds, {companyA.id, companyB.id});

    context = AccessContext(
      userId: user.id,
      privilege: user.privilege,
      operationalRole: user.operationalRole!,
      companyId: null,
      areaId: null,
      allowedCompanyIds: user.companyIds,
      allowedAreaIds: user.areaIds,
    );
    expect(
      (await organizations.watchCompanies(includeInactive: false).first)
          .map((company) => company.id)
          .toSet(),
      {companyA.id, companyB.id},
    );
    expect(
      (await organizations.watchAreas(companyB.id).first)
          .map((area) => area.id)
          .toSet(),
      {areaB.id},
    );
    await expectLater(organizations.getCompany(companyC.id), throwsStateError);

    final session = await LocalSession.load(
      store: _MemorySessionStore(),
      validateContext: organizations.isContextAvailable,
    );
    await session.start(authenticated);
    await session.selectArea(companyId: companyA.id, areaId: areaA.id);
    await session.selectArea(companyId: companyB.id, areaId: areaB.id);
    await expectLater(
      session.selectArea(companyId: companyB.id, areaId: areaB2.id),
      throwsStateError,
    );
    await expectLater(
      session.selectArea(companyId: companyC.id, areaId: areaC.id),
      throwsStateError,
    );

    context = adminContext();
    await expectLater(
      organizations.saveUser(
        AppUser(
          id: 'invalid-user',
          username: 'invalid@example.com',
          displayName: 'Inválido',
          privilege: PlatformPrivilege.user,
          companyIds: {companyA.id, companyB.id},
          operationalRole: AppRole.production,
          active: true,
          areaAccessMode: AreaAccessMode.selected,
          areaIds: {areaA.id},
          createdAt: now,
          updatedAt: now,
        ),
        newPassword: 'Invalid-2026!',
      ),
      throwsArgumentError,
    );
  });

  test('modo all abarca áreas de empresas asignadas, no externas', () async {
    final companyA = _company('company-a', 'Empresa A', now);
    final companyB = _company('company-b', 'Empresa B', now);
    final companyC = _company('company-c', 'Empresa C', now);
    final areaA = _area('area-a', companyA.id, 'Planta', now);
    final areaB = _area('area-b', companyB.id, 'Trituración', now);
    final areaC = _area('area-c', companyC.id, 'Empaque', now);
    for (final company in [companyA, companyB, companyC]) {
      await organizations.saveCompany(company);
    }
    for (final area in [areaA, areaB, areaC]) {
      await organizations.saveArea(area);
    }
    final user = AppUser(
      id: 'all-user',
      username: 'all@example.com',
      displayName: 'Todas',
      privilege: PlatformPrivilege.user,
      companyIds: {companyA.id, companyB.id},
      operationalRole: AppRole.production,
      active: true,
      areaAccessMode: AreaAccessMode.all,
      areaIds: const {},
      createdAt: now,
      updatedAt: now,
    );
    await organizations.saveUser(user, newPassword: 'All-2026!!');
    context = AccessContext(
      userId: user.id,
      privilege: user.privilege,
      operationalRole: user.operationalRole!,
      companyId: null,
      areaId: null,
      allowedCompanyIds: user.companyIds,
      allCompanyAreas: true,
    );
    expect(await organizations.watchAreas(companyA.id).first, hasLength(1));
    expect(await organizations.watchAreas(companyB.id).first, hasLength(1));
    expect(() => organizations.watchAreas(companyC.id), throwsStateError);
  });

  test('catálogo evita duplicados normalizados y conserva retirados', () async {
    final company = _company('company-a', 'Empresa A', now);
    final area = _area('area-a', company.id, 'Planta', now);
    await organizations.saveCompany(company);
    await organizations.saveArea(area);
    final item = _catalog(
      'location-a',
      company.id,
      area.id,
      CatalogKind.location,
      'Línea 1',
      now,
    );
    await organizations.saveCatalogItem(item);
    await expectLater(
      organizations.saveCatalogItem(
        _catalog(
          'location-b',
          company.id,
          area.id,
          CatalogKind.location,
          '  línea 1 ',
          now,
        ),
      ),
      throwsA(anything),
    );
    await organizations.saveCatalogItem(
      item.copyWith(active: false, updatedAt: DateTime.now()),
    );
    expect(
      await organizations
          .watchCatalog(company.id, area.id, CatalogKind.location)
          .first,
      isEmpty,
    );
    expect(
      await organizations
          .watchCatalog(
            company.id,
            area.id,
            CatalogKind.location,
            includeInactive: true,
          )
          .first,
      hasLength(1),
    );
    await expectLater(
      organizations.saveCatalogItem(
        _catalog(
          'other',
          company.id,
          area.id,
          CatalogKind.location,
          'Otra',
          now,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('tickets quedan aislados por empresa y área, incluso por ID', () async {
    final companyA = _company('company-a', 'Empresa A', now);
    final companyB = _company('company-b', 'Empresa B', now);
    final areaA = _area('area-a', companyA.id, 'Planta', now);
    final areaA2 = _area('area-a2', companyA.id, 'Trituración', now);
    final areaB = _area('area-b', companyB.id, 'Planta', now);
    for (final company in [companyA, companyB]) {
      await organizations.saveCompany(company);
    }
    for (final area in [areaA, areaA2, areaB]) {
      await organizations.saveArea(area);
    }
    final userA = _user('user-a', companyA.id, {areaA.id}, now);
    final userA2 = _user('user-a2', companyA.id, {areaA2.id}, now);
    final userB = _user('user-b', companyB.id, {areaB.id}, now);
    await organizations.saveUser(userA, newPassword: 'Usuario-A-2026!');
    await organizations.saveUser(userA2, newPassword: 'Usuario-A2-2026!');
    await organizations.saveUser(userB, newPassword: 'Usuario-B-2026!');

    AccessContext regular(AppUser user, WorkArea area) => AccessContext(
      userId: user.id,
      privilege: PlatformPrivilege.user,
      operationalRole: AppRole.production,
      companyId: area.companyId,
      allowedCompanyIds: user.companyIds,
      areaId: area.id,
      allowedAreaIds: user.areaIds,
    );
    final maintenance = SqliteMaintenanceRepository(
      database,
      notificationGateway: const NoopNotificationGateway(),
      context: () => context,
    );
    context = regular(userA, areaA);
    final ticketA = await maintenance.createTicket(_customInput('A'));
    context = regular(userA2, areaA2);
    final ticketA2 = await maintenance.createTicket(_customInput('A2'));
    context = regular(userB, areaB);
    final ticketB = await maintenance.createTicket(_customInput('B'));

    context = regular(userA, areaA);
    expect(
      (await maintenance.watchTickets().first).map((ticket) => ticket.id),
      [ticketA.ticketId],
    );
    expect(await maintenance.watchTicket(ticketA2.ticketId).first, isNull);
    expect(await maintenance.watchTicket(ticketB.ticketId).first, isNull);
    expect(await maintenance.watchUpdates(ticketA2.ticketId).first, isEmpty);
    expect(await maintenance.watchEvents(ticketA2.ticketId).first, isEmpty);
    expect(
      (await maintenance.watchNotifications(AppRole.maintenance).first).map(
        (item) => item.ticketId,
      ),
      [ticketA.ticketId],
    );
    // No se cierra el repositorio aquí porque comparte la conexión del fixture.
  });

  test(
    'ubicación/equipo guardan ID y snapshot; equipo es opcional y Otra se marca',
    () async {
      final company = _company('company-a', 'Empresa A', now);
      final area = _area('area-a', company.id, 'Planta', now);
      await organizations.saveCompany(company);
      await organizations.saveArea(area);
      final user = _user('user-a', company.id, {area.id}, now);
      await organizations.saveUser(user, newPassword: 'Usuario-A-2026!');
      final location = _catalog(
        'loc',
        company.id,
        area.id,
        CatalogKind.location,
        'Línea 1',
        now,
      );
      final equipment = _catalog(
        'eq',
        company.id,
        area.id,
        CatalogKind.equipment,
        'Motor 7',
        now,
      );
      await organizations.saveCatalogItem(location);
      await organizations.saveCatalogItem(equipment);
      context = AccessContext(
        userId: user.id,
        privilege: PlatformPrivilege.user,
        operationalRole: AppRole.production,
        companyId: company.id,
        areaId: area.id,
        allowedCompanyIds: user.companyIds,
        allowedAreaIds: user.areaIds,
      );
      final maintenance = SqliteMaintenanceRepository(
        database,
        context: () => context,
      );
      final managed = await maintenance.createTicket(
        CreateTicketInput(
          title: 'Gestionado',
          description: 'Detalle',
          location: location.name,
          locationOptionId: location.id,
          locationIsCustom: false,
          equipment: equipment.name,
          equipmentOptionId: equipment.id,
          equipmentIsCustom: false,
          priority: TicketPriority.medium,
        ),
      );
      final managedTicket = await maintenance
          .watchTicket(managed.ticketId)
          .first;
      expect(managedTicket?.locationOptionId, location.id);
      expect(managedTicket?.location, 'Línea 1');
      expect(managedTicket?.equipmentOptionId, equipment.id);

      context = adminContext(company.id, area.id);
      await organizations.saveCatalogItem(
        location.copyWith(
          name: 'Línea principal',
          active: false,
          updatedAt: DateTime.now(),
        ),
      );
      context = AccessContext(
        userId: user.id,
        privilege: PlatformPrivilege.user,
        operationalRole: AppRole.production,
        companyId: company.id,
        areaId: area.id,
        allowedCompanyIds: user.companyIds,
        allowedAreaIds: user.areaIds,
      );
      expect(
        await organizations
            .watchCatalog(company.id, area.id, CatalogKind.location)
            .first,
        isEmpty,
      );
      expect(
        (await maintenance.watchTicket(managed.ticketId).first)?.location,
        'Línea 1',
      );

      final custom = await maintenance.createTicket(
        const CreateTicketInput(
          title: 'Otra',
          description: 'Detalle',
          location: 'Patio temporal',
          locationIsCustom: true,
          equipment: null,
          priority: TicketPriority.low,
        ),
      );
      final customTicket = await maintenance.watchTicket(custom.ticketId).first;
      expect(customTicket?.locationIsCustom, isTrue);
      expect(customTicket?.equipment, isNull);
      expect(customTicket?.equipmentOptionId, isNull);

      await expectLater(
        maintenance.createTicket(
          const CreateTicketInput(
            title: 'Inválido',
            description: 'Detalle',
            location: '',
            locationIsCustom: true,
            priority: TicketPriority.low,
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test('plantillas están scopeadas por empresa y área', () async {
    final companyA = _company('company-a', 'Empresa A', now);
    final companyB = _company('company-b', 'Empresa B', now);
    final areaA = _area('area-a', companyA.id, 'Planta', now);
    final areaB = _area('area-b', companyB.id, 'Planta', now);
    await organizations.saveCompany(companyA);
    await organizations.saveCompany(companyB);
    await organizations.saveArea(areaA);
    await organizations.saveArea(areaB);
    final templates = SqliteFormTemplateRepository(
      database,
      context: () => context,
    );
    context = adminContext(companyA.id, areaA.id);
    await templates.createTemplate(
      FormTemplate(
        id: 'template-a',
        name: 'Formulario A',
        companyId: companyA.id,
        areaId: areaA.id,
        questions: const [
          TicketQuestion(
            id: 'q',
            prompt: 'Diagnóstico',
            type: QuestionType.freeText,
            required: true,
            order: 0,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    context = AccessContext(
      userId: 'regular-a',
      privilege: PlatformPrivilege.user,
      operationalRole: AppRole.production,
      companyId: companyA.id,
      areaId: areaA.id,
      allowedCompanyIds: {companyA.id},
      allowedAreaIds: {areaA.id},
    );
    await expectLater(templates.deleteTemplate('template-a'), throwsStateError);
    context = adminContext(companyB.id, areaB.id);
    expect(await templates.watchTemplates().first, isEmpty);
    expect(await templates.getTemplate('template-a'), isNull);
  });
}

Company _company(String id, String name, DateTime now) =>
    Company(id: id, name: name, active: true, createdAt: now, updatedAt: now);
WorkArea _area(String id, String companyId, String name, DateTime now) =>
    WorkArea(
      id: id,
      companyId: companyId,
      name: name,
      active: true,
      createdAt: now,
      updatedAt: now,
    );
AppUser _user(String id, String companyId, Set<String> areaIds, DateTime now) =>
    AppUser(
      id: id,
      username: '$id@example.com',
      displayName: id,
      privilege: PlatformPrivilege.user,
      companyIds: {companyId},
      operationalRole: AppRole.production,
      active: true,
      areaAccessMode: AreaAccessMode.selected,
      areaIds: areaIds,
      createdAt: now,
      updatedAt: now,
    );
AppUser _copyUser(AppUser user, {required bool active}) => AppUser(
  id: user.id,
  username: user.username,
  displayName: user.displayName,
  privilege: user.privilege,
  companyIds: user.companyIds,
  operationalRole: user.operationalRole,
  active: active,
  areaAccessMode: user.areaAccessMode,
  areaIds: user.areaIds,
  createdAt: user.createdAt,
  updatedAt: DateTime.now(),
  lastSeenAt: user.lastSeenAt,
);
CatalogItem _catalog(
  String id,
  String companyId,
  String areaId,
  CatalogKind kind,
  String name,
  DateTime now,
) => CatalogItem(
  id: id,
  companyId: companyId,
  areaId: areaId,
  kind: kind,
  name: name,
  active: true,
  createdAt: now,
  updatedAt: now,
);
CreateTicketInput _customInput(String suffix) => CreateTicketInput(
  title: 'Ticket $suffix',
  description: 'Detalle',
  location: 'Otra $suffix',
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
