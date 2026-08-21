import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/app/app_providers.dart';
import 'package:gestion_interna/app/router.dart';
import 'package:gestion_interna/core/notifications/app_notification.dart';
import 'package:gestion_interna/core/session/local_session.dart';
import 'package:gestion_interna/features/maintenance/application/maintenance_providers.dart';
import 'package:gestion_interna/features/maintenance/domain/maintenance_ticket.dart';

void main() {
  testWidgets('sesión cerrada abre login', (tester) async {
    final session = await LocalSession.load(store: _MemorySessionStore());
    await _pumpRouter(tester, session);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });

  testWidgets('sesión abierta abre áreas, permite entrar, volver y salir', (
    tester,
  ) async {
    final session = await LocalSession.load(store: _MemorySessionStore());
    await session.login(AccountRole.production);
    await _pumpRouter(tester, session);
    expect(find.byKey(const Key('select-plant')), findsOneWidget);

    await tester.tap(find.byKey(const Key('select-plant')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-menu')), findsOneWidget);

    await tester.tap(find.byKey(const Key('session-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cambiar área'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('select-plant')), findsOneWidget);

    await tester.tap(find.byKey(const Key('logout-from-areas')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });
}

Future<void> _pumpRouter(WidgetTester tester, LocalSession session) async {
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
      child: const _RouterHarness(),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

class _RouterHarness extends ConsumerWidget {
  const _RouterHarness();
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      MaterialApp.router(routerConfig: ref.watch(appRouterProvider));
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
