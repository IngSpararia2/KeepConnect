import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/local_data_banner.dart';
import '../../auth/application/auth_providers.dart';
import '../application/maintenance_providers.dart';
import '../domain/maintenance_ticket.dart';
import '../domain/ticket_enums.dart';

class MaintenanceDashboardScreen extends ConsumerWidget {
  const MaintenanceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProfileProvider).value;
    final tickets = ref.watch(ticketsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mantenimiento'),
        leading: IconButton(
          tooltip: 'Volver al inicio',
          onPressed: () => context.go('/home'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Buscar y filtrar tickets',
            onPressed: () => context.push('/maintenance/tickets'),
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton:
          (user?.isProduction ?? false) || (user?.isAdmin ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/maintenance/tickets/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crear solicitud'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(ticketsProvider),
        child: AsyncValueView(
          value: tickets,
          onRetry: () => ref.invalidate(ticketsProvider),
          data: (feed) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              LocalDataBanner(visible: feed.isFromCache),
              Text(
                _headingForRole(user?.role),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Indicadores calculados sobre los tickets recientes autorizados para su perfil.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _DashboardGrid(
                cards: _cardsFor(feed.tickets, user?.uid),
                onTap: (preset) => context.push(
                  Uri(
                    path: '/maintenance/tickets',
                    queryParameters: {'preset': preset},
                  ).toString(),
                ),
              ),
              const SizedBox(height: 22),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  leading: const Icon(Icons.view_list_outlined),
                  title: const Text(
                    'Todos los tickets',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('Buscador, filtros e historial'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/maintenance/tickets'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _headingForRole(Object? role) => switch (role?.toString()) {
    'UserRole.production' => 'Mis solicitudes',
    'UserRole.maintenance' => 'Solicitudes recibidas',
    _ => 'Panel general',
  };

  static List<_DashboardCardData> _cardsFor(
    List<MaintenanceTicket> tickets,
    String? uid,
  ) {
    int count(bool Function(MaintenanceTicket) predicate) =>
        tickets.where(predicate).length;
    return [
      _DashboardCardData(
        label: 'Pendientes',
        value: count((t) => t.status == TicketStatus.pending),
        icon: Icons.schedule_rounded,
        preset: 'pending',
      ),
      _DashboardCardData(
        label: 'Críticas',
        value: count((t) => t.priority == TicketPriority.critical && t.isOpen),
        icon: Icons.warning_amber_rounded,
        preset: 'critical',
        critical: true,
      ),
      _DashboardCardData(
        label: 'En proceso',
        value: count((t) => t.status == TicketStatus.inProgress),
        icon: Icons.handyman_outlined,
        preset: 'inProgress',
      ),
      _DashboardCardData(
        label: 'Esperando repuesto',
        value: count((t) => t.status == TicketStatus.waitingParts),
        icon: Icons.inventory_2_outlined,
        preset: 'waitingParts',
      ),
      _DashboardCardData(
        label: 'Por confirmar',
        value: count((t) => t.status == TicketStatus.resolved),
        icon: Icons.fact_check_outlined,
        preset: 'resolved',
      ),
      _DashboardCardData(
        label: 'Asignadas a mí',
        value: count(
          (t) =>
              (t.primaryAssigneeUid == uid ||
                  t.participantUids.contains(uid)) &&
              t.isOpen,
        ),
        icon: Icons.assignment_ind_outlined,
        preset: 'assignedToMe',
      ),
    ];
  }
}

class _DashboardGrid extends StatelessWidget {
  const _DashboardGrid({required this.cards, required this.onTap});

  final List<_DashboardCardData> cards;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: columns == 3 ? 1.45 : 1.18,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) {
            final card = cards[index];
            final color = card.critical
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary;
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onTap(card.preset),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(card.icon, color: color),
                      const Spacer(),
                      Text(
                        '${card.value}',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: color,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        card.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DashboardCardData {
  const _DashboardCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.preset,
    this.critical = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final String preset;
  final bool critical;
}
