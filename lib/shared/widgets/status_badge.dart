import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../features/maintenance/domain/ticket_enums.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});

  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final (baseColor, icon) = switch (status) {
      TicketStatus.pending => (AppColors.amber, Icons.schedule_rounded),
      TicketStatus.acknowledged => (
        AppColors.info,
        Icons.mark_email_read_outlined,
      ),
      TicketStatus.inProgress => (AppColors.primary, Icons.handyman_outlined),
      TicketStatus.closed => (AppColors.success, Icons.task_alt_outlined),
    };
    final color = AppColors.semantic(baseColor, Theme.of(context).brightness);
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
