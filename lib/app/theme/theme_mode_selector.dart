import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_providers.dart';

class ThemeModeSelector extends ConsumerWidget {
  const ThemeModeSelector({super.key});

  static const selectorKey = Key('theme-mode-selector');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return PopupMenuButton<ThemeMode>(
      key: selectorKey,
      tooltip: 'Cambiar apariencia',
      icon: Icon(_iconFor(mode)),
      onSelected: (selected) =>
          ref.read(themeModeProvider.notifier).setMode(selected),
      itemBuilder: (context) => ThemeMode.values
          .map(
            (option) => PopupMenuItem(
              key: Key('theme-mode-${option.name}'),
              value: option,
              child: Row(
                children: [
                  Icon(_iconFor(option)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_labelFor(option))),
                  if (option == mode) const Icon(Icons.check_rounded),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  IconData _iconFor(ThemeMode mode) => switch (mode) {
    ThemeMode.system => Icons.brightness_auto_rounded,
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
  };

  String _labelFor(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Automático',
    ThemeMode.light => 'Claro',
    ThemeMode.dark => 'Oscuro',
  };
}
