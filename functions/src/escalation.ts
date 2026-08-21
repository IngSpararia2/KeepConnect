import type { Timestamp } from "firebase-admin/firestore";

import { minutesFrom } from "./config";

export function nextManualEscalationAt(
  lastEscalationAt: Timestamp | null,
  cooldownMinutes: number
): Timestamp | null {
  return lastEscalationAt ? minutesFrom(lastEscalationAt, cooldownMinutes) : null;
}

export function manualEscalationAllowed(
  now: Timestamp,
  lastEscalationAt: Timestamp | null,
  cooldownMinutes: number
): boolean {
  const nextAllowedAt = nextManualEscalationAt(lastEscalationAt, cooldownMinutes);
  return nextAllowedAt === null || now.toMillis() >= nextAllowedAt.toMillis();
}
