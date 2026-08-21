import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../features/maintenance/domain/ticket_enums.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});

  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      TicketStatus.pending => (AppColors.amber, Icons.schedule_rounded),
      TicketStatus.acknowledged => (
        AppColors.info,
        Icons.mark_email_read_outlined,
      ),
      TicketStatus.assigned => (AppColors.info, Icons.assignment_ind_outlined),
      TicketStatus.inProgress => (AppColors.teal, Icons.handyman_outlined),
      TicketStatus.waitingParts => (
        AppColors.amber,
        Icons.inventory_2_outlined,
      ),
      TicketStatus.waitingExternal => (
        AppColors.amber,
        Icons.local_shipping_outlined,
      ),
      TicketStatus.paused => (Colors.deepOrange, Icons.pause_circle_outline),
      TicketStatus.resolved => (AppColors.success, Icons.task_alt_outlined),
      TicketStatus.closed => (Colors.blueGrey, Icons.lock_outline),
      TicketStatus.cancelled => (AppColors.danger, Icons.cancel_outlined),
    };
    return Semantics(
      label: 'Estado ${status.label}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              status.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
