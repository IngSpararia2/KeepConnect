import { Timestamp } from "firebase-admin/firestore";
import { describe, expect, it } from "vitest";

import {
  manualEscalationAllowed,
  nextManualEscalationAt
} from "../src/escalation";

describe("manual escalation cooldown", () => {
  const last = Timestamp.fromMillis(1_000_000);
  const cooldownMinutes = 15;
  const boundary = last.toMillis() + cooldownMinutes * 60_000;

  it("allows the first escalation", () => {
    expect(manualEscalationAllowed(last, null, cooldownMinutes)).toBe(true);
    expect(nextManualEscalationAt(null, cooldownMinutes)).toBeNull();
  });

  it("rejects an escalation immediately before the boundary", () => {
    expect(
      manualEscalationAllowed(
        Timestamp.fromMillis(boundary - 1),
        last,
        cooldownMinutes
      )
    ).toBe(false);
  });

  it("allows an escalation exactly at and after the boundary", () => {
    expect(
      manualEscalationAllowed(Timestamp.fromMillis(boundary), last, cooldownMinutes)
    ).toBe(true);
    expect(
      manualEscalationAllowed(Timestamp.fromMillis(boundary + 1), last, cooldownMinutes)
    ).toBe(true);
  });
});
