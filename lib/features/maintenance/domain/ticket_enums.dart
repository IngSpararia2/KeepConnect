enum TicketPriority {
  low,
  medium,
  high,
  critical;

  static TicketPriority fromValue(Object? value) =>
      TicketPriority.values.firstWhere(
        (priority) => priority.name == value,
        orElse: () => TicketPriority.medium,
      );

  String get label => switch (this) {
    TicketPriority.low => 'Baja',
    TicketPriority.medium => 'Media',
    TicketPriority.high => 'Alta',
    TicketPriority.critical => 'Crítica',
  };

  int get rank => index;
}

enum TicketStatus {
  pending,
  acknowledged,
  assigned,
  inProgress,
  waitingParts,
  waitingExternal,
  paused,
  resolved,
  closed,
  cancelled;

  static TicketStatus fromValue(Object? value) =>
      TicketStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => TicketStatus.pending,
      );

  String get label => switch (this) {
    TicketStatus.pending => 'Pendiente',
    TicketStatus.acknowledged => 'Recibido',
    TicketStatus.assigned => 'Asignado',
    TicketStatus.inProgress => 'En proceso',
    TicketStatus.waitingParts => 'En espera de repuesto',
    TicketStatus.waitingExternal => 'En espera externa',
    TicketStatus.paused => 'Pausado',
    TicketStatus.resolved => 'Resuelto',
    TicketStatus.closed => 'Cerrado',
    TicketStatus.cancelled => 'Cancelado',
  };

  bool get isOpen =>
      this != TicketStatus.closed && this != TicketStatus.cancelled;
}

enum DynamicFieldType {
  shortText,
  longText,
  number,
  yesNo,
  singleChoice,
  multipleChoice,
  checklist,
  date,
  photo;

  static DynamicFieldType fromValue(Object? value) =>
      DynamicFieldType.values.firstWhere(
        (type) => type.name == value,
        orElse: () => DynamicFieldType.shortText,
      );
}

enum TicketEventType {
  created,
  acknowledged,
  assigned,
  statusChanged,
  priorityChanged,
  commentAdded,
  attachmentAdded,
  urgencyEscalated,
  diagnosisAdded,
  resolved,
  closed,
  reopened,
  cancelled,
  productionImpactChanged;

  static TicketEventType fromValue(Object? value) => switch (value) {
    'created' || 'ticketCreated' => TicketEventType.created,
    'acknowledged' || 'ticketAcknowledged' => TicketEventType.acknowledged,
    'assigned' || 'assignmentChanged' => TicketEventType.assigned,
    'priorityChanged' => TicketEventType.priorityChanged,
    'commentAdded' => TicketEventType.commentAdded,
    'attachmentAdded' => TicketEventType.attachmentAdded,
    'urgencyEscalated' ||
    'manualEscalation' ||
    'automaticEscalation' => TicketEventType.urgencyEscalated,
    'diagnosisAdded' => TicketEventType.diagnosisAdded,
    'resolved' || 'ticketResolved' => TicketEventType.resolved,
    'closed' || 'ticketClosed' => TicketEventType.closed,
    'reopened' || 'ticketReopened' => TicketEventType.reopened,
    'cancelled' || 'ticketCancelled' => TicketEventType.cancelled,
    'productionImpactChanged' => TicketEventType.productionImpactChanged,
    _ => TicketEventType.statusChanged,
  };

  String get label => switch (this) {
    TicketEventType.created => 'Solicitud creada',
    TicketEventType.acknowledged => 'Solicitud recibida',
    TicketEventType.assigned => 'Asignación actualizada',
    TicketEventType.statusChanged => 'Estado actualizado',
    TicketEventType.priorityChanged => 'Prioridad actualizada',
    TicketEventType.commentAdded => 'Comentario añadido',
    TicketEventType.attachmentAdded => 'Evidencia añadida',
    TicketEventType.urgencyEscalated => 'Urgencia escalada',
    TicketEventType.diagnosisAdded => 'Diagnóstico añadido',
    TicketEventType.resolved => 'Solicitud resuelta',
    TicketEventType.closed => 'Solicitud cerrada',
    TicketEventType.reopened => 'Revisión solicitada',
    TicketEventType.cancelled => 'Solicitud cancelada',
    TicketEventType.productionImpactChanged =>
      'Impacto en producción actualizado',
  };
}
