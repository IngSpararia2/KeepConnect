import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/features/maintenance/domain/create_ticket_input.dart';
import 'package:gestion_interna/features/maintenance/domain/maintenance_ticket.dart';
import 'package:gestion_interna/features/maintenance/domain/status_transition_policy.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_question.dart';

void main() {
  group('flujo de estados', () {
    test('solo mantenimiento avanza un paso', () {
      expect(
        StatusTransitionPolicy.next(TicketStatus.pending, AppRole.production),
        isNull,
      );
      expect(
        StatusTransitionPolicy.next(TicketStatus.pending, AppRole.maintenance),
        TicketStatus.acknowledged,
      );
      expect(
        StatusTransitionPolicy.canTransition(
          from: TicketStatus.pending,
          to: TicketStatus.inProgress,
          role: AppRole.maintenance,
        ),
        isFalse,
      );
    });
    test('finalizado es terminal', () {
      expect(
        StatusTransitionPolicy.next(TicketStatus.closed, AppRole.maintenance),
        isNull,
      );
    });
  });

  group('preguntas', () {
    test('selección exige opciones válidas y no duplicadas', () {
      const empty = TicketQuestion(
        id: 'q1',
        prompt: 'Estado',
        type: QuestionType.singleChoice,
        required: true,
        order: 0,
      );
      const duplicate = TicketQuestion(
        id: 'q2',
        prompt: 'Estado',
        type: QuestionType.multipleChoice,
        required: true,
        order: 0,
        options: ['Bien', 'Bien'],
      );
      expect(empty.validate(), isNotNull);
      expect(duplicate.validate(), isNotNull);
    });
    test('respuesta obligatoria determina formulario completo', () {
      final now = DateTime(2026);
      MaintenanceTicket ticket(List<String> answer) => MaintenanceTicket(
        id: 't',
        humanCode: 'MTTO-0001',
        title: 'T',
        description: 'D',
        location: 'L',
        priority: TicketPriority.medium,
        status: TicketStatus.inProgress,
        createdAt: now,
        updatedAt: now,
        questions: [
          TicketQuestion(
            id: 'q',
            prompt: 'Diagnóstico',
            type: QuestionType.freeText,
            required: true,
            order: 0,
            answer: answer,
          ),
        ],
      );
      expect(ticket([]).isFormComplete, isFalse);
      expect(ticket(['Listo']).isFormComplete, isTrue);
    });
    test('ticket sin preguntas es válido', () {
      const input = CreateTicketInput(
        title: 'Falla',
        description: 'Descripción',
        location: 'Línea 1',
        priority: TicketPriority.low,
      );
      expect(input.validate(), isEmpty);
    });
  });
}
