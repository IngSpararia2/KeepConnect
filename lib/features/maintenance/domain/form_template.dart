import 'ticket_question.dart';

class FormTemplate {
  const FormTemplate({
    required this.id,
    required this.name,
    required this.questions,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.companyId = 'legacy-company',
    this.areaId = 'legacy-area-plant',
  });

  final String id;
  final String name;
  final String? description;
  final String companyId;
  final String? areaId;
  final List<TicketQuestion> questions;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<String> validate() => [
    if (name.trim().isEmpty) 'El nombre es obligatorio.',
    if (questions.isEmpty) 'Añade al menos una pregunta.',
    for (var index = 0; index < questions.length; index++)
      if (questions[index].validate() case final error?)
        'Pregunta ${index + 1}: $error',
  ];

  List<TicketQuestion> instantiateQuestions(String Function() createId) => [
    for (var index = 0; index < questions.length; index++)
      TicketQuestion(
        id: createId(),
        prompt: questions[index].prompt,
        type: questions[index].type,
        required: questions[index].required,
        order: index,
        options: List<String>.of(questions[index].options),
      ),
  ];
}
