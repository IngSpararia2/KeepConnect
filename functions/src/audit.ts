import { createHash } from "node:crypto";

import type { DocumentReference, Timestamp, Transaction } from "firebase-admin/firestore";

import type { Actor, AuditEventData, LastMutation } from "./types";

export function stableHash(...parts: string[]): string {
  return createHash("sha256").update(parts.join("\u001f")).digest("hex");
}

export function commandEventId(
  actorUid: string,
  command: string,
  requestId: string
): string {
  return `cmd_${stableHash(actorUid, command, requestId).slice(0, 40)}`;
}

export function commandReceiptId(actorUid: string, command: string, requestId: string): string {
  return stableHash(actorUid, command, requestId);
}

export function systemEventId(prefix: string, resourceId: string, marker: string): string {
  return `${prefix}_${stableHash(resourceId, marker).slice(0, 40)}`;
}

export function lastMutation(
  id: string,
  type: string,
  actor: Actor | null,
  now: Timestamp
): LastMutation {
  return {
    id,
    type,
    actorUid: actor?.uid ?? null,
    actorName: actor?.name ?? "Sistema",
    at: now
  };
}

export function writeAuditEvent(
  transaction: Transaction,
  eventRef: DocumentReference,
  input: {
    type: string;
    actor: Actor | null;
    now: Timestamp;
    previousValue: unknown;
    newValue: unknown;
    message: string;
    metadata?: Record<string, unknown>;
    correlationId: string;
    source: AuditEventData["source"];
  }
): void {
  const event: AuditEventData = {
    type: input.type,
    actorUid: input.actor?.uid ?? null,
    actorName: input.actor?.name ?? "Sistema",
    actorRole: input.actor?.role ?? "system",
    createdAt: input.now,
    previousValue: input.previousValue,
    newValue: input.newValue,
    message: input.message,
    metadata: input.metadata ?? {},
    correlationId: input.correlationId,
    source: input.source
  };
  transaction.create(eventRef, event);
}
