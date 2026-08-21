import { Timestamp, type DocumentReference } from "firebase-admin/firestore";
import type { BatchResponse, MulticastMessage } from "firebase-admin/messaging";
import { logger } from "firebase-functions";

import { stableHash } from "./audit";
import {
  MAX_NOTIFICATION_RECIPIENTS,
  NORMAL_NOTIFICATION_CHANNEL,
  URGENT_NOTIFICATION_CHANNEL,
  minutesFrom
} from "./config";
import { db, messaging } from "./firebase";
import type { NotificationDescriptor, TicketData } from "./types";

const INVALID_TOKEN_CODES = new Set([
  "messaging/invalid-argument",
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered"
]);

interface DeviceTarget {
  token: string;
  refs: DocumentReference[];
  tokenHash: string;
}

interface AcquiredJob {
  ref: DocumentReference;
  acquired: boolean;
  alreadySent: boolean;
  deliveredTokenHashes: Set<string>;
}

async function activeMaintenanceUids(departmentId: string): Promise<string[]> {
  const snapshot = await db
    .collection("users")
    .where("active", "==", true)
    .where("role", "==", "maintenance")
    .where("departmentId", "==", departmentId)
    .limit(MAX_NOTIFICATION_RECIPIENTS)
    .get();
  return snapshot.docs.map((document) => document.id);
}

async function activeAdminUids(): Promise<string[]> {
  const snapshot = await db
    .collection("users")
    .where("active", "==", true)
    .where("role", "==", "admin")
    .limit(500)
    .get();
  return snapshot.docs.map((document) => document.id);
}

async function filterActiveUids(uids: string[]): Promise<string[]> {
  const unique = [...new Set(uids)].slice(0, MAX_NOTIFICATION_RECIPIENTS);
  const active: string[] = [];
  for (let offset = 0; offset < unique.length; offset += 100) {
    const batch = unique.slice(offset, offset + 100);
    const snapshots = await db.getAll(...batch.map((uid) => db.doc(`users/${uid}`)));
    for (const snapshot of snapshots) {
      if (snapshot.exists && snapshot.data()?.active === true) active.push(snapshot.id);
    }
  }
  return active;
}

async function resolveRecipientUids(descriptor: NotificationDescriptor): Promise<string[]> {
  const requested = new Set(descriptor.recipientUids);
  if (descriptor.includeMaintenanceDepartmentId) {
    for (const uid of await activeMaintenanceUids(descriptor.includeMaintenanceDepartmentId)) {
      requested.add(uid);
    }
  }
  if (descriptor.includeAdmins) {
    for (const uid of await activeAdminUids()) requested.add(uid);
  }
  if (descriptor.actorUid) requested.delete(descriptor.actorUid);
  return filterActiveUids([...requested]);
}

async function resolveDevices(uids: string[]): Promise<DeviceTarget[]> {
  const candidates: Array<{
    uid: string;
    token: string;
    installationId: string;
    ref: DocumentReference;
  }> = [];
  for (let offset = 0; offset < uids.length; offset += 25) {
    const uidBatch = uids.slice(offset, offset + 25);
    const deviceSnapshots = await Promise.all(
      uidBatch.map((uid) => db.collection(`users/${uid}/devices`).get())
    );
    for (let snapshotIndex = 0; snapshotIndex < deviceSnapshots.length; snapshotIndex += 1) {
      const snapshot = deviceSnapshots[snapshotIndex];
      const uid = uidBatch[snapshotIndex];
      if (!snapshot || !uid) continue;
      for (const device of snapshot.docs) {
        const data = device.data();
        if (
          data.notificationsEnabled !== true ||
          typeof data.token !== "string" ||
          !data.token.trim()
        ) continue;
        const installationId = typeof data.installationId === "string"
          ? data.installationId
          : device.id;
        candidates.push({ uid, token: data.token.trim(), installationId, ref: device.ref });
      }
    }
  }

  const byToken = new Map<string, DocumentReference[]>();
  for (let offset = 0; offset < candidates.length; offset += 100) {
    const batch = candidates.slice(offset, offset + 100);
    const registryRefs = batch.map((candidate) =>
      db.doc(`device_installations/${candidate.installationId}`)
    );
    const registries = await db.getAll(...registryRefs);
    registries.forEach((registry, index) => {
      const candidate = batch[index];
      if (!candidate) return;
      const ownership = registry.data();
      const tokenHash = stableHash(candidate.token);
      if (ownership?.uid !== candidate.uid || ownership?.tokenHash !== tokenHash) return;
      const token = candidate.token;
      const refs = byToken.get(token) ?? [];
      refs.push(
        candidate.ref,
        registry.ref,
        db.doc(`device_tokens/${tokenHash}`)
      );
      byToken.set(token, refs);
    });
  }
  return [...byToken.entries()].map(([token, refs]) => ({
    token,
    refs,
    tokenHash: stableHash(token)
  }));
}

async function acquireJob(descriptor: NotificationDescriptor): Promise<AcquiredJob> {
  const jobId = stableHash(descriptor.eventId).slice(0, 64);
  const ref = db.doc(`notification_jobs/${jobId}`);
  const now = Timestamp.now();
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data() ?? {};
    if (data.status === "sent") {
      return { ref, acquired: false, alreadySent: true, deliveredTokenHashes: new Set<string>() };
    }
    const leaseUntil = data.leaseUntil;
    if (
      data.status === "processing" &&
      leaseUntil instanceof Timestamp &&
      leaseUntil.toMillis() > now.toMillis()
    ) {
      return {
        ref,
        acquired: false,
        alreadySent: false,
        deliveredTokenHashes: new Set<string>(
          Array.isArray(data.deliveredTokenHashes) ? data.deliveredTokenHashes : []
        )
      };
    }
    const attempts = typeof data.attempts === "number" ? data.attempts + 1 : 1;
    const deliveredTokenHashes = new Set<string>(
      Array.isArray(data.deliveredTokenHashes) ? data.deliveredTokenHashes : []
    );
    transaction.set(
      ref,
      {
        eventId: descriptor.eventId,
        eventType: descriptor.eventType,
        ticketId: descriptor.ticketId,
        actorUid: descriptor.actorUid,
        status: "processing",
        attempts,
        leaseUntil: minutesFrom(now, 2),
        updatedAt: now,
        createdAt: data.createdAt ?? now,
        deliveredTokenHashes: [...deliveredTokenHashes]
      },
      { merge: true }
    );
    return { ref, acquired: true, alreadySent: false, deliveredTokenHashes };
  });
}

function multicastMessage(
  descriptor: NotificationDescriptor,
  tokens: string[]
): MulticastMessage {
  const channelId = descriptor.urgent
    ? URGENT_NOTIFICATION_CHANNEL
    : NORMAL_NOTIFICATION_CHANNEL;
  return {
    tokens,
    notification: { title: descriptor.title, body: descriptor.body },
    data: {
      ticketId: descriptor.ticketId,
      eventId: descriptor.eventId,
      eventType: descriptor.eventType,
      route: `/maintenance/tickets/${descriptor.ticketId}`,
      priority: descriptor.priority,
      urgent: descriptor.urgent ? "true" : "false"
    },
    android: {
      priority: descriptor.urgent ? "high" : "normal",
      collapseKey: descriptor.eventId.slice(0, 64),
      notification: {
        channelId,
        priority: descriptor.urgent ? "max" : "default",
        sound: "default",
        defaultVibrateTimings: descriptor.urgent,
        visibility: "private",
        tag: stableHash(descriptor.eventId).slice(0, 32),
      }
    }
  };
}

async function deleteInvalidDevices(refs: DocumentReference[]): Promise<void> {
  if (refs.length === 0) return;
  const writer = db.bulkWriter();
  for (const ref of refs) writer.delete(ref);
  await writer.close();
}

function processBatchResponse(
  response: BatchResponse,
  targets: DeviceTarget[],
  delivered: Set<string>,
  invalidRefs: DocumentReference[]
): { transientFailure: boolean; errors: string[] } {
  let transientFailure = false;
  const errors: string[] = [];
  response.responses.forEach((result, index) => {
    const target = targets[index];
    if (!target) return;
    if (result.success) {
      delivered.add(target.tokenHash);
      return;
    }
    const code = result.error?.code ?? "messaging/unknown-error";
    errors.push(code);
    if (INVALID_TOKEN_CODES.has(code)) {
      invalidRefs.push(...target.refs);
    } else {
      transientFailure = true;
    }
  });
  return { transientFailure, errors };
}

export async function sendNotification(descriptor: NotificationDescriptor): Promise<void> {
  const job = await acquireJob(descriptor);
  if (job.alreadySent) return;
  if (!job.acquired) {
    throw new Error(`Notification job ${descriptor.eventId} is already being processed.`);
  }

  const recipientUids = await resolveRecipientUids(descriptor);
  const allTargets = await resolveDevices(recipientUids);
  const pendingTargets = allTargets.filter(
    (target) => !job.deliveredTokenHashes.has(target.tokenHash)
  );
  if (pendingTargets.length === 0) {
    await job.ref.set(
      {
        status: "sent",
        recipientCount: recipientUids.length,
        tokenCount: allTargets.length,
        sentAt: Timestamp.now(),
        leaseUntil: null,
        updatedAt: Timestamp.now()
      },
      { merge: true }
    );
    return;
  }

  const delivered = new Set(job.deliveredTokenHashes);
  const invalidRefs: DocumentReference[] = [];
  let transientFailure = false;
  const errors: string[] = [];
  for (let offset = 0; offset < pendingTargets.length; offset += 500) {
    const batch = pendingTargets.slice(offset, offset + 500);
    const response = await messaging.sendEachForMulticast(
      multicastMessage(descriptor, batch.map((target) => target.token))
    );
    const result = processBatchResponse(response, batch, delivered, invalidRefs);
    transientFailure ||= result.transientFailure;
    errors.push(...result.errors);
  }
  await deleteInvalidDevices(invalidRefs);

  const now = Timestamp.now();
  await job.ref.set(
    {
      status: transientFailure ? "failed" : "sent",
      recipientCount: recipientUids.length,
      tokenCount: allTargets.length,
      invalidTokenCount: invalidRefs.length,
      deliveredTokenHashes: [...delivered].slice(0, 5000),
      errors: [...new Set(errors)].slice(0, 20),
      sentAt: transientFailure ? null : now,
      failedAt: transientFailure ? now : null,
      leaseUntil: null,
      updatedAt: now
    },
    { merge: true }
  );

  if (transientFailure) {
    logger.error("FCM returned transient failures", {
      eventId: descriptor.eventId,
      ticketId: descriptor.ticketId,
      errors
    });
    throw new Error(`Transient FCM failure for ${descriptor.eventId}.`);
  }
}

export function ticketRecipientUids(ticket: TicketData): string[] {
  return [...new Set([
    ticket.requesterUid,
    ticket.primaryAssigneeUid,
    ...(Array.isArray(ticket.participantUids) ? ticket.participantUids : [])
  ].filter((uid): uid is string => typeof uid === "string" && uid.length > 0))];
}
