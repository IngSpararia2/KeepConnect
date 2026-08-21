import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import { db } from "./firebase";
import { ROLES, type Actor, type Role, type TicketData } from "./types";

export async function requireActor(request: CallableRequest<unknown>): Promise<Actor> {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión para realizar esta acción.");
  }

  const snapshot = await db.doc(`users/${uid}`).get();
  if (!snapshot.exists) {
    throw new HttpsError("failed-precondition", "Tu cuenta no tiene un perfil de aplicación.");
  }
  const data = snapshot.data() ?? {};
  if (data.active !== true) {
    throw new HttpsError("permission-denied", "Tu cuenta está desactivada.");
  }
  const role = data.role as Role;
  if (typeof data.role !== "string" || !ROLES.includes(role)) {
    throw new HttpsError("permission-denied", "Tu perfil no tiene un rol válido.");
  }
  if (typeof data.departmentId !== "string" || !data.departmentId.trim()) {
    throw new HttpsError("failed-precondition", "Tu perfil no tiene un área válida.");
  }

  return {
    uid,
    name: typeof data.name === "string" && data.name.trim() ? data.name.trim() : "Usuario",
    email:
      typeof data.email === "string" && data.email.trim()
        ? data.email.trim()
        : request.auth?.token.email?.toString() ?? "",
    role,
    departmentId: data.departmentId.trim()
  };
}

export function isMaintenanceFor(actor: Actor, ticket: TicketData): boolean {
  return actor.role === "maintenance" && actor.departmentId === ticket.targetDepartmentId;
}

export function isRequester(actor: Actor, ticket: TicketData): boolean {
  return actor.uid === ticket.requesterUid;
}

export function isTicketParticipant(actor: Actor, ticket: TicketData): boolean {
  return (
    actor.role === "admin" ||
    isRequester(actor, ticket) ||
    isMaintenanceFor(actor, ticket) ||
    ticket.participantUids.includes(actor.uid)
  );
}

export function requireTicketParticipant(actor: Actor, ticket: TicketData): void {
  if (!isTicketParticipant(actor, ticket)) {
    throw new HttpsError("permission-denied", "No tienes acceso a esta solicitud.");
  }
}

export function requireMaintenanceManager(actor: Actor, ticket: TicketData): void {
  if (actor.role !== "admin" && !isMaintenanceFor(actor, ticket)) {
    throw new HttpsError("permission-denied", "Solo Mantenimiento autorizado puede realizar esta acción.");
  }
}
