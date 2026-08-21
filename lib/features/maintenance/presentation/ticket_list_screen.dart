import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_providers.dart';
import '../application/maintenance_providers.dart';
import '../domain/ticket_enums.dart';
import 'widgets/ticket_card.dart';

class TicketListScreen extends ConsumerStatefulWidget {
  const TicketListScreen({super.key});
  @override
  ConsumerState<TicketListScreen> createState() => _TicketListScreenState();
}

class _TicketListScreenState extends ConsumerState<TicketListScreen> {
  TicketStatus? _status;
  TicketPriority? _priority;
  @override
  Widget build(BuildContext context) => ref
      .watch(ticketsProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (tickets) {
          final filtered = tickets
              .where(
                (ticket) =>
                    (_status == null || ticket.status == _status) &&
                    (_priority == null || ticket.priority == _priority),
              )
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<TicketStatus?>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                          labelText: 'Estado',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Todos'),
                          ),
                          ...TicketStatus.values.map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _status = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<TicketPriority?>(
                        initialValue: _priority,
                        decoration: const InputDecoration(
                          labelText: 'Prioridad',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Todas'),
                          ),
                          ...TicketPriority.values.map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _priority = value),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('No hay tickets con estos filtros.'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) => TicketCard(
                          ticket: filtered[index],
                          onTap: () =>
                              context.push('/tickets/${filtered[index].id}'),
                        ),
                      ),
              ),
              if (ref.watch(sessionProvider).role == AppRole.production)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => context.push('/tickets/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Crear solicitud'),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}
