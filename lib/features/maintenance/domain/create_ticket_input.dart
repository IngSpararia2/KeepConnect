import 'ticket_enums.dart';
import 'ticket_question.dart';

class CreateTicketInput {
  const CreateTicketInput({
    required this.title,
    required this.description,
    required this.location,
    required this.priority,
    this.equipment,
    this.locationOptionId,
    this.locationIsCustom = true,
    this.equipmentOptionId,
    this.equipmentIsCustom = true,
    this.questions = const [],
  });
  final String title;
  final String description;
  final String location;
  final String? equipment;
  final String? locationOptionId;
  final bool locationIsCustom;
  final String? equipmentOptionId;
  final bool equipmentIsCustom;
  final TicketPriority priority;
  final List<TicketQuestion> questions;

  List<String> validate() => [
    if (title.trim().isEmpty) 'El título es obligatorio.',
    if (description.trim().isEmpty) 'La descripción es obligatoria.',
    if (location.trim().isEmpty) 'La ubicación es obligatoria.',
    if (!locationIsCustom && locationOptionId == null)
      'Selecciona una ubicación administrada.',
    if (locationIsCustom && location.trim().isEmpty)
      'Escribe la ubicación personalizada.',
    if (equipmentIsCustom && equipment != null && equipment!.trim().isEmpty)
      'Escribe el equipo personalizado.',
    if (!equipmentIsCustom &&
        equipment?.trim().isNotEmpty == true &&
        equipmentOptionId == null)
      'Selecciona un equipo administrado.',
    for (var i = 0; i < questions.length; i++)
      if (questions[i].validate() case final error?)
        'Pregunta ${i + 1}: $error',
  ];
}

class CreatedTicketResult {
  const CreatedTicketResult({required this.ticketId, required this.humanCode});
  final String ticketId;
  final String humanCode;
}
