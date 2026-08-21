import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/app/app_providers.dart';
import 'package:gestion_interna/core/database/database_service.dart';
import 'package:gestion_interna/core/notifications/app_notification.dart';
import 'package:gestion_interna/core/notifications/notification_service.dart';
import 'package:gestion_interna/core/session/local_session.dart';
import 'package:gestion_interna/features/maintenance/application/maintenance_providers.dart';
import 'package:gestion_interna/features/maintenance/data/sqlite_maintenance_repository.dart';
import 'package:gestion_interna/features/maintenance/domain/maintenance_ticket.dart';
import 'package:gestion_interna/features/maintenance/presentation/area_selection_screen.dart';
import 'package:gestion_interna/features/maintenance/presentation/app_shell.dart';
import 'package:gestion_interna/features/maintenance/presentation/create_ticket_screen.dart';
import 'package:gestion_interna/features/maintenance/presentation/login_screen.dart';
import 'package:gestion_interna/features/maintenance/presentation/ticket_detail_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_CO'));
  testWidgets('selector inicial muestra únicamente Planta', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AreaSelectionScreen())),
    );
    expect(find.text('Planta'), findsOneWidget);
    expect(find.byKey(const Key('select-plant')), findsOneWidget);
    expect(find.text('Mantenimiento'), findsNothing);
  });

  testWidgets('constructor añade una pregunta de texto libre', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: CreateTicketScreen())),
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
  });

  testWidgets('login muestra los tres tipos de cuenta', (tester) async {
    final session = await LocalSession.load(store: _MemorySessionStore());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localSessionProvider.overrideWithValue(session)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
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
