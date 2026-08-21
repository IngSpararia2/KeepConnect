import { minutesFrom } from "./config";
import type {
  MaintenanceSettings,
  Priority,
  PriorityPolicy,
  PrioritySuggestion
} from "./types";
import type { Timestamp } from "firebase-admin/firestore";

export const PRIORITY_RANK: Record<Priority, number> = {
  low: 1,
  medium: 2,
  high: 3,
  critical: 4
};

function fromScore(score: number, policy: PriorityPolicy): Priority {
  if (score >= policy.criticalThreshold) return "critical";
  if (score >= policy.highThreshold) return "high";
  if (score >= policy.mediumThreshold) return "medium";
  return "low";
}

function atLeast(priority: Priority, minimum: Priority): Priority {
  return PRIORITY_RANK[priority] >= PRIORITY_RANK[minimum] ? priority : minimum;
}

export function suggestPriority(
  input: {
    productionStopped: boolean;
    safetyRisk: boolean;
    criticalAsset: boolean;
    impactPercentage: number | null;
  },
  policy: PriorityPolicy
): PrioritySuggestion {
  let score = 0;
  const factors: string[] = [];

  if (input.productionStopped) {
    score += policy.productionStoppedWeight;
    factors.push("productionStopped");
  }
  if (input.safetyRisk) {
    score += policy.safetyRiskWeight;
    factors.push("safetyRisk");
  }
  if (input.criticalAsset) {
    score += policy.criticalAssetWeight;
    factors.push("criticalAsset");
  }
  if (
    input.impactPercentage !== null &&
    input.impactPercentage >= policy.severeImpactFromPercentage
  ) {
    score += policy.severeImpactWeight;
    factors.push("severeImpact");
  } else if (
    input.impactPercentage !== null &&
    input.impactPercentage >= policy.moderateImpactFromPercentage
  ) {
    score += policy.moderateImpactWeight;
    factors.push("moderateImpact");
  }

  let priority = fromScore(score, policy);
  if (input.safetyRisk) {
    priority = atLeast(priority, policy.safetyRiskMinimumPriority);
  }
  if (input.productionStopped && input.criticalAsset) {
    priority = atLeast(priority, policy.stoppedCriticalAssetMinimumPriority);
  }

  return { priority, score, factors, policyVersion: policy.version };
}

export function isPriorityLower(candidate: Priority, reference: Priority): boolean {
  return PRIORITY_RANK[candidate] < PRIORITY_RANK[reference];
}

export function nextAcknowledgementEscalationAt(
  now: Timestamp,
  priority: Priority,
  settings: MaintenanceSettings
): Timestamp | null {
  if (!settings.automaticEscalationEnabled) return null;
  if (priority === "critical") {
    return minutesFrom(now, settings.criticalAcknowledgementMinutes);
  }
  if (priority === "high") {
    return minutesFrom(now, settings.highAcknowledgementMinutes);
  }
  return null;
}
