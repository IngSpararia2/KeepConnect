import { Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { lastMutation, systemEventId, writeAuditEvent } from "./audit";
import {
  DISPLAY_TIME_ZONE,
  FUNCTION_REGION,
  minutesFrom,
  readMaintenanceSettings
} from "./config";
import { db } from "./firebase";
import type { MaintenanceSettings, TicketData } from "./types";

async function escalateDueTicket(
  ticketId: string,
  settings: MaintenanceSettings
): Promise<boolean> {
  const ticketRef = db.doc(`tickets/${ticketId}`);
  const now = Timestamp.now();

  return db.runTransaction(async (transaction) => {
    const ticketSnapshot = await transaction.get(ticketRef);
    if (!ticketSnapshot.exists) return false;
    const ticket = ticketSnapshot.data() as TicketData;
    const dueAt = ticket.nextAutomaticEscalationAt;
    if (
      ticket.status !== "pending" ||
      ticket.acknowledgedAt !== null ||
      ticket.isOpen !== true ||
      !(dueAt instanceof Timestamp) ||
      dueAt.toMillis() > now.toMillis() ||
      (ticket.priority !== "critical" && ticket.priority !== "high")
    ) {
      if (ticket.nextAutomaticEscalationAt !== null) {
        transaction.update(ticketRef, { nextAutomaticEscalationAt: null, updatedAt: now });
      }
      return false;
    }

    const nextLevel = (ticket.automaticEscalationLevel ?? 0) + 1;
    const eventId = systemEventId(
      "auto",
      ticketId,
      `${dueAt.toMillis()}:${nextLevel}`
    );
    const eventRef = ticketRef.collection("events").doc(eventId);
    const eventSnapshot = await transaction.get(eventRef);
    if (eventSnapshot.exists) return false;

    const shouldRepeat = nextLevel < settings.maximumAutomaticEscalationLevel;
    const nextAutomaticEscalationAt = shouldRepeat
      ? minutesFrom(now, settings.automaticEscalationRepeatMinutes)
      : null;
    const escalationCount = (ticket.escalationCount ?? 0) + 1;
    transaction.update(ticketRef, {
      escalationCount,
      automaticEscalationLevel: nextLevel,
      lastAutomaticEscalationAt: now,
      nextAutomaticEscalationAt,
      lastEscalationType: "automatic",
      lastEscalationReason: "El ticket no fue reconocido dentro del tiempo configurado.",
      updatedAt: now,
      lastActivityAt: now,
      lastMutation: lastMutation(eventId, "automaticEscalation", null, now)
    });
    writeAuditEvent(transaction, eventRef, {
      type: "automaticEscalation",
      actor: null,
      now,
      previousValue: {
        automaticEscalationLevel: ticket.automaticEscalationLevel ?? 0,
        escalationCount: ticket.escalationCount ?? 0
      },
      newValue: { automaticEscalationLevel: nextLevel, escalationCount },
      message: `El sistema escaló automáticamente ${ticket.humanCode} por falta de reconocimiento.`,
      metadata: {
        dueAt,
        nextAutomaticEscalationAt,
        maximumLevel: settings.maximumAutomaticEscalationLevel
      },
      correlationId: eventId,
      source: "scheduler"
    });
    return true;
  });
}

export const checkOverdueTickets = onSchedule(
  {
    region: FUNCTION_REGION,
    schedule: "every 5 minutes",
    timeZone: DISPLAY_TIME_ZONE,
    retryCount: 3,
    maxRetrySeconds: 300,
    timeoutSeconds: 300,
    memory: "256MiB"
  },
  async () => {
    const settings = await readMaintenanceSettings();
    if (!settings.automaticEscalationEnabled) {
      logger.info("Automatic maintenance escalation is disabled.");
      return;
    }
    const now = Timestamp.now();
    const dueSnapshot = await db
      .collection("tickets")
      .where("isOpen", "==", true)
      .where("nextAutomaticEscalationAt", "<=", now)
      .orderBy("nextAutomaticEscalationAt", "asc")
      .limit(100)
      .get();

    let escalated = 0;
    for (let offset = 0; offset < dueSnapshot.docs.length; offset += 10) {
      const batch = dueSnapshot.docs.slice(offset, offset + 10);
      const results = await Promise.all(
        batch.map((document) => escalateDueTicket(document.id, settings))
      );
      escalated += results.filter(Boolean).length;
    }
    logger.info("Automatic escalation scan completed", {
      candidates: dueSnapshot.size,
      escalated
    });
  }
);
