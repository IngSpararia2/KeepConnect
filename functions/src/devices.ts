import { Timestamp, type DocumentReference } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { stableHash } from "./audit";
import { requireActor } from "./auth";
import { FUNCTION_REGION } from "./config";
import { db } from "./firebase";
import {
  asRecord,
  optionalInteger,
  requiredBoolean,
  requiredString
} from "./validation";

const OPTIONS = {
  region: FUNCTION_REGION,
  timeoutSeconds: 30,
  memory: "256MiB" as const,
  maxInstances: 30,
  enforceAppCheck: false
};

function installationIdFrom(data: Record<string, unknown>): string {
  const installationId = requiredString(data, "installationId", 128, 8);
  if (!/^[A-Za-z0-9_-]+$/.test(installationId)) {
    throw new HttpsError("invalid-argument", "installationId no es válido.");
  }
  return installationId;
}

function addDeletion(
  deletions: Map<string, DocumentReference>,
  reference: DocumentReference,
  protectedPaths: Set<string>
): void {
  if (!protectedPaths.has(reference.path)) deletions.set(reference.path, reference);
}

export const registerDevice = onCall(OPTIONS, async (request) => {
  const actor = await requireActor(request);
  const data = asRecord(request.data);
  const installationId = installationIdFrom(data);
  const token = requiredString(data, "token", 4096, 20);
  const platform = requiredString(data, "platform", 20);
  const applicationId = requiredString(data, "applicationId", 200);
  const notificationsEnabled = requiredBoolean(data, "notificationsEnabled");
  const permissionStatus = requiredString(data, "permissionStatus", 40);
  const createdAtMillis = optionalInteger(
    data,
    "installationCreatedAtMillis",
    0,
    4_102_444_800_000
  );
  if (platform !== "android" || applicationId !== "com.samuelpararia.gestioninterna") {
    throw new HttpsError("invalid-argument", "La instalación Android no pertenece a esta app.");
  }
  if (!["granted", "denied", "notDetermined"].includes(permissionStatus)) {
    throw new HttpsError("invalid-argument", "permissionStatus no es válido.");
  }

  const tokenHash = stableHash(token);
  const installationRef = db.doc(`device_installations/${installationId}`);
  const tokenRef = db.doc(`device_tokens/${tokenHash}`);
  const deviceRef = db.doc(`users/${actor.uid}/devices/${installationId}`);
  const now = Timestamp.now();

  await db.runTransaction(async (transaction) => {
    const [installationSnapshot, tokenSnapshot] = await Promise.all([
      transaction.get(installationRef),
      transaction.get(tokenRef)
    ]);
    const previousInstallation = installationSnapshot.data() ?? {};
    const previousToken = tokenSnapshot.data() ?? {};
    const deletions = new Map<string, DocumentReference>();
    const protectedPaths = new Set([installationRef.path, tokenRef.path, deviceRef.path]);

    const previousOwnerUid = previousInstallation.uid;
    if (typeof previousOwnerUid === "string") {
      addDeletion(
        deletions,
        db.doc(`users/${previousOwnerUid}/devices/${installationId}`),
        protectedPaths
      );
    }
    const previousTokenHash = previousInstallation.tokenHash;
    if (typeof previousTokenHash === "string" && previousTokenHash !== tokenHash) {
      addDeletion(deletions, db.doc(`device_tokens/${previousTokenHash}`), protectedPaths);
    }

    const previousTokenOwnerUid = previousToken.uid;
    const previousTokenInstallationId = previousToken.installationId;
    if (typeof previousTokenOwnerUid === "string" &&
      typeof previousTokenInstallationId === "string") {
      addDeletion(
        deletions,
        db.doc(`users/${previousTokenOwnerUid}/devices/${previousTokenInstallationId}`),
        protectedPaths
      );
      addDeletion(
        deletions,
        db.doc(`device_installations/${previousTokenInstallationId}`),
        protectedPaths
      );
    }

    for (const reference of deletions.values()) transaction.delete(reference);
    transaction.set(installationRef, {
      uid: actor.uid,
      installationId,
      tokenHash,
      updatedAt: now
    });
    transaction.set(tokenRef, {
      uid: actor.uid,
      installationId,
      tokenHash,
      updatedAt: now
    });
    transaction.set(deviceRef, {
      installationId,
      uid: actor.uid,
      token,
      platform,
      applicationId,
      notificationsEnabled,
      permissionStatus,
      installationCreatedAt: Timestamp.fromMillis(createdAtMillis ?? now.toMillis()),
      updatedAt: now,
      lastSeenAt: now
    });
  });

  return { installationId, registered: true };
});

export const unregisterDevice = onCall(OPTIONS, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  const data = asRecord(request.data);
  const installationId = installationIdFrom(data);
  const installationRef = db.doc(`device_installations/${installationId}`);
  const deviceRef = db.doc(`users/${uid}/devices/${installationId}`);

  await db.runTransaction(async (transaction) => {
    const installationSnapshot = await transaction.get(installationRef);
    const ownership = installationSnapshot.data() ?? {};
    transaction.delete(deviceRef);
    if (ownership.uid !== uid) return;
    const tokenHash = ownership.tokenHash;
    if (typeof tokenHash === "string") transaction.delete(db.doc(`device_tokens/${tokenHash}`));
    transaction.delete(installationRef);
  });

  return { installationId, unregistered: true };
});
