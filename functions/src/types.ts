import type { Timestamp } from "firebase-admin/firestore";

export const ROLES = ["admin", "production", "maintenance"] as const;
export type Role = (typeof ROLES)[number];

export const PRIORITIES = ["low", "medium", "high", "critical"] as const;
export type Priority = (typeof PRIORITIES)[number];

export const TICKET_STATUSES = [
  "pending",
  "acknowledged",
  "assigned",
  "inProgress",
  "waitingParts",
  "waitingExternal",
  "paused",
  "resolved",
  "closed",
  "cancelled"
] as const;
export type TicketStatus = (typeof TICKET_STATUSES)[number];

export const ATTACHMENT_KINDS = [
  "evidence",
  "resolution",
  "dynamicForm",
  "comment"
] as const;
export type AttachmentKind = (typeof ATTACHMENT_KINDS)[number];

export interface Actor {
  uid: string;
  name: string;
  email: string;
  role: Role;
  departmentId: string;
}

export interface AssetSnapshot {
  id: string;
  code: string;
  name: string;
  location: string | null;
  critical: boolean;
}

export interface DynamicTemplateFieldSnapshot {
  id: string;
  type: string;
  label: string;
  required: boolean;
  options: string[];
  validation: Record<string, unknown> | null;
}

export interface FormTemplateSnapshot {
  id: string;
  name: string;
  version: number;
  fields: DynamicTemplateFieldSnapshot[];
}

export interface LastMutation {
  id: string;
  type: string;
  actorUid: string | null;
  actorName: string;
  at: Timestamp;
}

export interface TicketData {
  schemaVersion: number;
  moduleId: string;
  humanCode: string;
  title: string;
  description: string;
  categoryId: string;
  categoryName: string;
  sourceDepartmentId: string;
  targetDepartmentId: string;
  requesterUid: string;
  requesterName: string;
  requesterEmail: string;
  createdByUid: string;
  location: string;
  assetId: string | null;
  assetSnapshot: AssetSnapshot | null;
  productionStopped: boolean;
  productionStoppedAt: Timestamp | null;
  productionResumedAt: Timestamp | null;
  safetyRisk: boolean;
  impactPercentage: number | null;
  impactNotes: string | null;
  formTemplateId: string | null;
  formTemplateVersion: number | null;
  formTemplateSnapshot: FormTemplateSnapshot | null;
  formResponses: Record<string, unknown>;
  suggestedPriority: Priority;
  priorityScore: number;
  priorityPolicyVersion: string;
  priorityFactors: string[];
  priority: Priority;
  priorityRank: number;
  prioritySetByUid: string;
  prioritySetAt: Timestamp;
  priorityOverrideReason: string | null;
  status: TicketStatus;
  isOpen: boolean;
  statusChangedAt: Timestamp;
  primaryAssigneeUid: string | null;
  primaryAssigneeName: string | null;
  participantUids: string[];
  assignedByUid: string | null;
  assignedAt: Timestamp | null;
  lastAssignedAt: Timestamp | null;
  acknowledgedByUid: string | null;
  acknowledgedAt: Timestamp | null;
  workStartedAt: Timestamp | null;
  lastWorkResumedAt: Timestamp | null;
  diagnosis: string | null;
  workPerformed: string | null;
  resolutionNotes: string | null;
  resolvedByUid: string | null;
  resolvedAt: Timestamp | null;
  lastResolvedAt: Timestamp | null;
  resolutionAttemptCount: number;
  reopenCount: number;
  lastReopenedAt: Timestamp | null;
  closedByUid: string | null;
  closedAt: Timestamp | null;
  cancelledByUid: string | null;
  cancelledAt: Timestamp | null;
  cancellationReason: string | null;
  waitingReason: string | null;
  waitingSince: Timestamp | null;
  escalationCount: number;
  manualEscalationCount: number;
  lastManualEscalationAt: Timestamp | null;
  lastAutomaticEscalationAt: Timestamp | null;
  automaticEscalationLevel: number;
  nextAutomaticEscalationAt: Timestamp | null;
  lastEscalationType: "manual" | "automatic" | null;
  lastEscalationReason: string | null;
  attachmentCount: number;
  searchTokens: string[];
  createdAt: Timestamp;
  updatedAt: Timestamp;
  lastActivityAt: Timestamp;
  lastMutation: LastMutation;
}

export interface PriorityPolicy {
  version: string;
  productionStoppedWeight: number;
  safetyRiskWeight: number;
  criticalAssetWeight: number;
  moderateImpactWeight: number;
  severeImpactWeight: number;
  moderateImpactFromPercentage: number;
  severeImpactFromPercentage: number;
  mediumThreshold: number;
  highThreshold: number;
  criticalThreshold: number;
  safetyRiskMinimumPriority: Priority;
  stoppedCriticalAssetMinimumPriority: Priority;
}

export interface MaintenanceSettings {
  automaticEscalationEnabled: boolean;
  criticalAcknowledgementMinutes: number;
  highAcknowledgementMinutes: number;
  manualEscalationCooldownMinutes: number;
  automaticEscalationRepeatMinutes: number;
  maximumAutomaticEscalationLevel: number;
  maxPhotosPerTicket: number;
  maxPhotoBytes: number;
  priorityPolicy: PriorityPolicy;
}

export interface PrioritySuggestion {
  priority: Priority;
  score: number;
  factors: string[];
  policyVersion: string;
}

export interface AuditEventData {
  type: string;
  actorUid: string | null;
  actorName: string;
  actorRole: Role | "system";
  createdAt: Timestamp;
  previousValue: unknown;
  newValue: unknown;
  message: string;
  metadata: Record<string, unknown>;
  correlationId: string;
  source: "callable" | "trigger" | "scheduler";
}

export interface NotificationDescriptor {
  eventId: string;
  eventType: string;
  ticketId: string;
  humanCode: string;
  title: string;
  body: string;
  priority: Priority;
  urgent: boolean;
  actorUid: string | null;
  recipientUids: string[];
  includeMaintenanceDepartmentId?: string;
  includeAdmins?: boolean;
}
