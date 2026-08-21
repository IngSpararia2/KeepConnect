import 'maintenance_asset.dart';
import 'priority_engine.dart';
import 'ticket_enums.dart';

class CreateTicketInput {
  const CreateTicketInput({
    required this.title,
    required this.description,
    required this.sourceDepartmentId,
    required this.targetDepartmentId,
    required this.location,
    required this.categoryId,
    required this.productionStopped,
    required this.safetyRisk,
    required this.suggested,
    required this.priority,
    required this.dynamicAnswers,
    this.asset,
    this.impactPercent,
    this.impactNotes,
    this.priorityOverrideReason,
    this.templateId,
    this.templateVersion,
  });

  final String title;
  final String description;
  final String sourceDepartmentId;
  final String targetDepartmentId;
  final String location;
  final String categoryId;
  final MaintenanceAsset? asset;
  final bool productionStopped;
  final bool safetyRisk;
  final int? impactPercent;
  final String? impactNotes;
  final PriorityRecommendation suggested;
  final TicketPriority priority;
  final String? priorityOverrideReason;
  final String? templateId;
  final int? templateVersion;
  final Map<String, Object?> dynamicAnswers;

  Map<String, Object?> toCallableData({required String requestId}) => {
    'requestId': requestId,
    'moduleId': 'maintenance',
    'title': title.trim(),
    'description': description.trim(),
    'sourceDepartmentId': sourceDepartmentId,
    'targetDepartmentId': targetDepartmentId,
    'location': location.trim(),
    'categoryId': categoryId,
    'assetId': asset?.id,
    'productionStopped': productionStopped,
    'safetyRisk': safetyRisk,
    'impactPercentage': impactPercent,
    'impactNotes': impactNotes?.trim(),
    'suggestedPriority': suggested.priority.name,
    'priorityScore': suggested.score,
    'priorityPolicyVersion': suggested.policyVersion,
    'priorityFactors': suggested.factors,
    'selectedPriority': priority.name,
    'priorityOverrideReason': priorityOverrideReason?.trim(),
    'formTemplateId': templateId,
    'formTemplateVersion': templateVersion,
    'formResponses': dynamicAnswers,
  };
}

class CreatedTicketResult {
  const CreatedTicketResult({required this.ticketId, required this.humanCode});

  final String ticketId;
  final String humanCode;
}
