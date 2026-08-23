import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../../../config/app_config.dart';
import '../application/maintenance_providers.dart';
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
            _ContextLabel(session: session),
          ],
        ),
        actions: [
          PopupMenuButton<_SessionAction>(
            key: const Key('session-menu'),
            tooltip: 'Cuenta y áreas',
            onSelected: (action) async {
              if (action == _SessionAction.admin) {
                context.push('/admin');
                return;
              }
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
              if (session.isSuperAdmin)
                const PopupMenuItem(
                  value: _SessionAction.admin,
                  child: ListTile(
                    leading: Icon(Icons.admin_panel_settings_outlined),
                    title: Text('Administración'),
                  ),
                ),
              if (session.isSuperAdmin)
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

enum _SessionAction { admin, templates, areas, logout }

class _ContextLabel extends ConsumerWidget {
  const _ContextLabel({required this.session});
  final SessionState session;

  Future<String> _load(WidgetRef ref) async {
    final repository = ref.read(organizationRepositoryProvider);
    final company = await repository.getCompany(session.companyId!);
    final area = await repository.getArea(session.areaId!);
    return '${company?.name ?? 'Empresa'} · ${area?.name ?? 'Área'}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<String>(
    future: _load(ref),
    builder: (context, snapshot) {
      return Text(
        '${snapshot.data ?? 'Empresa · Área'} · ${session.effectiveRole.label}',
        style: Theme.of(context).textTheme.labelMedium,
      );
    },
  );
}
