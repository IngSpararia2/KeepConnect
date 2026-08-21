import '../../auth/domain/app_user.dart';
import 'ticket_enums.dart';

abstract final class StatusTransitionPolicy {
  static const Map<TicketStatus, Set<TicketStatus>> _graph = {
    TicketStatus.pending: {TicketStatus.acknowledged, TicketStatus.cancelled},
    TicketStatus.acknowledged: {TicketStatus.assigned, TicketStatus.cancelled},
    TicketStatus.assigned: {TicketStatus.inProgress, TicketStatus.cancelled},
    TicketStatus.inProgress: {
      TicketStatus.waitingParts,
      TicketStatus.waitingExternal,
      TicketStatus.paused,
      TicketStatus.resolved,
    },
    TicketStatus.waitingParts: {TicketStatus.inProgress},
    TicketStatus.waitingExternal: {TicketStatus.inProgress},
    TicketStatus.paused: {TicketStatus.inProgress},
    TicketStatus.resolved: {TicketStatus.closed, TicketStatus.inProgress},
    TicketStatus.closed: {},
    TicketStatus.cancelled: {},
  };

  static bool canTransition({
    required TicketStatus from,
    required TicketStatus to,
    required UserRole role,
    required bool isRequester,
    required bool isAssignee,
  }) {
    if (!(_graph[from]?.contains(to) ?? false)) return false;
    if (role == UserRole.admin) return true;

    if (to == TicketStatus.cancelled) {
      return from == TicketStatus.pending &&
          role == UserRole.production &&
          isRequester;
    }
    if (from == TicketStatus.resolved &&
        (to == TicketStatus.closed || to == TicketStatus.inProgress)) {
      return role == UserRole.production && isRequester;
    }
    if (role != UserRole.maintenance) return false;

    if (from == TicketStatus.pending && to == TicketStatus.acknowledged) {
      return true;
    }
    if (from == TicketStatus.acknowledged && to == TicketStatus.assigned) {
      return true;
    }
    return isAssignee;
  }

  static List<TicketStatus> allowedTargets({
    required TicketStatus from,
    required UserRole role,
    required bool isRequester,
    required bool isAssignee,
  }) {
    return (_graph[from] ?? const <TicketStatus>{})
        .where(
          (target) => canTransition(
            from: from,
            to: target,
            role: role,
            isRequester: isRequester,
            isAssignee: isAssignee,
          ),
        )
        .toList(growable: false);
  }
}
