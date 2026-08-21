import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/app/app_providers.dart';
import 'package:gestion_interna/core/database/database_service.dart';
import 'package:gestion_interna/core/notifications/app_notification.dart';
import 'package:gestion_interna/core/notifications/notification_service.dart';
import 'package:gestion_interna/core/session/local_session.dart';
import 'package:gestion_interna/features/maintenance/application/form_template_providers.dart';
import 'package:gestion_interna/features/maintenance/application/maintenance_providers.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_form_template_repository.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_maintenance_repository.dart';
import 'package:gestion_interna/features/maintenance/domain/form_template.dart';
import 'package:gestion_interna/features/maintenance/domain/maintenance_ticket.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_question.dart';
import 'package:gestion_interna/features/maintenance/presentation/area_selection_screen.dart';
import 'package:gestion_interna/features/maintenance/presentation/app_shell.dart';
import 'package:gestion_interna/features/maintenance/presentation/create_ticket_screen.dart';
import 'package:gestion_interna/features/maintenance/presentation/login_screen.dart';
import 'package:gestion_interna/features/maintenance/presentation/ticket_detail_screen.dart';
import 'package:gestion_interna/app/router.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_CO'));

  testWidgets('splash carga el logo oficial', (tester) async {
    final session = await LocalSession.load(store: _MemorySessionStore());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localSessionProvider.overrideWithValue(session)],
        child: const MaterialApp(home: SplashScreen()),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('app-logo-splash')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('selector inicial muestra únicamente Planta', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AreaSelectionScreen())),
    );
    expect(find.text('Planta'), findsOneWidget);
    expect(find.byKey(const Key('select-plant')), findsOneWidget);
    expect(find.text('Mantenimiento'), findsNothing);
  });

  testWidgets('constructor añade una pregunta de texto libre', (tester) async {
    final database = DatabaseService.inMemory();
    final session = await LocalSession.load(store: _MemorySessionStore());
    await session.login(AccountRole.production);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localSessionProvider.overrideWithValue(session),
          formTemplateRepositoryProvider.overrideWithValue(
            SqliteFormTemplateRepository(database),
          ),
        ],
        child: const MaterialApp(home: CreateTicketScreen()),
      ),
    );
    await tester.tap(find.byKey(const Key('add-question')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('question-prompt')),
      '¿Qué encontró?',
    );
    await tester.tap(find.byKey(const Key('save-question')));
    await tester.pumpAndSettle();
    expect(find.text('¿Qué encontró?'), findsOneWidget);
    expect(find.text('Texto libre'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    database.close();
  });

  testWidgets('login muestra los tres tipos de cuenta', (tester) async {
    final session = await LocalSession.load(store: _MemorySessionStore());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localSessionProvider.overrideWithValue(session)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    expect(find.byKey(const Key('app-logo-login')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('account-role')));
    await tester.pumpAndSettle();
    expect(find.text('Planta'), findsWidgets);
    expect(find.text('Mantenimiento'), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);
  });

  for (final role in [AccountRole.production, AccountRole.maintenance]) {
    testWidgets('Modo de prueba no aparece para ${role.label}', (tester) async {
      final session = await LocalSession.load(store: _MemorySessionStore());
      await session.login(role);
      await _pumpShell(tester, session);
      expect(find.byKey(const Key('test-mode-menu')), findsNothing);
      expect(
        find.byKey(const Key('create-ticket')),
        role == AccountRole.production ? findsOneWidget : findsNothing,
      );
      if (role == AccountRole.production) {
        expect(
          tester.getTopLeft(find.byKey(const Key('create-ticket'))).dy,
          greaterThan(tester.getTopLeft(find.text('Críticos abiertos')).dy),
        );
      }
      await tester.tap(find.byKey(const Key('session-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Formularios prediseñados'), findsNothing);
    });
  }

  testWidgets('Administrador alterna la vista operativa', (tester) async {
    final session = await LocalSession.load(store: _MemorySessionStore());
    await session.login(AccountRole.administrator);
    await _pumpShell(tester, session);
    expect(find.byKey(const Key('test-mode-menu')), findsOneWidget);
    expect(find.byKey(const Key('create-ticket')), findsOneWidget);
    await tester.tap(find.byKey(const Key('test-mode-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vista Mantenimiento').last);
    await tester.pumpAndSettle();
    expect(find.text('Vista Mantenimiento'), findsOneWidget);
    expect(find.byKey(const Key('create-ticket')), findsNothing);
    await tester.tap(find.byKey(const Key('session-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Formularios prediseñados'), findsOneWidget);
  });

  testWidgets('seleccionar plantilla agrega copias editables y eliminables', (
    tester,
  ) async {
    final database = DatabaseService.inMemory();
    final repository = SqliteFormTemplateRepository(database);
    final now = DateTime(2026, 8, 20);
    await repository.createTemplate(
      FormTemplate(
        id: 'review',
        name: 'Revisión de máquina',
        questions: const [
          TicketQuestion(
            id: 'template-q1',
            prompt: 'Diagnóstico inicial',
            type: QuestionType.freeText,
            required: true,
            order: 0,
          ),
          TicketQuestion(
            id: 'template-q2',
            prompt: '¿Puede operar?',
            type: QuestionType.singleChoice,
            required: true,
            order: 1,
            options: ['Sí', 'No'],
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    final session = await LocalSession.load(store: _MemorySessionStore());
    await session.login(AccountRole.production);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localSessionProvider.overrideWithValue(session),
          formTemplateRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: CreateTicketScreen()),
      ),
    );
    final useTemplate = find.byKey(const Key('use-form-template'));
    await tester.ensureVisible(useTemplate);
    await tester.tap(useTemplate);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('select-template-review')));
    await tester.pumpAndSettle();
    expect(find.text('Diagnóstico inicial'), findsOneWidget);
    expect(find.text('¿Puede operar?'), findsOneWidget);

    final questionList = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    questionList.onReorderItem!(0, 2);
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('¿Puede operar?')).dy,
      lessThan(tester.getTopLeft(find.text('Diagnóstico inicial')).dy),
    );

    await tester.tap(find.text('Diagnóstico inicial'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('question-prompt')),
      'Diagnóstico modificado',
    );
    await tester.tap(find.byKey(const Key('save-question')));
    await tester.pumpAndSettle();
    expect(find.text('Diagnóstico modificado'), findsOneWidget);

    final canOperateTile = find.ancestor(
      of: find.text('¿Puede operar?'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(
        of: canOperateTile,
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('¿Puede operar?'), findsNothing);
    expect((await repository.getTemplate('review'))?.questions, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    database.close();
  });

  testWidgets('crear ticket abre detalle y atrás vuelve al dashboard', (
    tester,
  ) async {
    final session = await LocalSession.load(store: _MemorySessionStore());
    await session.login(AccountRole.production);
    final repository = SqliteMaintenanceRepository(
      DatabaseService.inMemory(),
      notificationGateway: const NoopNotificationGateway(),
    );
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, _) => Scaffold(
            body: FilledButton(
              key: const Key('open-create'),
              onPressed: () => context.push('/tickets/new'),
              child: const Text('Dashboard'),
            ),
          ),
        ),
        GoRoute(
          path: '/tickets/new',
          builder: (_, _) => const CreateTicketScreen(),
        ),
        GoRoute(
          path: '/tickets/:ticketId',
          builder: (_, state) =>
              TicketDetailScreen(ticketId: state.pathParameters['ticketId']!),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localSessionProvider.overrideWithValue(session),
          maintenanceRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.byKey(const Key('open-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ticket-title')),
      'Falla de prueba',
    );
    await tester.enterText(
      find.byKey(const Key('ticket-description')),
      'Descripción de prueba',
    );
    await tester.enterText(find.byKey(const Key('ticket-location')), 'Línea 1');
    await tester.tap(find.byKey(const Key('submit-ticket')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('ticket-back')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ticket-back')));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsOneWidget);

    final ticketId = (await repository.watchTickets().first).single.id;
    router.go('/tickets/$ticketId');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('ticket-back')));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await repository.close();
  });
}

Future<void> _pumpShell(WidgetTester tester, LocalSession session) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localSessionProvider.overrideWithValue(session),
        ticketsProvider.overrideWith(
          (_) => Stream.value(const <MaintenanceTicket>[]),
        ),
        notificationsProvider.overrideWith(
          (_) => Stream.value(const <AppNotification>[]),
        ),
        unreadNotificationsProvider.overrideWith((_) => Stream.value(0)),
      ],
      child: const MaterialApp(home: AppShell()),
    ),
  );
  await tester.pumpAndSettle();
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
