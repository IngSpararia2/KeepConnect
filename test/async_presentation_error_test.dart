import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/app/app_providers.dart';
import 'package:gestion_interna/core/session/local_session.dart';
import 'package:gestion_interna/features/maintenance/application/form_template_providers.dart';
import 'package:gestion_interna/features/maintenance/data/form_template_repository.dart';
import 'package:gestion_interna/features/maintenance/domain/form_template.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_question.dart';
import 'package:gestion_interna/features/maintenance/presentation/create_ticket_screen.dart';
import 'package:gestion_interna/features/maintenance/presentation/form_template_editor_screen.dart';
import 'package:gestion_interna/features/maintenance/presentation/form_template_list_screen.dart';
import 'package:gestion_interna/features/organization/data/organization_repository.dart';
import 'package:gestion_interna/features/organization/domain/organization_models.dart';

void main() {
  testWidgets('fallo de catálogos deja creación recuperable', (tester) async {
    final session = await _session();
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localSessionProvider.overrideWithValue(session),
          organizationRepositoryProvider.overrideWithValue(
            _FailingOrganizationRepository(),
          ),
        ],
        child: const MaterialApp(home: CreateTicketScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No fue posible cargar los catálogos. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('retry-ticket-catalogs')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fallo al editar plantilla permite reintentar', (tester) async {
    final repository = _FakeFormTemplateRepository(failFirstGet: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          formTemplateRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: FormTemplateEditorScreen(templateId: 'template-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No fue posible cargar la plantilla.'), findsOneWidget);
    expect(find.byKey(const Key('retry-template-load')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('retry-template-load')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('template-name')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fallo al eliminar plantilla queda controlado', (tester) async {
    final repository = _FakeFormTemplateRepository(failDelete: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          formTemplateRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: FormTemplateListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete-template-template-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-template')));
    await tester.pumpAndSettle();

    expect(find.text('No fue posible eliminar la plantilla.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<LocalSession> _session() async {
  final session = await LocalSession.load(store: _MemorySessionStore());
  final now = DateTime(2026);
  await session.start(
    AppUser(
      id: 'user-1',
      username: 'operador',
      displayName: 'Operador',
      privilege: PlatformPrivilege.user,
      companyIds: const {'company-1'},
      operationalRole: AppRole.production,
      active: true,
      areaAccessMode: AreaAccessMode.selected,
      areaIds: const {'area-1'},
      createdAt: now,
      updatedAt: now,
    ),
  );
  await session.selectArea(companyId: 'company-1', areaId: 'area-1');
  return session;
}

FormTemplate _template() {
  final now = DateTime(2026);
  return FormTemplate(
    id: 'template-1',
    name: 'Plantilla de prueba',
    questions: const [
      TicketQuestion(
        id: 'question-1',
        prompt: 'Detalle',
        type: QuestionType.freeText,
        required: true,
        order: 0,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

final class _FailingOrganizationRepository implements OrganizationRepository {
  @override
  Stream<List<CatalogItem>> watchCatalog(
    String companyId,
    String areaId,
    CatalogKind kind, {
    bool includeInactive = false,
  }) => Stream.error(StateError('sqlite unavailable'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeFormTemplateRepository implements FormTemplateRepository {
  _FakeFormTemplateRepository({
    this.failFirstGet = false,
    this.failDelete = false,
  });

  bool failFirstGet;
  final bool failDelete;

  @override
  Stream<List<FormTemplate>> watchTemplates() => Stream.value([_template()]);

  @override
  Future<FormTemplate?> getTemplate(String id) async {
    if (failFirstGet) {
      failFirstGet = false;
      throw StateError('sqlite unavailable');
    }
    return _template();
  }

  @override
  Future<void> deleteTemplate(String id) async {
    if (failDelete) throw StateError('sqlite unavailable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _MemorySessionStore implements SessionStore {
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
