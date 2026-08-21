import 'ticket_enums.dart';

class TicketQuestion {
  const TicketQuestion({
    required this.id,
    required this.prompt,
    required this.type,
    required this.required,
    required this.order,
    this.options = const [],
    this.answer = const [],
  });
  final String id;
  final String prompt;
  final QuestionType type;
  final bool required;
  final int order;
  final List<String> options;
  final List<String> answer;

  String? validate() {
    if (prompt.trim().isEmpty) return 'Escribe el enunciado.';
    if (type != QuestionType.freeText) {
      final clean = options.map((e) => e.trim()).where((e) => e.isNotEmpty);
      if (clean.isEmpty) return 'Añade al menos una opción válida.';
      if (clean.toSet().length != clean.length) {
        return 'Las opciones no pueden repetirse.';
      }
    }
    return null;
  }

  bool get isAnswered => answer.any((value) => value.trim().isNotEmpty);
  bool get isComplete => !required || isAnswered;
  TicketQuestion copyWith({List<String>? answer}) => TicketQuestion(
    id: id,
    prompt: prompt,
    type: type,
    required: required,
    order: order,
    options: options,
    answer: answer ?? this.answer,
  );
}
