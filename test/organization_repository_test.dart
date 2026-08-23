import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/core/database/database_service.dart';
import 'package:gestion_interna/core/notifications/notification_service.dart';
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
      companyId: user.companyId,
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
      companyId: companyId,
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
  companyId: user.companyId,
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
