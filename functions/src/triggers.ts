import { logger } from "firebase-functions";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";

import { FUNCTION_REGION } from "./config";
import { sendNotification, ticketRecipientUids } from "./notifications";
import type { NotificationDescriptor, Priority, TicketData } from "./types";

const FIRESTORE_TRIGGER_OPTIONS = {
  region: FUNCTION_REGION,
  retry: true
};

function stoppedSuffix(ticket: TicketData): string {
  return ticket.productionStopped ? " Producción detenida." : "";
}

function assetName(ticket: TicketData): string {
  return ticket.assetSnapshot?.name ?? ticket.title;
}

function statusLabel(ticket: TicketData): string {
  const labels: Record<TicketData["status"], string> = {
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
  return labels[ticket.status];
}

function priorityLabel(priority: Priority): string {
  return { low: "baja", medium: "media", high: "alta", critical: "crítica" }[priority];
}

function ticketCreatedDescriptor(ticketId: string, ticket: TicketData): NotificationDescriptor {
  const critical = ticket.priority === "critical";
  return {
    eventId: `ticket-created:${ticketId}`,
    eventType: "ticketCreated",
    ticketId,
    humanCode: ticket.humanCode,
    title: critical ? "Nueva solicitud crítica" : "Nueva solicitud de mantenimiento",
    body: `${ticket.requesterName} reportó ${assetName(ticket)}. ${ticket.humanCode}.${stoppedSuffix(ticket)}`,
    priority: ticket.priority,
    urgent: critical,
    actorUid: ticket.requesterUid,
    recipientUids: [],
    includeMaintenanceDepartmentId: ticket.targetDepartmentId
  };
}

function updatedDescriptor(ticketId: string, ticket: TicketData): NotificationDescriptor | null {
  const mutation = ticket.lastMutation;
  if (!mutation?.id || !mutation.type) return null;
  const recipients = ticketRecipientUids(ticket);
  const base = {
    eventId: `ticket-update:${ticketId}:${mutation.id}`,
    eventType: mutation.type,
    ticketId,
    humanCode: ticket.humanCode,
    priority: ticket.priority,
    actorUid: mutation.actorUid,
    recipientUids: recipients
  };

  switch (mutation.type) {
    case "ticketAcknowledged":
      return {
        ...base,
        title: "Solicitud recibida",
        body: `${ticket.humanCode} fue recibido por Mantenimiento.`,
        urgent: false,
        recipientUids: [ticket.requesterUid]
      };
    case "assignmentChanged":
      return {
        ...base,
        title: "Ticket asignado",
        body: `${ticket.humanCode} fue asignado a ${ticket.primaryAssigneeName ?? "Mantenimiento"}.`,
        urgent: ticket.priority === "critical"
      };
    case "workStarted":
    case "workResumed":
    case "ticketWaiting":
    case "ticketPaused":
    case "ticketReopened":
      return {
        ...base,
        title: "Estado actualizado",
        body: `${ticket.humanCode} cambió a “${statusLabel(ticket)}”.`,
        urgent: false
      };
    case "ticketResolved":
      return {
        ...base,
        title: "Solicitud resuelta",
        body: `${ticket.humanCode} está listo para que confirmes el cierre.`,
        urgent: false,
        recipientUids: [ticket.requesterUid]
      };
    case "ticketClosed":
      return {
        ...base,
        title: "Ticket cerrado",
        body: `${ticket.humanCode} fue confirmado y cerrado.`,
        urgent: false
      };
    case "ticketCancelled":
      return {
        ...base,
        title: "Ticket cancelado",
        body: `${ticket.humanCode} fue cancelado.`,
        urgent: false,
        includeMaintenanceDepartmentId: ticket.targetDepartmentId
      };
    case "priorityChanged":
      return {
        ...base,
        title: ticket.priority === "critical" ? "Prioridad crítica" : "Prioridad actualizada",
        body: `${ticket.humanCode} ahora tiene prioridad ${priorityLabel(ticket.priority)}.`,
        urgent: ticket.priority === "critical",
        includeMaintenanceDepartmentId: ticket.targetDepartmentId
      };
    case "manualEscalation":
      return {
        ...base,
        title: "⚠ Urgencia de mantenimiento",
        body: `Producción solicita atención inmediata de ${ticket.humanCode} – ${assetName(ticket)}.${stoppedSuffix(ticket)}`,
        urgent: true,
        includeMaintenanceDepartmentId: ticket.targetDepartmentId,
        includeAdmins: true
      };
    case "automaticEscalation":
      return {
        ...base,
        title: "⚠ Ticket crítico sin reconocer",
        body: `${ticket.humanCode} requiere atención inmediata.${stoppedSuffix(ticket)}`,
        urgent: true,
        includeMaintenanceDepartmentId: ticket.targetDepartmentId,
        includeAdmins: true
      };
    case "productionImpactChanged":
      return {
        ...base,
        title: ticket.productionStopped ? "Producción detenida" : "Producción reanudada",
        body: `${ticket.humanCode}: ${ticket.productionStopped ? "la producción se detuvo" : "la producción se reanudó"}.`,
        urgent: ticket.productionStopped,
        includeMaintenanceDepartmentId: ticket.targetDepartmentId
      };
    case "commentAdded":
    case "attachmentAdded":
      return null;
    default:
      logger.info("Ticket mutation does not require a notification", {
        ticketId,
        mutationType: mutation.type
      });
      return null;
  }
}

export const onTicketCreated = onDocumentCreated(
  { ...FIRESTORE_TRIGGER_OPTIONS, document: "tickets/{ticketId}" },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    await sendNotification(ticketCreatedDescriptor(event.params.ticketId, snapshot.data() as TicketData));
  }
);

export const onTicketUpdated = onDocumentUpdated(
  { ...FIRESTORE_TRIGGER_OPTIONS, document: "tickets/{ticketId}" },
  async (event) => {
    const snapshot = event.data?.after;
    if (!snapshot) return;
    const descriptor = updatedDescriptor(event.params.ticketId, snapshot.data() as TicketData);
    if (descriptor) await sendNotification(descriptor);
  }
);

export const onCommentCreated = onDocumentCreated(
  {
    ...FIRESTORE_TRIGGER_OPTIONS,
    document: "tickets/{ticketId}/comments/{commentId}"
  },
  async (event) => {
    const commentSnapshot = event.data;
    if (!commentSnapshot) return;
    const ticketSnapshot = await commentSnapshot.ref.parent.parent?.get();
    if (!ticketSnapshot?.exists) return;
    const ticket = ticketSnapshot.data() as TicketData;
    const comment = commentSnapshot.data();
    const actorUid = typeof comment.authorUid === "string" ? comment.authorUid : null;
    const actorName = typeof comment.authorName === "string" ? comment.authorName : "Un participante";
    const text = typeof comment.text === "string" ? comment.text.trim() : "Nuevo comentario";
    const descriptor: NotificationDescriptor = {
      eventId: `comment-created:${event.params.ticketId}:${event.params.commentId}`,
      eventType: "commentAdded",
      ticketId: event.params.ticketId,
      humanCode: ticket.humanCode,
      title: `Nuevo comentario en ${ticket.humanCode}`,
      body: `${actorName}: ${text.slice(0, 160)}`,
      priority: ticket.priority as Priority,
      urgent: false,
      actorUid,
      recipientUids: ticketRecipientUids(ticket),
      includeMaintenanceDepartmentId: ticket.primaryAssigneeUid ? undefined : ticket.targetDepartmentId
    };
    await sendNotification(descriptor);
  }
);
