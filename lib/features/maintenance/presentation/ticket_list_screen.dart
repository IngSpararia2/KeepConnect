import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/local_data_banner.dart';
import '../../auth/application/auth_providers.dart';
import '../application/maintenance_providers.dart';
import '../domain/maintenance_ticket.dart';
import '../domain/ticket_enums.dart';
import 'widgets/ticket_card.dart';

class TicketListScreen extends ConsumerStatefulWidget {
  const TicketListScreen({super.key, this.initialPreset});

  final String? initialPreset;

  @override
  ConsumerState<TicketListScreen> createState() => _TicketListScreenState();
}

class _TicketListScreenState extends ConsumerState<TicketListScreen> {
  final _searchController = TextEditingController();
  TicketStatus? _status;
  TicketPriority? _priority;
  bool? _productionStopped;
  var _historyOnly = false;

  @override
  void initState() {
    super.initState();
    _applyPreset(widget.initialPreset);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyPreset(String? preset) {
    switch (preset) {
      case 'pending':
        _status = TicketStatus.pending;
      case 'critical':
        _priority = TicketPriority.critical;
      case 'inProgress':
        _status = TicketStatus.inProgress;
      case 'waitingParts':
        _status = TicketStatus.waitingParts;
      case 'resolved':
        _status = TicketStatus.resolved;
      case 'history':
        _historyOnly = true;
    }
  }

  List<MaintenanceTicket> _filtered(
    List<MaintenanceTicket> tickets,
    String? currentUid,
  ) {
    final search = _searchController.text.trim().toLowerCase();
    return tickets
        .where((ticket) {
          if (widget.initialPreset == 'assignedToMe' &&
              ticket.primaryAssigneeUid != currentUid &&
              !ticket.participantUids.contains(currentUid)) {
            return false;
          }
          if (_status != null && ticket.status != _status) return false;
          if (_priority != null && ticket.priority != _priority) return false;
          if (_productionStopped != null &&
              ticket.productionStopped != _productionStopped) {
            return false;
          }
          if (_historyOnly && ticket.isOpen) return false;
          if (search.isEmpty) return true;
          return ticket.humanCode.toLowerCase().contains(search) ||
              ticket.title.toLowerCase().contains(search) ||
              (ticket.assetName?.toLowerCase().contains(search) ?? false);
        })
        .toList(growable: false);
  }

  void _clearFilters() {
    setState(() {
      _status = null;
      _priority = null;
      _productionStopped = null;
      _historyOnly = false;
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(ticketsProvider);
    final user = ref.watch(currentUserProfileProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tickets de mantenimiento'),
        actions: [
          IconButton(
            tooltip: 'Limpiar filtros',
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
        ],
      ),
      floatingActionButton:
          (user?.isProduction ?? false) || (user?.isAdmin ?? false)
          ? FloatingActionButton(
              tooltip: 'Crear solicitud',
              onPressed: () => context.push('/maintenance/tickets/new'),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Buscar por código, título o equipo',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _DropdownFilter<TicketStatus>(
                  hint: 'Estado',
                  value: _status,
                  values: TicketStatus.values,
                  label: (value) => value.label,
                  onChanged: (value) => setState(() => _status = value),
                ),
                const SizedBox(width: 8),
                _DropdownFilter<TicketPriority>(
                  hint: 'Prioridad',
                  value: _priority,
                  values: TicketPriority.values,
                  label: (value) => value.label,
                  onChanged: (value) => setState(() => _priority = value),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Producción detenida'),
                  selected: _productionStopped == true,
                  onSelected: (selected) => setState(
                    () => _productionStopped = selected ? true : null,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Historial'),
                  selected: _historyOnly,
                  onSelected: (selected) =>
                      setState(() => _historyOnly = selected),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: AsyncValueView(
              value: tickets,
              onRetry: () => ref.invalidate(ticketsProvider),
              data: (feed) {
                final filtered = _filtered(feed.tickets, user?.uid);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: LocalDataBanner(visible: feed.isFromCache),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const _EmptyTickets()
                          : RefreshIndicator(
                              onRefresh: () async =>
                                  ref.invalidate(ticketsProvider),
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  10,
                                  16,
                                  96,
                                ),
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final ticket = filtered[index];
                                  return TicketCard(
                                    ticket: ticket,
                                    onTap: () => context.push(
                                      '/maintenance/tickets/${ticket.id}',
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownFilter<T> extends StatelessWidget {
  const _DropdownFilter({
    required this.hint,
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
  });

  final String hint;
  final T? value;
  final List<T> values;
  final String Function(T value) label;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T?>(
      value: value,
      hint: Text(hint),
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(14),
      items: [
        DropdownMenuItem<T?>(value: null, child: Text('Todos: $hint')),
        ...values.map(
          (item) => DropdownMenuItem<T?>(value: item, child: Text(label(item))),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _EmptyTickets extends StatelessWidget {
  const _EmptyTickets();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 54),
            const SizedBox(height: 12),
            Text(
              'No hay tickets con estos filtros',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text('Cambie los filtros o cree una nueva solicitud.'),
          ],
        ),
      ),
    );
  }
}
