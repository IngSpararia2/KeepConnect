import 'ticket_enums.dart';
import 'ticket_question.dart';

class MaintenanceTicket {
  const MaintenanceTicket({
    required this.id,
    required this.humanCode,
    required this.title,
    required this.description,
    required this.location,
    required this.priority,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.equipment,
    this.companyId = 'legacy-company',
    this.areaId = 'legacy-area-plant',
    this.createdByUserId = 'legacy-system-user',
    this.locationOptionId,
    this.locationIsCustom = true,
    this.equipmentOptionId,
    this.equipmentIsCustom = false,
    this.questions = const [],
  });
  final String id;
  final String humanCode;
  final String title;
  final String description;
  final String location;
  final String? equipment;
  final String companyId;
  final String areaId;
  final String createdByUserId;
  final String? locationOptionId;
  final bool locationIsCustom;
  final String? equipmentOptionId;
  final bool equipmentIsCustom;
  final TicketPriority priority;
  final TicketStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TicketQuestion> questions;

  bool get isOpen => status.isOpen;
  bool get isFormComplete => questions.every((question) => question.isComplete);
  List<TicketQuestion> get missingRequiredQuestions =>
      questions.where((question) => !question.isComplete).toList();
}
