enum TicketPriority {
  low,
  medium,
  high,
  critical;

  static TicketPriority fromValue(Object? value) => TicketPriority.values
      .firstWhere((item) => item.name == value, orElse: () => medium);
  String get label => switch (this) {
    low => 'Baja',
    medium => 'Media',
    high => 'Alta',
    critical => 'Crítica',
  };
}

enum TicketStatus {
  pending,
  acknowledged,
  inProgress,
  closed;

  static TicketStatus fromValue(Object? value) => TicketStatus.values
      .firstWhere((item) => item.name == value, orElse: () => pending);
  String get label => switch (this) {
    pending => 'Pendiente',
    acknowledged => 'En revisión',
    inProgress => 'En ejecución',
    closed => 'Finalizado',
  };
  bool get isOpen => this != closed;
}

enum QuestionType {
  freeText,
  singleChoice,
  multipleChoice;

  static QuestionType fromValue(Object? value) => QuestionType.values
      .firstWhere((item) => item.name == value, orElse: () => freeText);
  String get label => switch (this) {
    freeText => 'Texto libre',
    singleChoice => 'Selección única',
    multipleChoice => 'Selección múltiple',
  };
}

enum AppRole {
  production,
  maintenance;

  String get label => this == production ? 'Planta' : 'Mantenimiento';
  AppRole get other => this == production ? maintenance : production;
}

enum TicketUpdateType {
  note,
  instruction,
  observation,
  action;

  String get label => switch (this) {
    note => 'Nota adicional',
    instruction => 'Nueva instrucción',
    observation => 'Observación / novedad',
    action => 'Acción realizada',
  };
}

enum TicketEventType {
  created,
  statusChanged,
  questionAdded,
  answersSaved,
  formCompleted,
  updateAdded,
  closed;

  static TicketEventType fromValue(Object? value) => TicketEventType.values
      .firstWhere((item) => item.name == value, orElse: () => statusChanged);
}
