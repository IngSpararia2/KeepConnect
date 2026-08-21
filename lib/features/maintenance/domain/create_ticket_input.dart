import 'ticket_enums.dart';
import 'ticket_question.dart';

class CreateTicketInput {
  const CreateTicketInput({
    required this.title,
    required this.description,
    required this.location,
    required this.priority,
    this.equipment,
    this.questions = const [],
  });
  final String title;
  final String description;
  final String location;
  final String? equipment;
  final TicketPriority priority;
  final List<TicketQuestion> questions;

  List<String> validate() => [
    if (title.trim().isEmpty) 'El título es obligatorio.',
    if (description.trim().isEmpty) 'La descripción es obligatoria.',
    if (location.trim().isEmpty) 'La ubicación es obligatoria.',
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
