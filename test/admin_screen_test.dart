import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/app/app_providers.dart';
import 'package:gestion_interna/core/database/database_service.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/features/organization/data/password_hasher.dart';
import 'package:gestion_interna/features/organization/data/sqlite_organization_repository.dart';
import 'package:gestion_interna/features/organization/domain/organization_models.dart';
import 'package:gestion_interna/features/organization/presentation/admin_screen.dart';

void main() {
  testWidgets('formulario de usuario se desplaza con teclado en móvil', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = DatabaseService.inMemory(seedLegacyContext: false);
    AccessContext? context;
    final organizations = SqliteOrganizationRepository(
      database,
      context: () => context,
      hasher: const PasswordHasher(iterations: 10000),
    );
    final owner = await organizations.bootstrapOwner(
      username: 'owner@example.com',
      displayName: 'Propietario',
      password: 'Segura-2026!',
    );
    context = AccessContext(
      userId: owner.id,
      privilege: PlatformPrivilege.superAdmin,
      operationalRole: AppRole.production,
      companyId: null,
      areaId: null,
    );
    final now = DateTime(2026);
    const companyId = 'company-a';
    await organizations.saveCompany(
      Company(
        id: companyId,
        name: 'Empresa A',
        active: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
    for (final area in ['Planta', 'Trituración', 'Administración', 'Empaque']) {
      await organizations.saveArea(
        WorkArea(
          id: area,
          companyId: companyId,
          name: area,
          active: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    final container = ProviderContainer(
      overrides: [
        organizationRepositoryProvider.overrideWithValue(organizations),
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
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuarios'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-user')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('user-password')));
    await tester.enterText(
      find.byKey(const Key('user-password')),
      'Segura-2026!',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Acceso a todas las áreas'));
    await tester.tap(find.text('Acceso a todas las áreas'));
    await tester.pumpAndSettle();
    expect(find.text('Áreas permitidas'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-user')));

    expect(find.byKey(const Key('save-user')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
