import 'package:flutter/material.dart';

import '../../../../core/utils/date_time_formatters.dart';
import '../../../../shared/widgets/priority_badge.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../domain/maintenance_ticket.dart';

class TicketCard extends StatelessWidget {
  const TicketCard({required this.ticket, required this.onTap, super.key});

  final MaintenanceTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.humanCode,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  PriorityBadge(ticket.priority, compact: true),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                ticket.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(ticket.status),
                  if (ticket.productionStopped)
                    _CriticalFact(
                      icon: Icons.factory_outlined,
                      text: 'PRODUCCIÓN DETENIDA',
                      color: scheme.error,
                    ),
                  if (ticket.safetyRisk)
                    _CriticalFact(
                      icon: Icons.health_and_safety_outlined,
                      text: 'RIESGO DE SEGURIDAD',
                      color: scheme.error,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 17),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      [
                        if (ticket.assetName?.isNotEmpty == true)
                          ticket.assetName,
                        if (ticket.location.isNotEmpty) ticket.location,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppDateTime.dateTime(ticket.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CriticalFact extends StatelessWidget {
  const _CriticalFact({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}
