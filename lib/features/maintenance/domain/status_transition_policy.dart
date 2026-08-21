import 'ticket_enums.dart';

abstract final class StatusTransitionPolicy {
  static const _graph = <TicketStatus, TicketStatus>{
    TicketStatus.pending: TicketStatus.acknowledged,
    TicketStatus.acknowledged: TicketStatus.inProgress,
    TicketStatus.inProgress: TicketStatus.closed,
  };
  static bool canTransition({
    required TicketStatus from,
    required TicketStatus to,
    required AppRole role,
  }) => role == AppRole.maintenance && _graph[from] == to;
  static TicketStatus? next(TicketStatus from, AppRole role) =>
      role == AppRole.maintenance ? _graph[from] : null;
}
