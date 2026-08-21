import { HttpsError } from "firebase-functions/v2/https";

import type { Role, TicketStatus } from "./types";

export const TRANSITION_GRAPH: Readonly<Record<TicketStatus, readonly TicketStatus[]>> = {
  pending: ["acknowledged", "cancelled"],
  acknowledged: ["assigned", "cancelled"],
  assigned: ["inProgress", "cancelled"],
  inProgress: ["waitingParts", "waitingExternal", "paused", "resolved"],
  waitingParts: ["inProgress"],
  waitingExternal: ["inProgress"],
  paused: ["inProgress"],
  resolved: ["closed", "inProgress"],
  closed: [],
  cancelled: []
};

export interface TransitionContext {
  role: Role;
  isRequester: boolean;
  isMaintenanceForTicket: boolean;
  isAssignedParticipant: boolean;
}

export function canTransition(
  from: TicketStatus,
  to: TicketStatus,
  context: TransitionContext
): boolean {
  if (!TRANSITION_GRAPH[from].includes(to)) return false;

  if (context.role === "admin") return true;

  if (to === "cancelled") {
    return from === "pending" && context.isRequester;
  }
  if (from === "resolved" && (to === "closed" || to === "inProgress")) {
    return context.isRequester;
  }
  if (from === "pending" && to === "acknowledged") {
    return context.isMaintenanceForTicket;
  }
  if (from === "acknowledged" && to === "assigned") {
    return context.isMaintenanceForTicket;
  }
  if (from === "assigned" && to === "inProgress") {
    return context.isMaintenanceForTicket && context.isAssignedParticipant;
  }
  if (
    from === "inProgress" ||
    from === "waitingParts" ||
    from === "waitingExternal" ||
    from === "paused"
  ) {
    return context.isMaintenanceForTicket && context.isAssignedParticipant;
  }
  return false;
}

export function assertTransition(
  from: TicketStatus,
  to: TicketStatus,
  context: TransitionContext
): void {
  if (!canTransition(from, to, context)) {
    throw new HttpsError(
      "failed-precondition",
      `No está permitido cambiar el ticket de ${from} a ${to} para este usuario.`
    );
  }
}
