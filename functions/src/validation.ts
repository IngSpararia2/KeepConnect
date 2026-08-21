import { randomUUID } from "node:crypto";

import { HttpsError } from "firebase-functions/v2/https";

import {
  ATTACHMENT_KINDS,
  PRIORITIES,
  TICKET_STATUSES,
  type AttachmentKind,
  type DynamicTemplateFieldSnapshot,
  type Priority,
  type TicketStatus
} from "./types";

export function asRecord(value: unknown, label = "data"): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", `${label} debe ser un objeto.`);
  }
  return value as Record<string, unknown>;
}

export function requiredString(
  record: Record<string, unknown>,
  key: string,
  maximumLength: number,
  minimumLength = 1
): string {
  const value = record[key];
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${key} es obligatorio.`);
  }
  const normalized = value.trim();
  if (normalized.length < minimumLength || normalized.length > maximumLength) {
    throw new HttpsError(
      "invalid-argument",
      `${key} debe tener entre ${minimumLength} y ${maximumLength} caracteres.`
    );
  }
  return normalized;
}

export function optionalString(
  record: Record<string, unknown>,
  key: string,
  maximumLength: number
): string | null {
  const value = record[key];
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${key} debe ser texto.`);
  }
  const normalized = value.trim();
  if (normalized.length > maximumLength) {
    throw new HttpsError("invalid-argument", `${key} excede ${maximumLength} caracteres.`);
  }
  return normalized || null;
}

export function requiredBoolean(record: Record<string, unknown>, key: string): boolean {
  const value = record[key];
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", `${key} debe ser verdadero o falso.`);
  }
  return value;
}

export function optionalInteger(
  record: Record<string, unknown>,
  key: string,
  minimum: number,
  maximum: number
): number | null {
  const value = record[key];
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "number" || !Number.isInteger(value) || value < minimum || value > maximum) {
    throw new HttpsError("invalid-argument", `${key} debe ser un entero entre ${minimum} y ${maximum}.`);
  }
  return value;
}

export function optionalPositiveInteger(
  record: Record<string, unknown>,
  key: string,
  maximum: number
): number | null {
  return optionalInteger(record, key, 1, maximum);
}

export function parsePriority(value: unknown, key = "priority"): Priority {
  if (typeof value !== "string" || !PRIORITIES.includes(value as Priority)) {
    throw new HttpsError("invalid-argument", `${key} no es una prioridad válida.`);
  }
  return value as Priority;
}

export function parseOptionalPriority(value: unknown): Priority | null {
  return value === undefined || value === null || value === ""
    ? null
    : parsePriority(value, "selectedPriority");
}

export function parseStatus(value: unknown): TicketStatus {
  if (typeof value !== "string" || !TICKET_STATUSES.includes(value as TicketStatus)) {
    throw new HttpsError("invalid-argument", "toStatus no es un estado válido.");
  }
  return value as TicketStatus;
}

export function parseAttachmentKind(value: unknown): AttachmentKind {
  if (value === undefined || value === null || value === "") {
    return "evidence";
  }
  if (typeof value !== "string" || !ATTACHMENT_KINDS.includes(value as AttachmentKind)) {
    throw new HttpsError("invalid-argument", "kind no es un tipo de evidencia válido.");
  }
  return value as AttachmentKind;
}

export function parseStringArray(
  value: unknown,
  key: string,
  maximumItems: number,
  maximumItemLength = 128
): string[] {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value) || value.length > maximumItems) {
    throw new HttpsError("invalid-argument", `${key} debe ser una lista de máximo ${maximumItems} elementos.`);
  }
  const result = new Set<string>();
  for (const item of value) {
    if (typeof item !== "string" || item.trim().length === 0 || item.trim().length > maximumItemLength) {
      throw new HttpsError("invalid-argument", `${key} contiene un valor inválido.`);
    }
    result.add(item.trim());
  }
  return [...result];
}

export function parseMap(
  value: unknown,
  key: string,
  maximumBytes: number,
  maximumKeys: number
): Record<string, unknown> {
  if (value === undefined || value === null) {
    return {};
  }
  const record = asRecord(value, key);
  if (Object.keys(record).length > maximumKeys) {
    throw new HttpsError("invalid-argument", `${key} contiene demasiadas respuestas.`);
  }
  let serialized: string;
  try {
    serialized = JSON.stringify(record);
  } catch {
    throw new HttpsError("invalid-argument", `${key} no se puede serializar.`);
  }
  if (Buffer.byteLength(serialized, "utf8") > maximumBytes) {
    throw new HttpsError("invalid-argument", `${key} excede el tamaño permitido.`);
  }
  return record;
}

const DYNAMIC_FIELD_TYPES = new Set([
  "shortText",
  "longText",
  "number",
  "yesNo",
  "singleChoice",
  "multipleChoice",
  "checklist",
  "date",
  "photo"
]);

function templateError(message: string): never {
  throw new HttpsError("failed-precondition", `Plantilla dinámica inválida: ${message}`);
}

function configuredString(value: unknown, label: string, maximum: number): string {
  if (typeof value !== "string" || !value.trim() || value.trim().length > maximum) {
    return templateError(`${label} no es válido.`);
  }
  return value.trim();
}

function configuredOptions(value: unknown, fieldId: string): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length > 100) {
    return templateError(`options de ${fieldId} no es una lista válida.`);
  }
  const options: string[] = [];
  for (const item of value) {
    if (typeof item !== "string" || !item.trim() || item.trim().length > 200) {
      return templateError(`options de ${fieldId} contiene un valor inválido.`);
    }
    options.push(item.trim());
  }
  return [...new Set(options)];
}

function responseMissing(value: unknown): boolean {
  return value === undefined || value === null ||
    (typeof value === "string" && !value.trim()) ||
    (Array.isArray(value) && value.length === 0);
}

function validateChoice(value: unknown, field: DynamicTemplateFieldSnapshot): void {
  if (typeof value !== "string" || !field.options.includes(value)) {
    throw new HttpsError("invalid-argument", `${field.id} debe ser una opción permitida.`);
  }
}

function validateDynamicResponse(
  value: unknown,
  field: DynamicTemplateFieldSnapshot
): void {
  if (responseMissing(value)) {
    if (field.required) {
      throw new HttpsError("invalid-argument", `${field.id} es obligatorio.`);
    }
    return;
  }

  switch (field.type) {
    case "shortText":
    case "longText": {
      const maximum = field.type === "shortText" ? 2000 : 10_000;
      if (typeof value !== "string" || value.trim().length > maximum) {
        throw new HttpsError("invalid-argument", `${field.id} no es un texto válido.`);
      }
      return;
    }
    case "number": {
      if (typeof value !== "number" || !Number.isFinite(value)) {
        throw new HttpsError("invalid-argument", `${field.id} debe ser numérico.`);
      }
      const rules = field.validation ?? {};
      const minimum = rules.minimum;
      const maximum = rules.maximum;
      if (typeof minimum === "number" && value < minimum) {
        throw new HttpsError("invalid-argument", `${field.id} es menor que el mínimo.`);
      }
      if (typeof maximum === "number" && value > maximum) {
        throw new HttpsError("invalid-argument", `${field.id} supera el máximo.`);
      }
      return;
    }
    case "yesNo":
      if (typeof value !== "boolean") {
        throw new HttpsError("invalid-argument", `${field.id} debe ser verdadero o falso.`);
      }
      return;
    case "singleChoice":
      validateChoice(value, field);
      return;
    case "multipleChoice":
    case "checklist":
      if (!Array.isArray(value) || value.length > field.options.length) {
        throw new HttpsError("invalid-argument", `${field.id} debe ser una lista válida.`);
      }
      for (const item of value) validateChoice(item, field);
      if (new Set(value).size !== value.length) {
        throw new HttpsError("invalid-argument", `${field.id} contiene opciones duplicadas.`);
      }
      return;
    case "date":
      if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) {
        throw new HttpsError("invalid-argument", `${field.id} debe ser una fecha válida.`);
      }
      return;
    case "photo":
      throw new HttpsError(
        "invalid-argument",
        `${field.id} debe cargarse como evidencia y no como valor del formulario.`
      );
    default:
      return templateError(`tipo no soportado en ${field.id}.`);
  }
}

export function validateDynamicFormResponses(
  rawFields: unknown,
  responses: Record<string, unknown>
): DynamicTemplateFieldSnapshot[] {
  if (!Array.isArray(rawFields) || rawFields.length > 100) {
    return templateError("fields debe ser una lista de máximo 100 elementos.");
  }
  const fields: DynamicTemplateFieldSnapshot[] = [];
  const ids = new Set<string>();
  for (const item of rawFields) {
    if (typeof item !== "object" || item === null || Array.isArray(item)) {
      return templateError("cada field debe ser un objeto.");
    }
    const raw = item as Record<string, unknown>;
    const id = configuredString(raw.id, "field.id", 80);
    if (!/^[A-Za-z][A-Za-z0-9_-]*$/.test(id) || ids.has(id)) {
      return templateError(`field.id ${id} está repetido o no es seguro.`);
    }
    ids.add(id);
    const type = configuredString(raw.type, `${id}.type`, 40);
    if (!DYNAMIC_FIELD_TYPES.has(type)) return templateError(`tipo ${type} no soportado.`);
    const options = configuredOptions(raw.options, id);
    if ((type === "singleChoice" || type === "multipleChoice" || type === "checklist") &&
      options.length === 0) {
      return templateError(`${id} necesita opciones.`);
    }
    const validation = raw.validation === undefined || raw.validation === null
      ? null
      : asRecord(raw.validation, `${id}.validation`);
    const field: DynamicTemplateFieldSnapshot = {
      id,
      type,
      label: configuredString(raw.label, `${id}.label`, 240),
      required: raw.required === true,
      options,
      validation
    };
    if (field.type === "photo" && field.required) {
      return templateError(`${id} no puede ser fotografía obligatoria en esta versión.`);
    }
    fields.push(field);
  }

  for (const key of Object.keys(responses)) {
    if (!ids.has(key)) {
      throw new HttpsError("invalid-argument", `formResponses contiene la clave desconocida ${key}.`);
    }
  }
  for (const field of fields) validateDynamicResponse(responses[field.id], field);
  return fields;
}

export function commandRequestId(record: Record<string, unknown>): string {
  const value = record.requestId;
  if (value === undefined || value === null || value === "") {
    return randomUUID();
  }
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{8,128}$/.test(value)) {
    throw new HttpsError(
      "invalid-argument",
      "requestId debe contener de 8 a 128 caracteres alfanuméricos, guion o guion bajo."
    );
  }
  return value;
}

export function normalizeSearchText(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

export function buildSearchTokens(values: string[]): string[] {
  const tokens = new Set<string>();
  for (const value of values) {
    for (const word of normalizeSearchText(value).split(" ")) {
      if (!word) continue;
      tokens.add(word.slice(0, 40));
      for (let length = 2; length <= Math.min(word.length, 12); length += 1) {
        tokens.add(word.slice(0, length));
        if (tokens.size >= 80) return [...tokens];
      }
    }
  }
  return [...tokens];
}

export function safeStorageFileName(value: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$/.test(value) && !value.includes("..");
}
