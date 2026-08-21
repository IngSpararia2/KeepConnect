import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
              'Área Planta · Vista ${session.role.label}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        actions: [
          PopupMenuButton<AppRole>(
            key: const Key('test-mode-menu'),
            tooltip: 'Modo de prueba',
            initialValue: session.role,
            onSelected: ref.read(sessionProvider.notifier).setRole,
            itemBuilder: (_) => AppRole.values
                .map(
                  (role) => PopupMenuItem(
                    value: role,
                    child: Row(
                      children: [
                        Icon(
                          role == AppRole.production
                              ? Icons.factory_outlined
                              : Icons.handyman_outlined,
                        ),
                        const SizedBox(width: 10),
                        Text('Vista ${role.label}'),
                      ],
                    ),
                  ),
                )
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Chip(
                avatar: const Icon(Icons.science_outlined, size: 18),
                label: Text('Modo de prueba: ${session.role.label}'),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          MaintenanceDashboardScreen(),
          TicketListScreen(),
          NotificationsScreen(),
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
