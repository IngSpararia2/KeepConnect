import { Timestamp } from "firebase-admin/firestore";

import { db } from "./firebase";
import type { MaintenanceSettings, PriorityPolicy } from "./types";

export const FUNCTION_REGION = "us-central1";
export const DISPLAY_TIME_ZONE = "America/Bogota";
export const NORMAL_NOTIFICATION_CHANNEL = "gestion_interna_normal_v1";
export const URGENT_NOTIFICATION_CHANNEL = "gestion_interna_urgent_v1";
export const MAX_NOTIFICATION_RECIPIENTS = 5000;
export const MAX_PARTICIPANTS = 20;

export const DEFAULT_PRIORITY_POLICY: PriorityPolicy = {
  version: "demo-v1",
  productionStoppedWeight: 5,
  safetyRiskWeight: 7,
  criticalAssetWeight: 2,
  moderateImpactWeight: 1,
  severeImpactWeight: 2,
  moderateImpactFromPercentage: 25,
  severeImpactFromPercentage: 75,
  mediumThreshold: 2,
  highThreshold: 5,
  criticalThreshold: 7,
  safetyRiskMinimumPriority: "critical",
  stoppedCriticalAssetMinimumPriority: "critical"
};

export const DEFAULT_MAINTENANCE_SETTINGS: MaintenanceSettings = {
  automaticEscalationEnabled: true,
  criticalAcknowledgementMinutes: 30,
  highAcknowledgementMinutes: 120,
  manualEscalationCooldownMinutes: 15,
  automaticEscalationRepeatMinutes: 30,
  maximumAutomaticEscalationLevel: 3,
  maxPhotosPerTicket: 5,
  maxPhotoBytes: 5 * 1024 * 1024,
  priorityPolicy: DEFAULT_PRIORITY_POLICY
};

function finiteNumber(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number
): number {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.min(maximum, Math.max(minimum, value))
    : fallback;
}

function priorityPolicyFrom(value: unknown): PriorityPolicy {
  const raw = typeof value === "object" && value !== null
    ? (value as Record<string, unknown>)
    : {};
  const defaults = DEFAULT_PRIORITY_POLICY;
  const minimum = (candidate: unknown, fallback: "critical") =>
    candidate === "low" || candidate === "medium" || candidate === "high" || candidate === "critical"
      ? candidate
      : fallback;

  return {
    version: typeof raw.version === "string" && raw.version.trim()
      ? raw.version.trim().slice(0, 80)
      : defaults.version,
    productionStoppedWeight: finiteNumber(raw.productionStoppedWeight, defaults.productionStoppedWeight, 0, 100),
    safetyRiskWeight: finiteNumber(raw.safetyRiskWeight, defaults.safetyRiskWeight, 0, 100),
    criticalAssetWeight: finiteNumber(raw.criticalAssetWeight, defaults.criticalAssetWeight, 0, 100),
    moderateImpactWeight: finiteNumber(raw.moderateImpactWeight, defaults.moderateImpactWeight, 0, 100),
    severeImpactWeight: finiteNumber(raw.severeImpactWeight, defaults.severeImpactWeight, 0, 100),
    moderateImpactFromPercentage: finiteNumber(raw.moderateImpactFromPercentage, defaults.moderateImpactFromPercentage, 0, 100),
    severeImpactFromPercentage: finiteNumber(raw.severeImpactFromPercentage, defaults.severeImpactFromPercentage, 0, 100),
    mediumThreshold: finiteNumber(raw.mediumThreshold, defaults.mediumThreshold, 0, 1000),
    highThreshold: finiteNumber(raw.highThreshold, defaults.highThreshold, 0, 1000),
    criticalThreshold: finiteNumber(raw.criticalThreshold, defaults.criticalThreshold, 0, 1000),
    safetyRiskMinimumPriority: minimum(raw.safetyRiskMinimumPriority, "critical"),
    stoppedCriticalAssetMinimumPriority: minimum(raw.stoppedCriticalAssetMinimumPriority, "critical")
  };
}

export async function readMaintenanceSettings(): Promise<MaintenanceSettings> {
  const snapshot = await db.doc("settings/maintenance").get();
  if (!snapshot.exists) {
    return DEFAULT_MAINTENANCE_SETTINGS;
  }

  const raw = snapshot.data() ?? {};
  const defaults = DEFAULT_MAINTENANCE_SETTINGS;
  return {
    automaticEscalationEnabled:
      typeof raw.automaticEscalationEnabled === "boolean"
        ? raw.automaticEscalationEnabled
        : defaults.automaticEscalationEnabled,
    criticalAcknowledgementMinutes: finiteNumber(
      raw.criticalAcknowledgementMinutes,
      defaults.criticalAcknowledgementMinutes,
      1,
      10080
    ),
    highAcknowledgementMinutes: finiteNumber(
      raw.highAcknowledgementMinutes,
      defaults.highAcknowledgementMinutes,
      1,
      10080
    ),
    manualEscalationCooldownMinutes: finiteNumber(
      raw.manualEscalationCooldownMinutes,
      defaults.manualEscalationCooldownMinutes,
      1,
      1440
    ),
    automaticEscalationRepeatMinutes: finiteNumber(
      raw.automaticEscalationRepeatMinutes,
      defaults.automaticEscalationRepeatMinutes,
      1,
      10080
    ),
    maximumAutomaticEscalationLevel: finiteNumber(
      raw.maximumAutomaticEscalationLevel,
      defaults.maximumAutomaticEscalationLevel,
      1,
      20
    ),
    maxPhotosPerTicket: finiteNumber(raw.maxPhotosPerTicket, defaults.maxPhotosPerTicket, 1, 30),
    maxPhotoBytes: finiteNumber(raw.maxPhotoBytes, defaults.maxPhotoBytes, 100_000, 10 * 1024 * 1024),
    priorityPolicy: priorityPolicyFrom(raw.priorityPolicy)
  };
}

export function minutesFrom(now: Timestamp, minutes: number): Timestamp {
  return Timestamp.fromMillis(now.toMillis() + minutes * 60_000);
}

export function bogotaDateKey(date = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: DISPLAY_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).formatToParts(date);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((entry) => entry.type === type)?.value ?? "00";
  return `${part("year")}${part("month")}${part("day")}`;
}
