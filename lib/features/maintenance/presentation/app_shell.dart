import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../../../config/app_config.dart';
import '../application/maintenance_providers.dart';
import '../domain/ticket_enums.dart';
import 'maintenance_dashboard_screen.dart';
import 'notifications_screen.dart';
import 'ticket_list_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  var _index = 0;
  static const _titles = ['Inicio', 'Tickets', 'Notificaciones'];

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final unread = ref.watch(unreadNotificationsProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_titles[_index]),
            Text(
              'Área Planta · Vista ${session.effectiveRole.label}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        actions: [
          PopupMenuButton<_SessionAction>(
            key: const Key('session-menu'),
            tooltip: 'Cuenta y áreas',
            onSelected: (action) async {
              if (action == _SessionAction.templates) {
                context.push('/form-templates');
                return;
              }
              if (action == _SessionAction.areas) {
                context.go('/areas');
                return;
              }
              await ref.read(sessionProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            itemBuilder: (_) => [
              if (session.isAdministrator)
                const PopupMenuItem(
                  value: _SessionAction.templates,
                  child: ListTile(
                    leading: Icon(Icons.description_outlined),
                    title: Text('Formularios prediseñados'),
                  ),
                ),
              const PopupMenuItem(
                value: _SessionAction.areas,
                child: ListTile(
                  leading: Icon(Icons.apps_rounded),
                  title: Text('Cambiar área'),
                ),
              ),
              PopupMenuItem(
                value: _SessionAction.logout,
                child: ListTile(
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Cerrar sesión'),
                ),
              ),
            ],
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (session.isAdministrator)
            _TestModeSelector(
              role: session.effectiveRole,
              onSelected: ref.read(sessionProvider.notifier).setEffectiveRole,
            ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                MaintenanceDashboardScreen(),
                TicketListScreen(),
                NotificationsScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Inicio',
          ),
          const NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number),
            label: 'Tickets',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications),
            ),
            label: 'Notificaciones',
          ),
        ],
      ),
      persistentFooterButtons: const [
        Text(AppConfig.credits, style: TextStyle(fontSize: 10)),
      ],
    );
  }
}

enum _SessionAction { templates, areas, logout }

class _TestModeSelector extends StatelessWidget {
  const _TestModeSelector({required this.role, required this.onSelected});

  final AppRole role;
  final ValueChanged<AppRole> onSelected;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .4),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          const Icon(Icons.science_outlined, size: 19),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Modo de prueba',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          PopupMenuButton<AppRole>(
            key: const Key('test-mode-menu'),
            tooltip: 'Cambiar vista operativa',
            initialValue: role,
            onSelected: onSelected,
            itemBuilder: (_) => AppRole.values
                .map(
                  (value) => PopupMenuItem(
                    value: value,
                    child: Text('Vista ${value.label}'),
                  ),
                )
                .toList(),
            child: Chip(label: Text('Vista ${role.label}')),
          ),
        ],
      ),
    ),
  );
}
