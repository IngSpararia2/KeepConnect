import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../features/maintenance/domain/ticket_enums.dart';

class PriorityBadge extends StatelessWidget {
  const PriorityBadge(this.priority, {super.key, this.compact = false});

  final TicketPriority priority;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (priority) {
      TicketPriority.low => (AppColors.success, Icons.arrow_downward_rounded),
      TicketPriority.medium => (AppColors.info, Icons.remove_rounded),
      TicketPriority.high => (AppColors.amber, Icons.arrow_upward_rounded),
      TicketPriority.critical => (
        AppColors.danger,
        Icons.warning_amber_rounded,
      ),
    };
    return Semantics(
      label: 'Prioridad ${priority.label}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 5 : 7,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 15 : 17, color: color),
            const SizedBox(width: 5),
            Text(
              priority.label.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w800,
                letterSpacing: .35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
