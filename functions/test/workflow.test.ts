import { describe, expect, it } from "vitest";

import { canTransition, TRANSITION_GRAPH, type TransitionContext } from "../src/workflow";

const maintenanceAssigned: TransitionContext = {
  role: "maintenance",
  isRequester: false,
  isMaintenanceForTicket: true,
  isAssignedParticipant: true
};

const productionRequester: TransitionContext = {
  role: "production",
  isRequester: true,
  isMaintenanceForTicket: false,
  isAssignedParticipant: false
};

describe("ticket workflow", () => {
  it("allows the intended maintenance path", () => {
    expect(canTransition("pending", "acknowledged", maintenanceAssigned)).toBe(true);
    expect(canTransition("acknowledged", "assigned", maintenanceAssigned)).toBe(true);
    expect(canTransition("assigned", "inProgress", maintenanceAssigned)).toBe(true);
    expect(canTransition("inProgress", "waitingParts", maintenanceAssigned)).toBe(true);
    expect(canTransition("waitingParts", "inProgress", maintenanceAssigned)).toBe(true);
    expect(canTransition("inProgress", "resolved", maintenanceAssigned)).toBe(true);
  });

  it("reserves closing and requesting review for the requester", () => {
    expect(canTransition("resolved", "closed", productionRequester)).toBe(true);
    expect(canTransition("resolved", "inProgress", productionRequester)).toBe(true);
    expect(canTransition("resolved", "closed", maintenanceAssigned)).toBe(false);
  });

  it("does not let production acknowledge or skip workflow states", () => {
    expect(canTransition("pending", "acknowledged", productionRequester)).toBe(false);
    expect(canTransition("pending", "inProgress", productionRequester)).toBe(false);
    expect(canTransition("pending", "resolved", productionRequester)).toBe(false);
  });

  it("allows only the requester to cancel a pending ticket", () => {
    expect(canTransition("pending", "cancelled", productionRequester)).toBe(true);
    expect(canTransition("assigned", "cancelled", productionRequester)).toBe(false);
  });

  it("requires an assigned maintenance participant for work changes", () => {
    const unassigned = { ...maintenanceAssigned, isAssignedParticipant: false };
    expect(canTransition("assigned", "inProgress", unassigned)).toBe(false);
    expect(canTransition("inProgress", "paused", unassigned)).toBe(false);
  });

  it("treats closed and cancelled as terminal", () => {
    expect(TRANSITION_GRAPH.closed).toEqual([]);
    expect(TRANSITION_GRAPH.cancelled).toEqual([]);
  });

  it("allows an admin only along declared graph edges", () => {
    const admin: TransitionContext = {
      role: "admin",
      isRequester: false,
      isMaintenanceForTicket: false,
      isAssignedParticipant: false
    };
    expect(canTransition("assigned", "cancelled", admin)).toBe(true);
    expect(canTransition("pending", "resolved", admin)).toBe(false);
  });
});
