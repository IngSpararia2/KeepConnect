import { Timestamp } from "firebase-admin/firestore";
import { describe, expect, it } from "vitest";

import {
  DEFAULT_MAINTENANCE_SETTINGS,
  DEFAULT_PRIORITY_POLICY
} from "../src/config";
import {
  isPriorityLower,
  nextAcknowledgementEscalationAt,
  suggestPriority
} from "../src/priority";

describe("suggestPriority", () => {
  it("suggests low for an issue without impact factors", () => {
    expect(
      suggestPriority(
        {
          productionStopped: false,
          safetyRisk: false,
          criticalAsset: false,
          impactPercentage: 0
        },
        DEFAULT_PRIORITY_POLICY
      )
    ).toMatchObject({ priority: "low", score: 0, factors: [] });
  });

  it("makes a stopped critical asset critical", () => {
    const result = suggestPriority(
      {
        productionStopped: true,
        safetyRisk: false,
        criticalAsset: true,
        impactPercentage: 20
      },
      DEFAULT_PRIORITY_POLICY
    );
    expect(result.priority).toBe("critical");
    expect(result.factors).toEqual(expect.arrayContaining(["productionStopped", "criticalAsset"]));
  });

  it("never recommends below the configured safety minimum", () => {
    const result = suggestPriority(
      {
        productionStopped: false,
        safetyRisk: true,
        criticalAsset: false,
        impactPercentage: null
      },
      { ...DEFAULT_PRIORITY_POLICY, safetyRiskWeight: 0 }
    );
    expect(result.priority).toBe("critical");
  });

  it("applies the severe impact band once", () => {
    const result = suggestPriority(
      {
        productionStopped: false,
        safetyRisk: false,
        criticalAsset: false,
        impactPercentage: 75
      },
      DEFAULT_PRIORITY_POLICY
    );
    expect(result.score).toBe(DEFAULT_PRIORITY_POLICY.severeImpactWeight);
    expect(result.factors).toEqual(["severeImpact"]);
  });
});

describe("priority comparison and escalation deadline", () => {
  it("detects a downgrade", () => {
    expect(isPriorityLower("medium", "high")).toBe(true);
    expect(isPriorityLower("critical", "high")).toBe(false);
  });

  it("schedules only high and critical acknowledgement escalation", () => {
    const now = Timestamp.fromMillis(1_000_000);
    expect(
      nextAcknowledgementEscalationAt(now, "critical", DEFAULT_MAINTENANCE_SETTINGS)?.toMillis()
    ).toBe(now.toMillis() + 30 * 60_000);
    expect(
      nextAcknowledgementEscalationAt(now, "high", DEFAULT_MAINTENANCE_SETTINGS)?.toMillis()
    ).toBe(now.toMillis() + 120 * 60_000);
    expect(nextAcknowledgementEscalationAt(now, "medium", DEFAULT_MAINTENANCE_SETTINGS)).toBeNull();
  });
});
