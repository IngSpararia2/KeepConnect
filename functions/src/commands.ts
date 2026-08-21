import { Timestamp, type DocumentSnapshot } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import {
  isMaintenanceFor,
  isRequester,
  requireActor,
  requireMaintenanceManager,
  requireTicketParticipant
} from "./auth";
import {
  commandEventId,
  commandReceiptId,
  lastMutation,
  writeAuditEvent
} from "./audit";
import {
  MAX_PARTICIPANTS,
  FUNCTION_REGION,
  bogotaDateKey,
  minutesFrom,
  readMaintenanceSettings
} from "./config";
import { manualEscalationAllowed, nextManualEscalationAt } from "./escalation";
import { db, storage } from "./firebase";
import {
  PRIORITY_RANK,
  isPriorityLower,
  nextAcknowledgementEscalationAt,
  suggestPriority
} from "./priority";
import type {
  Actor,
  AssetSnapshot,
  AuditEventData,
  FormTemplateSnapshot,
  Priority,
  TicketData,
  TicketStatus
} from "./types";
import {
  asRecord,
  buildSearchTokens,
  commandRequestId,
  optionalInteger,
  optionalPositiveInteger,
  optionalString,
  parseAttachmentKind,
  parseMap,
  parseOptionalPriority,
  parsePriority,
  parseStatus,
  parseStringArray,
  requiredBoolean,
  requiredString,
  safeStorageFileName,
  validateDynamicFormResponses
} from "./validation";
import { assertTransition } from "./workflow";

const CALLABLE_OPTIONS = {
  region: FUNCTION_REGION,
  timeoutSeconds: 60,
  memory: "256MiB" as const,
  maxInstances: 30,
  enforceAppCheck: false
};

interface StoredObjectMetadata {
  contentType?: string;
  size?: string | number;
  metadata?: Record<string, string>;
}

function ticketFrom(snapshot: DocumentSnapshot): TicketData {
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "La solicitud no existe.");
  }
  return snapshot.data() as TicketData;
}

function ticketIdFrom(data: Record<string, unknown>): string {
  const ticketId = requiredString(data, "ticketId", 128);
  if (!/^[A-Za-z0-9_-]+$/.test(ticketId)) {
    throw new HttpsError("invalid-argument", "ticketId no es válido.");
  }
  return ticketId;
}

function eventResultStatus(event: DocumentSnapshot, fallback: TicketStatus): TicketStatus {
  const data = event.data();
  const value = data?.newValue;
  if (typeof value === "object" && value !== null && "status" in value) {
    const status = (value as Record<string, unknown>).status;
    if (typeof status === "string") return status as TicketStatus;
  }
  return fallback;
}

function activeOpenStatus(status: TicketStatus): boolean {
  return status !== "closed" && status !== "cancelled";
}

function statusLabel(status: TicketStatus): string {
  const labels: Record<TicketStatus, string> = {
    pending: "Pendiente",
    acknowledged: "Recibido",
    assigned: "Asignado",
    inProgress: "En proceso",
    waitingParts: "En espera de repuesto",
    waitingExternal: "En espera externa",
    paused: "Pausado",
    resolved: "Resuelto",
    closed: "Cerrado",
    cancelled: "Cancelado"
  };
  return labels[status];
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function currentParticipantUids(ticket: TicketData): string[] {
  return Array.isArray(ticket.participantUids) ? ticket.participantUids : [ticket.requesterUid];
}

async function loadAsset(
  assetId: string | null,
  sourceDepartmentId: string
): Promise<AssetSnapshot | null> {
  if (!assetId) return null;
  const snapshot = await db.doc(`assets/${assetId}`).get();
  const data = snapshot.data();
  if (!snapshot.exists || !data || data.active !== true) {
    throw new HttpsError("failed-precondition", "El activo seleccionado no existe o está inactivo.");
  }
  if (data.departmentId !== sourceDepartmentId) {
    throw new HttpsError("failed-precondition", "El activo no pertenece al área solicitante.");
  }
  return {
    id: snapshot.id,
    code: typeof data.code === "string" ? data.code : "",
    name: typeof data.name === "string" ? data.name : snapshot.id,
    location: nullableString(data.location),
    critical: data.critical === true
  };
}

async function loadCategory(
  categoryId: string,
  moduleId: string
): Promise<{ id: string; name: string }> {
  const snapshot = await db.doc(`ticket_categories/${categoryId}`).get();
  const data = snapshot.data();
  if (!snapshot.exists || !data || data.active !== true) {
    throw new HttpsError("failed-precondition", "La categoría no existe o está inactiva.");
  }
  if (data.moduleId !== moduleId) {
    throw new HttpsError("failed-precondition", "La categoría no pertenece al módulo.");
  }
  return {
    id: snapshot.id,
    name: typeof data.name === "string" && data.name.trim() ? data.name.trim() : snapshot.id
  };
}

async function loadFormTemplate(
  requestedTemplateId: string | null,
  moduleId: string,
  responses: Record<string, unknown>,
  sourceDepartmentId: string,
  targetDepartmentId: string
): Promise<FormTemplateSnapshot | null> {
  const moduleSnapshot = await db.doc(`modules/${moduleId}`).get();
  const moduleData = moduleSnapshot.data();
  if (!moduleSnapshot.exists || !moduleData || moduleData.active !== true) {
    throw new HttpsError("failed-precondition", "El módulo de mantenimiento no está activo.");
  }
  const sources = Array.isArray(moduleData.sourceDepartmentIds)
    ? moduleData.sourceDepartmentIds
    : [];
  const destinations = Array.isArray(moduleData.destinationDepartmentIds)
    ? moduleData.destinationDepartmentIds
    : [];
  if (!sources.includes(sourceDepartmentId) || !destinations.includes(targetDepartmentId)) {
    throw new HttpsError(
      "permission-denied",
      "Las áreas origen/destino no están autorizadas para este módulo."
    );
  }
  const configuredTemplateId = typeof moduleData.formTemplateId === "string" &&
    moduleData.formTemplateId.trim()
    ? moduleData.formTemplateId.trim()
    : null;
  const templateId = requestedTemplateId ?? configuredTemplateId;
  if (!templateId) {
    if (Object.keys(responses).length > 0) {
      throw new HttpsError("invalid-argument", "No hay una plantilla para formResponses.");
    }
    return null;
  }
  if (configuredTemplateId && templateId !== configuredTemplateId) {
    throw new HttpsError("failed-precondition", "La plantilla no es la configurada para el módulo.");
  }
  const snapshot = await db.doc(`form_templates/${templateId}`).get();
  const data = snapshot.data();
  if (!snapshot.exists || !data || data.active !== true) {
    throw new HttpsError("failed-precondition", "El formulario dinámico no existe o está inactivo.");
  }
  if (data.moduleId !== moduleId) {
    throw new HttpsError("failed-precondition", "El formulario no pertenece al módulo.");
  }
  const version = typeof data.version === "number" && Number.isFinite(data.version)
    ? data.version
    : 1;
  return {
    id: snapshot.id,
    name: typeof data.name === "string" && data.name.trim()
      ? data.name.trim().slice(0, 240)
      : snapshot.id,
    version,
    fields: validateDynamicFormResponses(data.fields, responses)
  };
}

async function ensureActiveDepartment(departmentId: string): Promise<void> {
  const snapshot = await db.doc(`departments/${departmentId}`).get();
  if (!snapshot.exists || snapshot.data()?.active !== true) {
    throw new HttpsError("failed-precondition", "El área seleccionada no existe o está inactiva.");
  }
}

function eventData(
  type: string,
  actor: Actor,
  now: Timestamp,
  previousValue: unknown,
  newValue: unknown,
  message: string,
  correlationId: string,
  metadata: Record<string, unknown> = {}
): AuditEventData {
  return {
    type,
    actorUid: actor.uid,
    actorName: actor.name,
    actorRole: actor.role,
    createdAt: now,
    previousValue,
    newValue,
    message,
    metadata,
    correlationId,
    source: "callable"
  };
}

export const createTicket = onCall(CALLABLE_OPTIONS, async (request) => {
  const actor = await requireActor(request);
  if (actor.role !== "production" && actor.role !== "admin") {
    throw new HttpsError("permission-denied", "Solo Producción o un administrador puede crear solicitudes.");
  }
  const data = asRecord(request.data);
  const requestId = commandRequestId(data);
  const title = requiredString(data, "title", 120, 3);
  const description = requiredString(data, "description", 4000, 10);
  const location = requiredString(data, "location", 240, 2);
  const categoryId = optionalString(data, "categoryId", 80) ?? requiredString(data, "category", 80);
  const sourceDepartmentId =
    actor.role === "admin"
      ? optionalString(data, "sourceDepartmentId", 80) ?? actor.departmentId
      : actor.departmentId;
  const targetDepartmentId = optionalString(data, "targetDepartmentId", 80) ?? "maintenance";
  const assetId = optionalString(data, "assetId", 128);
  const formTemplateId = optionalString(data, "formTemplateId", 128);
  const productionStopped = requiredBoolean(data, "productionStopped");
  const safetyRisk = requiredBoolean(data, "safetyRisk");
  const impactPercentage = optionalInteger(data, "impactPercentage", 0, 100);
  const impactNotes = optionalString(data, "impactNotes", 1000);
  const formResponses = parseMap(data.formResponses, "formResponses", 60_000, 100);
  const selectedPriority = parseOptionalPriority(data.selectedPriority ?? data.priority);
  const priorityOverrideReason = optionalString(data, "priorityOverrideReason", 500);

  const [asset, template, category, settings] = await Promise.all([
    loadAsset(assetId, sourceDepartmentId),
    loadFormTemplate(
      formTemplateId,
      "maintenance",
      formResponses,
      sourceDepartmentId,
      targetDepartmentId
    ),
    loadCategory(categoryId, "maintenance"),
    readMaintenanceSettings(),
    ensureActiveDepartment(sourceDepartmentId),
    ensureActiveDepartment(targetDepartmentId)
  ]);

  const suggestion = suggestPriority(
    {
      productionStopped,
      safetyRisk,
      criticalAsset: asset?.critical ?? false,
      impactPercentage
    },
    settings.priorityPolicy
  );
  const priority = selectedPriority ?? suggestion.priority;
  if (isPriorityLower(priority, suggestion.priority) && !priorityOverrideReason) {
    throw new HttpsError(
      "invalid-argument",
      "Debes explicar por qué seleccionas una prioridad menor que la recomendada."
    );
  }

  const now = Timestamp.now();
  const dateKey = bogotaDateKey(now.toDate());
  const ticketRef = db.collection("tickets").doc();
  const receiptRef = db.doc(`_command_receipts/${commandReceiptId(actor.uid, "createTicket", requestId)}`);
  const counterRef = db.doc(`counters/maintenance-${dateKey}`);
  const eventId = commandEventId(actor.uid, "createTicket", requestId);

  return db.runTransaction(async (transaction) => {
    const [receiptSnapshot, counterSnapshot] = await Promise.all([
      transaction.get(receiptRef),
      transaction.get(counterRef)
    ]);
    if (receiptSnapshot.exists) {
      const receipt = receiptSnapshot.data() ?? {};
      return {
        ticketId: receipt.ticketId as string,
        humanCode: receipt.humanCode as string,
        status: "pending" as const,
        priority: receipt.priority as Priority,
        suggestedPriority: receipt.suggestedPriority as Priority,
        idempotent: true
      };
    }

    const rawNext = counterSnapshot.data()?.nextSequence;
    const sequence = typeof rawNext === "number" && Number.isInteger(rawNext) && rawNext > 0 ? rawNext : 1;
    const humanCode = `MTTO-${dateKey}-${sequence.toString().padStart(4, "0")}`;
    const ticket: TicketData = {
      schemaVersion: 1,
      moduleId: "maintenance",
      humanCode,
      title,
      description,
      categoryId: category.id,
      categoryName: category.name,
      sourceDepartmentId,
      targetDepartmentId,
      requesterUid: actor.uid,
      requesterName: actor.name,
      requesterEmail: actor.email,
      createdByUid: actor.uid,
      location,
      assetId,
      assetSnapshot: asset,
      productionStopped,
      productionStoppedAt: productionStopped ? now : null,
      productionResumedAt: null,
      safetyRisk,
      impactPercentage,
      impactNotes,
      formTemplateId: template?.id ?? null,
      formTemplateVersion: template?.version ?? null,
      formTemplateSnapshot: template,
      formResponses,
      suggestedPriority: suggestion.priority,
      priorityScore: suggestion.score,
      priorityPolicyVersion: suggestion.policyVersion,
      priorityFactors: suggestion.factors,
      priority,
      priorityRank: PRIORITY_RANK[priority],
      prioritySetByUid: actor.uid,
      prioritySetAt: now,
      priorityOverrideReason,
      status: "pending",
      isOpen: true,
      statusChangedAt: now,
      primaryAssigneeUid: null,
      primaryAssigneeName: null,
      participantUids: [actor.uid],
      assignedByUid: null,
      assignedAt: null,
      lastAssignedAt: null,
      acknowledgedByUid: null,
      acknowledgedAt: null,
      workStartedAt: null,
      lastWorkResumedAt: null,
      diagnosis: null,
      workPerformed: null,
      resolutionNotes: null,
      resolvedByUid: null,
      resolvedAt: null,
      lastResolvedAt: null,
      resolutionAttemptCount: 0,
      reopenCount: 0,
      lastReopenedAt: null,
      closedByUid: null,
      closedAt: null,
      cancelledByUid: null,
      cancelledAt: null,
      cancellationReason: null,
      waitingReason: null,
      waitingSince: null,
      escalationCount: 0,
      manualEscalationCount: 0,
      lastManualEscalationAt: null,
      lastAutomaticEscalationAt: null,
      automaticEscalationLevel: 0,
      nextAutomaticEscalationAt: nextAcknowledgementEscalationAt(now, priority, settings),
      lastEscalationType: null,
      lastEscalationReason: null,
      attachmentCount: 0,
      searchTokens: buildSearchTokens([title, humanCode, asset?.name ?? "", asset?.code ?? ""]),
      createdAt: now,
      updatedAt: now,
      lastActivityAt: now,
      lastMutation: lastMutation(eventId, "ticketCreated", actor, now)
    };

    transaction.create(ticketRef, ticket);
    transaction.create(
      ticketRef.collection("events").doc(eventId),
      eventData(
        "ticketCreated",
        actor,
        now,
        null,
        { status: ticket.status, priority, suggestedPriority: suggestion.priority },
        `${actor.name} creó ${humanCode}.`,
        requestId,
        { humanCode }
      )
    );
    transaction.set(
      counterRef,
      { nextSequence: sequence + 1, lastIssuedCode: humanCode, updatedAt: now },
      { merge: true }
    );
    transaction.create(receiptRef, {
      command: "createTicket",
      actorUid: actor.uid,
      requestId,
      ticketId: ticketRef.id,
      humanCode,
      priority,
      suggestedPriority: suggestion.priority,
      createdAt: now
    });

    return {
      ticketId: ticketRef.id,
      humanCode,
      status: ticket.status,
      priority,
      suggestedPriority: suggestion.priority,
      idempotent: false
    };
  });
});

export const transitionTicket = onCall(CALLABLE_OPTIONS, async (request) => {
  const actor = await requireActor(request);
  const data = asRecord(request.data);
  const ticketId = ticketIdFrom(data);
  const toStatus = parseStatus(data.toStatus);
  if (toStatus === "assigned") {
    throw new HttpsError("invalid-argument", "Usa assignTicket para asignar responsables.");
  }
  const requestId = commandRequestId(data);
  const reason = optionalString(data, "reason", 1000);
  const diagnosis = optionalString(data, "diagnosis", 3000);
  const workPerformed = optionalString(data, "workPerformed", 4000);
  const resolutionNotes = optionalString(data, "resolutionNotes", 3000);
  const now = Timestamp.now();
  const ticketRef = db.doc(`tickets/${ticketId}`);
  const eventId = commandEventId(actor.uid, "transitionTicket", requestId);
  const eventRef = ticketRef.collection("events").doc(eventId);

  return db.runTransaction(async (transaction) => {
    const [ticketSnapshot, existingEvent] = await Promise.all([
      transaction.get(ticketRef),
      transaction.get(eventRef)
    ]);
    const ticket = ticketFrom(ticketSnapshot);
    if (existingEvent.exists) {
      return {
        ticketId,
        status: eventResultStatus(existingEvent, ticket.status),
        eventId,
        idempotent: true
      };
    }

    const fromStatus = ticket.status;
    assertTransition(fromStatus, toStatus, {
      role: actor.role,
      isRequester: isRequester(actor, ticket),
      isMaintenanceForTicket: isMaintenanceFor(actor, ticket),
      isAssignedParticipant:
        actor.uid === ticket.primaryAssigneeUid || currentParticipantUids(ticket).includes(actor.uid)
    });

    const updates: Record<string, unknown> = {
      status: toStatus,
      isOpen: activeOpenStatus(toStatus),
      statusChangedAt: now,
      updatedAt: now,
      lastActivityAt: now,
      lastMutation: lastMutation(eventId, "statusChanged", actor, now)
    };
    let eventType = "statusChanged";

    if (toStatus === "acknowledged") {
      updates.acknowledgedAt = ticket.acknowledgedAt ?? now;
      updates.acknowledgedByUid = ticket.acknowledgedByUid ?? actor.uid;
      updates.nextAutomaticEscalationAt = null;
      eventType = "ticketAcknowledged";
    } else if (toStatus === "inProgress") {
      updates.waitingReason = null;
      updates.waitingSince = null;
      updates.lastWorkResumedAt = now;
      if (fromStatus === "assigned") {
        updates.workStartedAt = ticket.workStartedAt ?? now;
        eventType = "workStarted";
      } else if (fromStatus === "resolved") {
        if (!reason) {
          throw new HttpsError("invalid-argument", "Debes indicar por qué solicitas una nueva revisión.");
        }
        updates.lastResolvedAt = ticket.resolvedAt;
        updates.resolvedAt = null;
        updates.resolvedByUid = null;
        updates.reopenCount = (ticket.reopenCount ?? 0) + 1;
        updates.lastReopenedAt = now;
        eventType = "ticketReopened";
      } else {
        eventType = "workResumed";
      }
    } else if (toStatus === "waitingParts" || toStatus === "waitingExternal" || toStatus === "paused") {
      if (!reason) {
        throw new HttpsError("invalid-argument", "Debes indicar el motivo de la espera o pausa.");
      }
      updates.waitingReason = reason;
      updates.waitingSince = now;
      eventType = toStatus === "paused" ? "ticketPaused" : "ticketWaiting";
    } else if (toStatus === "resolved") {
      if (!diagnosis || !workPerformed || !resolutionNotes) {
        throw new HttpsError(
          "invalid-argument",
          "Diagnóstico, trabajo realizado y observaciones son obligatorios para resolver."
        );
      }
      updates.diagnosis = diagnosis;
      updates.workPerformed = workPerformed;
      updates.resolutionNotes = resolutionNotes;
      updates.resolvedByUid = actor.uid;
      updates.resolvedAt = now;
      updates.lastResolvedAt = now;
      updates.resolutionAttemptCount = (ticket.resolutionAttemptCount ?? 0) + 1;
      updates.waitingReason = null;
      updates.waitingSince = null;
      eventType = "ticketResolved";
    } else if (toStatus === "closed") {
      updates.closedByUid = actor.uid;
      updates.closedAt = now;
      eventType = "ticketClosed";
    } else if (toStatus === "cancelled") {
      if (!reason) {
        throw new HttpsError("invalid-argument", "Debes indicar el motivo de cancelación.");
      }
      updates.cancelledByUid = actor.uid;
      updates.cancelledAt = now;
      updates.cancellationReason = reason;
      updates.nextAutomaticEscalationAt = null;
      eventType = "ticketCancelled";
    }

    updates.lastMutation = lastMutation(eventId, eventType, actor, now);
    transaction.update(ticketRef, updates);
    writeAuditEvent(transaction, eventRef, {
      type: eventType,
      actor,
      now,
      previousValue: { status: fromStatus },
      newValue: { status: toStatus, reason, diagnosis, workPerformed, resolutionNotes },
      message: `${actor.name} cambió ${ticket.humanCode} a “${statusLabel(toStatus)}”.`,
      metadata: { reason },
      correlationId: requestId,
      source: "callable"
    });

    return { ticketId, status: toStatus, eventId, idempotent: false };
  });
});

export const assignTicket = onCall(CALLABLE_OPTIONS, async (request) => {
  const actor = await requireActor(request);
  const data = asRecord(request.data);
  const ticketId = ticketIdFrom(data);
  const primaryAssigneeUid = requiredString(data, "primaryAssigneeUid", 128);
  const hasParticipantList = Object.prototype.hasOwnProperty.call(data, "participantUids");
  const requestedParticipants = parseStringArray(data.participantUids, "participantUids", MAX_PARTICIPANTS);
  const requestId = commandRequestId(data);
  const now = Timestamp.now();
  const ticketRef = db.doc(`tickets/${ticketId}`);
  const eventId = commandEventId(actor.uid, "assignTicket", requestId);
  const eventRef = ticketRef.collection("events").doc(eventId);

  return db.runTransaction(async (transaction) => {
    const [ticketSnapshot, existingEvent] = await Promise.all([
      transaction.get(ticketRef),
      transaction.get(eventRef)
    ]);
    const ticket = ticketFrom(ticketSnapshot);
    if (existingEvent.exists) {
      const newValue = existingEvent.data()?.newValue as Record<string, unknown> | undefined;
      return {
        ticketId,
        status: "assigned" as const,
        primaryAssigneeUid: (newValue?.primaryAssigneeUid as string | undefined) ?? primaryAssigneeUid,
        participantUids: (newValue?.participantUids as string[] | undefined) ?? currentParticipantUids(ticket),
        eventId,
        idempotent: true
      };
    }
    requireMaintenanceManager(actor, ticket);
    if (ticket.status !== "acknowledged" && ticket.status !== "assigned") {
      throw new HttpsError("failed-precondition", "El ticket debe estar recibido antes de asignarlo.");
    }
    if (primaryAssigneeUid === ticket.requesterUid) {
      throw new HttpsError(
        "invalid-argument",
        "El solicitante de Producción no puede ser el responsable técnico."
      );
    }

    const baseParticipants = hasParticipantList ? requestedParticipants : currentParticipantUids(ticket);
    const participantUids = [
      ...new Set([ticket.requesterUid, primaryAssigneeUid, ...baseParticipants])
    ];
    if (participantUids.length > MAX_PARTICIPANTS) {
      throw new HttpsError("invalid-argument", `No se permiten más de ${MAX_PARTICIPANTS} participantes.`);
    }
    const maintenanceUids = participantUids.filter((uid) => uid !== ticket.requesterUid);
    const userSnapshots = await Promise.all(
      maintenanceUids.map((uid) => transaction.get(db.doc(`users/${uid}`)))
    );
    for (const snapshot of userSnapshots) {
      const profile = snapshot.data();
      if (
        !snapshot.exists ||
        profile?.active !== true ||
        profile.role !== "maintenance" ||
        profile.departmentId !== ticket.targetDepartmentId
      ) {
        throw new HttpsError(
          "failed-precondition",
          `El usuario ${snapshot.id} no es un técnico activo del área destino.`
        );
      }
    }
    const primaryProfile = userSnapshots.find((snapshot) => snapshot.id === primaryAssigneeUid)?.data();
    const primaryAssigneeName =
      typeof primaryProfile?.name === "string" ? primaryProfile.name : "Técnico de mantenimiento";

    const previous = {
      status: ticket.status,
      primaryAssigneeUid: ticket.primaryAssigneeUid,
      participantUids: currentParticipantUids(ticket)
    };
    const next = { status: "assigned", primaryAssigneeUid, participantUids };
    transaction.update(ticketRef, {
      status: "assigned",
      isOpen: true,
      statusChangedAt: ticket.status === "assigned" ? ticket.statusChangedAt : now,
      primaryAssigneeUid,
      primaryAssigneeName,
      participantUids,
      assignedByUid: actor.uid,
      assignedAt: ticket.assignedAt ?? now,
      lastAssignedAt: now,
      updatedAt: now,
      lastActivityAt: now,
      lastMutation: lastMutation(eventId, "assignmentChanged", actor, now)
    });
    writeAuditEvent(transaction, eventRef, {
      type: "assignmentChanged",
      actor,
      now,
      previousValue: previous,
      newValue: next,
      message: `${actor.name} asignó ${ticket.humanCode} a ${primaryAssigneeName}.`,
      correlationId: requestId,
      source: "callable"
    });

    return {
      ticketId,
      status: "assigned" as const,
      primaryAssigneeUid,
      participantUids,
      eventId,
      idempotent: false
    };
  });
});

export const addComment = onCall(CALLABLE_OPTIONS, async (request) => {
  const actor = await requireActor(request);
  const data = asRecord(request.data);
  const ticketId = ticketIdFrom(data);
  const text = requiredString(data, "text", 2000, 1);
  const requestId = commandRequestId(data);
  const now = Timestamp.now();
  const ticketRef = db.doc(`tickets/${ticketId}`);
  const eventId = commandEventId(actor.uid, "addComment", requestId);
  const commentId = `comment_${eventId.slice(4)}`;
  const commentRef = ticketRef.collection("comments").doc(commentId);
  const eventRef = ticketRef.collection("events").doc(eventId);

  return db.runTransaction(async (transaction) => {
    const [ticketSnapshot, existingComment, existingEvent] = await Promise.all([
      transaction.get(ticketRef),
      transaction.get(commentRef),
      transaction.get(eventRef)
    ]);
    const ticket = ticketFrom(ticketSnapshot);
    requireTicketParticipant(actor, ticket);
    if (existingComment.exists || existingEvent.exists) {
      return { ticketId, commentId, eventId, idempotent: true };
    }
    if (!activeOpenStatus(ticket.status)) {
      throw new HttpsError("failed-precondition", "No se pueden comentar tickets cerrados o cancelados.");
    }

    transaction.create(commentRef, {
      authorUid: actor.uid,
      authorName: actor.name,
      authorRole: actor.role,
      text,
      createdAt: now,
      requestId
    });
    writeAuditEvent(transaction, eventRef, {
      type: "commentAdded",
      actor,
      now,
      previousValue: null,
      newValue: { commentId },
      message: `${actor.name} añadió un comentario.`,
      metadata: { commentId },
      correlationId: requestId,
      source: "callable"
    });
    transaction.update(ticketRef, {
      updatedAt: now,
      lastActivityAt: now,
      lastMutation: lastMutation(eventId, "commentAdded", actor, now)
    });

    return { ticketId, commentId, eventId, idempotent: false };
  });
});

export const updatePriority = onCall(CALLABLE_OPTIONS, async (request) => {
  const actor = await requireActor(request);
  const data = asRecord(request.data);
  const ticketId = ticketIdFrom(data);
  const priority = parsePriority(data.priority);
  const reason = requiredString(data, "reason", 1000, 3);
  const requestId = commandRequestId(data);
  const settings = await readMaintenanceSettings();
  const now = Timestamp.now();
  const ticketRef = db.doc(`tickets/${ticketId}`);
  const eventId = commandEventId(actor.uid, "updatePriority", requestId);
  const eventRef = ticketRef.collection("events").doc(eventId);

  return db.runTransaction(async (transaction) => {
    const [ticketSnapshot, existingEvent] = await Promise.all([
      transaction.get(ticketRef),
      transaction.get(eventRef)
    ]);
    const ticket = ticketFrom(ticketSnapshot);
    if (existingEvent.exists) {
      const newValue = existingEvent.data()?.newValue as Record<string, unknown> | undefined;
      return {
        ticketId,
        priority: (newValue?.priority as Priority | undefined) ?? ticket.priority,
        eventId,
        idempotent: true
      };
    }
    requireMaintenanceManager(actor, ticket);
    if (!activeOpenStatus(ticket.status)) {
      throw new HttpsError("failed-precondition", "No se puede cambiar la prioridad de un ticket terminado.");
    }
    if (ticket.priority === priority) {
      throw new HttpsError("already-exists", "El ticket ya tiene esa prioridad.");
    }

    const nextAutomaticEscalationAt =
      ticket.acknowledgedAt === null && ticket.status === "pending"
        ? nextAcknowledgementEscalationAt(now, priority, settings)
        : null;
    transaction.update(ticketRef, {
      priority,
      priorityRank: PRIORITY_RANK[priority],
      prioritySetByUid: actor.uid,
      prioritySetAt: now,
      priorityOverrideReason: reason,
      nextAutomaticEscalationAt,
      updatedAt: now,
      lastActivityAt: now,
      lastMutation: lastMutation(eventId, "priorityChanged", actor, now)
    });
    writeAuditEvent(transaction, eventRef, {
      type: "priorityChanged",
      actor,
      now,
      previousValue: { priority: ticket.priority },
      newValue: { priority, reason },
      message: `${actor.name} cambió la prioridad de ${ticket.humanCode} a ${priority}.`,
      metadata: { reason },
      correlationId: requestId,
      source: "callable"
    });

    return { ticketId, priority, eventId, idempotent: false };
  });
});

export const updateProductionImpact = onCall(CALLABLE_OPTIONS, async (request) => {
  const actor = await requireActor(request);
  const data = asRecord(request.data);
  const ticketId = ticketIdFrom(data);
  const productionStopped = requiredBoolean(data, "productionStopped");
  const reason = requiredString(data, "reason", 1000, 3);
  const requestId = commandRequestId(data);
  const now = Timestamp.now();
  const ticketRef = db.doc(`tickets/${ticketId}`);
  const eventId = commandEventId(actor.uid, "updateProductionImpact", requestId);
  const eventRef = ticketRef.collection("events").doc(eventId);

  return db.runTransaction(async (transaction) => {
    const [ticketSnapshot, existingEvent] = await Promise.all([
      transaction.get(ticketRef),
      transaction.get(eventRef)
    ]);
    const ticket = ticketFrom(ticketSnapshot);
    if (existingEvent.exists) {
      return { ticketId, productionStopped, eventId, idempotent: true };
    }
    const authorized = actor.role === "admin" ||
      (actor.role === "production" && actor.uid === ticket.requesterUid);
    if (!authorized) {
      throw new HttpsError(
        "permission-denied",
        "Solo el solicitante de Producción o un administrador puede actualizar este impacto."
      );
    }
    if (!activeOpenStatus(ticket.status)) {
      throw new HttpsError("failed-precondition", "El ticket ya está terminado.");
    }
    if (ticket.productionStopped === productionStopped) {
      throw new HttpsError("already-exists", "El ticket ya tiene ese estado de producción.");
    }

    transaction.update(ticketRef, {
      productionStopped,
      productionStoppedAt: productionStopped ? now : ticket.productionStoppedAt,
      productionResumedAt: productionStopped ? null : now,
      updatedAt: now,
      lastActivityAt: now,
      lastMutation: lastMutation(eventId, "productionImpactChanged", actor, now)
    });
    writeAuditEvent(transaction, eventRef, {
      type: "productionImpactChanged",
      actor,
      now,
      previousValue: { productionStopped: ticket.productionStopped },
      newValue: { productionStopped, reason },
      message: productionStopped
        ? `${actor.name} informó que la producción se detuvo.`
        : `${actor.name} confirmó que la producción se reanudó.`,
      metadata: { reason },
      correlationId: requestId,
      source: "callable"
    });

    return { ticketId, productionStopped, eventId, idempotent: false };
  });
});

export const registerAttachment = onCall(CALLABLE_OPTIONS, async (request) => {
  const actor = await requireActor(request);
  const data = asRecord(request.data);
  const ticketId = ticketIdFrom(data);
  const attachmentId = requiredString(data, "attachmentId", 80, 8);
  if (!/^[A-Za-z0-9_-]+$/.test(attachmentId)) {
    throw new HttpsError("invalid-argument", "attachmentId no es válido.");
  }
  const fileName = requiredString(data, "fileName", 120);
  if (!safeStorageFileName(fileName)) {
    throw new HttpsError("invalid-argument", "fileName contiene caracteres o segmentos no permitidos.");
  }
  const expectedStoragePath = `tickets/${ticketId}/${attachmentId}/${fileName}`;
  const storagePath = requiredString(data, "storagePath", 500);
  if (storagePath !== expectedStoragePath) {
    throw new HttpsError("invalid-argument", `storagePath debe ser exactamente ${expectedStoragePath}.`);
  }
  const kind = parseAttachmentKind(data.kind);
  const declaredWidth = optionalPositiveInteger(data, "width", 20_000);
  const declaredHeight = optionalPositiveInteger(data, "height", 20_000);
  const caption = optionalString(data, "caption", 500);
  const requestId = commandRequestId(data);
  const settings = await readMaintenanceSettings();
  const ticketRef = db.doc(`tickets/${ticketId}`);

  const initialTicket = ticketFrom(await ticketRef.get());
  requireTicketParticipant(actor, initialTicket);
  if (!activeOpenStatus(initialTicket.status)) {
    throw new HttpsError("failed-precondition", "No se pueden añadir evidencias a un ticket terminado.");
  }

  let objectMetadata: StoredObjectMetadata;
  try {
    const [loadedMetadata] = await storage.bucket().file(storagePath).getMetadata();
    objectMetadata = loadedMetadata as StoredObjectMetadata;
  } catch (error) {
    throw new HttpsError("not-found", "El archivo aún no existe en Firebase Storage.", {
      cause: error instanceof Error ? error.message : "storage-object-not-found"
    });
  }
  const contentType = objectMetadata.contentType ?? "";
  const sizeBytes = Number(objectMetadata.size ?? 0);
  if (!contentType.startsWith("image/")) {
    throw new HttpsError("invalid-argument", "Solo se permiten archivos de imagen.");
  }
  if (!Number.isFinite(sizeBytes) || sizeBytes <= 0 || sizeBytes > settings.maxPhotoBytes) {
    throw new HttpsError(
      "invalid-argument",
      `La imagen debe pesar como máximo ${settings.maxPhotoBytes} bytes.`
    );
  }
  const customMetadata = objectMetadata.metadata ?? {};
  if (customMetadata.ticketId !== ticketId || customMetadata.uploaderUid !== actor.uid) {
    throw new HttpsError(
      "failed-precondition",
      "La metadata del archivo no coincide con el ticket y usuario autenticado."
    );
  }

  const now = Timestamp.now();
  const attachmentRef = ticketRef.collection("attachments").doc(attachmentId);
  const eventId = commandEventId(actor.uid, "registerAttachment", requestId);
  const eventRef = ticketRef.collection("events").doc(eventId);
  return db.runTransaction(async (transaction) => {
    const [ticketSnapshot, attachmentSnapshot, existingEvent] = await Promise.all([
      transaction.get(ticketRef),
      transaction.get(attachmentRef),
      transaction.get(eventRef)
    ]);
    const ticket = ticketFrom(ticketSnapshot);
    requireTicketParticipant(actor, ticket);
    if (attachmentSnapshot.exists || existingEvent.exists) {
      return { ticketId, attachmentId, eventId, idempotent: true };
    }
    if (!activeOpenStatus(ticket.status)) {
      throw new HttpsError("failed-precondition", "No se pueden añadir evidencias a un ticket terminado.");
    }
    const attachmentCount = ticket.attachmentCount ?? 0;
    if (attachmentCount >= settings.maxPhotosPerTicket) {
      throw new HttpsError(
        "resource-exhausted",
        `El ticket alcanzó el máximo de ${settings.maxPhotosPerTicket} fotografías.`
      );
    }

    transaction.create(attachmentRef, {
      storagePath,
      fileName,
      contentType,
      sizeBytes,
      width: declaredWidth,
      height: declaredHeight,
      kind,
      caption,
      uploaderUid: actor.uid,
      uploaderName: actor.name,
      createdAt: now
    });
    transaction.update(ticketRef, {
      attachmentCount: attachmentCount + 1,
      updatedAt: now,
      lastActivityAt: now,
      lastMutation: lastMutation(eventId, "attachmentAdded", actor, now)
    });
    writeAuditEvent(transaction, eventRef, {
      type: "attachmentAdded",
      actor,
      now,
      previousValue: null,
      newValue: { attachmentId, kind, storagePath },
      message: `${actor.name} añadió una evidencia fotográfica.`,
      metadata: { attachmentId, kind, contentType, sizeBytes },
      correlationId: requestId,
      source: "callable"
    });

    return { ticketId, attachmentId, eventId, idempotent: false };
  });
});

export const escalateTicket = onCall(CALLABLE_OPTIONS, async (request) => {
  const actor = await requireActor(request);
  const data = asRecord(request.data);
  const ticketId = ticketIdFrom(data);
  const reason = optionalString(data, "reason", 1000);
  const requestId = commandRequestId(data);
  const settings = await readMaintenanceSettings();
  const now = Timestamp.now();
  const ticketRef = db.doc(`tickets/${ticketId}`);
  const eventId = commandEventId(actor.uid, "escalateTicket", requestId);
  const eventRef = ticketRef.collection("events").doc(eventId);

  return db.runTransaction(async (transaction) => {
    const [ticketSnapshot, existingEvent] = await Promise.all([
      transaction.get(ticketRef),
      transaction.get(eventRef)
    ]);
    const ticket = ticketFrom(ticketSnapshot);
    if (existingEvent.exists) {
      const metadata = existingEvent.data()?.metadata as Record<string, unknown> | undefined;
      return {
        ticketId,
        escalationCount:
          typeof metadata?.escalationCount === "number"
            ? metadata.escalationCount
            : ticket.escalationCount,
        nextAllowedAt: metadata?.nextAllowedAt ?? null,
        eventId,
        idempotent: true
      };
    }
    const authorized =
      actor.role === "admin" || (actor.role === "production" && actor.uid === ticket.requesterUid);
    if (!authorized) {
      throw new HttpsError(
        "permission-denied",
        "Solo el solicitante de Producción o un administrador puede escalar la urgencia."
      );
    }
    if (!activeOpenStatus(ticket.status) || ticket.status === "resolved") {
      throw new HttpsError("failed-precondition", "Este ticket ya no admite escalamiento de urgencia.");
    }
    const nextAllowedAt = nextManualEscalationAt(
      ticket.lastManualEscalationAt,
      settings.manualEscalationCooldownMinutes
    );
    if (
      !manualEscalationAllowed(
        now,
        ticket.lastManualEscalationAt,
        settings.manualEscalationCooldownMinutes
      )
    ) {
      throw new HttpsError("resource-exhausted", "Debes esperar antes de volver a escalar este ticket.", {
        nextAllowedAt: nextAllowedAt?.toMillis() ?? now.toMillis(),
        cooldownMinutes: settings.manualEscalationCooldownMinutes
      });
    }

    const escalationCount = (ticket.escalationCount ?? 0) + 1;
    const manualEscalationCount = (ticket.manualEscalationCount ?? 0) + 1;
    const followingAllowedAt = minutesFrom(now, settings.manualEscalationCooldownMinutes);
    transaction.update(ticketRef, {
      escalationCount,
      manualEscalationCount,
      lastManualEscalationAt: now,
      lastEscalationType: "manual",
      lastEscalationReason: reason,
      updatedAt: now,
      lastActivityAt: now,
      lastMutation: lastMutation(eventId, "manualEscalation", actor, now)
    });
    writeAuditEvent(transaction, eventRef, {
      type: "manualEscalation",
      actor,
      now,
      previousValue: { escalationCount: ticket.escalationCount ?? 0 },
      newValue: { escalationCount, reason },
      message: `${actor.name} escaló la urgencia de ${ticket.humanCode}.`,
      metadata: {
        reason,
        escalationCount,
        manualEscalationCount,
        nextAllowedAt: followingAllowedAt
      },
      correlationId: requestId,
      source: "callable"
    });

    return {
      ticketId,
      escalationCount,
      nextAllowedAt: followingAllowedAt.toMillis(),
      eventId,
      idempotent: false
    };
  });
});
