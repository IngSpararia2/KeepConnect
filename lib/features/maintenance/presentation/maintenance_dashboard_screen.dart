import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../application/maintenance_providers.dart';
import '../domain/ticket_enums.dart';

class MaintenanceDashboardScreen extends ConsumerWidget {
  const MaintenanceDashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider).role;
    return ref
        .watch(ticketsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('No fue posible cargar: $error')),
          data: (tickets) {
            int count(TicketStatus status) =>
                tickets.where((t) => t.status == status).length;
            final critical = tickets
                .where((t) => t.priority == TicketPriority.critical && t.isOpen)
                .length;
            final cards = [
              (
                'Pendientes',
                count(TicketStatus.pending),
                Icons.schedule_rounded,
              ),
              (
                'En revisión',
                count(TicketStatus.acknowledged),
                Icons.fact_check_outlined,
              ),
              (
                'En ejecución',
                count(TicketStatus.inProgress),
                Icons.handyman_outlined,
              ),
              (
                'Finalizados',
                count(TicketStatus.closed),
                Icons.task_alt_outlined,
              ),
              ('Críticos abiertos', critical, Icons.warning_amber_rounded),
            ];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (role == AppRole.production) ...[
                  FilledButton.icon(
                    key: const Key('create-ticket'),
                    onPressed: () => context.push('/tickets/new'),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Crear solicitud'),
                  ),
                  const SizedBox(height: 18),
                ],
                LayoutBuilder(
                  builder: (_, constraints) => GridView.count(
                    crossAxisCount: constraints.maxWidth >= 700 ? 3 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.35,
                    children: [
                      for (final item in cards)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  item.$3,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const Spacer(),
                                Text(
                                  '${item.$2}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                Text(item.$1),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
  }
}
