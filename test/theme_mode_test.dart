import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/app/app_providers.dart';
import 'package:gestion_interna/app/theme/app_theme.dart';
import 'package:gestion_interna/app/theme/theme_mode_selector.dart';
import 'package:gestion_interna/app/theme/theme_mode_store.dart';

void main() {
  test('el modo predeterminado es automático', () {
    final container = _container(_MemoryThemeModeStore());
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test(
    'lee el modo persistido y usa automático ante un valor desconocido',
    () async {
      final store = _MemoryThemeModeStore(value: 'dark');
      final container = _container(store);
      addTearDown(container.dispose);
      container.read(themeModeProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(themeModeProvider), ThemeMode.dark);

      store.value = 'legacy-value';
      final fallback = _container(store);
      addTearDown(fallback.dispose);
      fallback.read(themeModeProvider);
      await Future<void>.delayed(Duration.zero);
      expect(fallback.read(themeModeProvider), ThemeMode.system);
    },
  );

  test('escribe todos los modos y actualiza el estado de inmediato', () async {
    final store = _MemoryThemeModeStore();
    final container = _container(store);
    addTearDown(container.dispose);

    for (final mode in ThemeMode.values) {
      final future = container.read(themeModeProvider.notifier).setMode(mode);
      expect(container.read(themeModeProvider), mode);
      await future;
      expect(store.value, mode.name);
    }
  });

  testWidgets('el selector muestra las opciones y cambia el modo activo', (
    tester,
  ) async {
    final store = _MemoryThemeModeStore();
    final container = _container(store);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: Scaffold(appBar: AppBar(actions: const [ThemeModeSelector()])),
        ),
      ),
    );

    await tester.tap(find.byKey(ThemeModeSelector.selectorKey));
    await tester.pumpAndSettle();
    expect(find.text('Automático'), findsOneWidget);
    expect(find.text('Claro'), findsOneWidget);
    expect(find.text('Oscuro'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('theme-mode-dark')));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(store.value, 'dark');

    await tester.tap(find.byKey(ThemeModeSelector.selectorKey));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  test('los temas tienen brillo correcto y Card adapta su borde', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    final darkShape = dark.cardTheme.shape! as RoundedRectangleBorder;

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(darkShape.side.color, dark.colorScheme.outlineVariant);
    expect(darkShape.side.color, isNot(const Color(0xFFE1E7EF)));
  });
}

ProviderContainer _container(_MemoryThemeModeStore store) => ProviderContainer(
  overrides: [themeModeStoreProvider.overrideWithValue(store)],
);

class _MemoryThemeModeStore implements ThemeModeStore {
  _MemoryThemeModeStore({this.value});

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String next) async => value = next;
}
