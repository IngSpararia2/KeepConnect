import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_value.dart';
import 'ticket_enums.dart';

class MaintenanceTicket {
  const MaintenanceTicket({
    required this.id,
    required this.humanCode,
    required this.title,
    required this.description,
    required this.categoryId,
    required this.requesterUid,
    required this.requesterName,
    required this.sourceDepartmentId,
    required this.targetDepartmentId,
    required this.location,
    required this.productionStopped,
    required this.safetyRisk,
    required this.suggestedPriority,
    required this.priority,
    required this.status,
    required this.participantUids,
    required this.escalationCount,
    required this.dynamicAnswers,
    this.assetId,
    this.categoryName,
    this.assetName,
    this.assetCode,
    this.assetCritical = false,
    this.impactPercent,
    this.impactNotes,
    this.priorityScore = 0,
    this.priorityPolicyVersion = 'demo-v1',
    this.priorityFactors = const [],
    this.priorityOverrideReason,
    this.primaryAssigneeUid,
    this.primaryAssigneeName,
    this.diagnosis,
    this.workPerformed,
    this.resolutionNotes,
    this.createdAt,
    this.updatedAt,
    this.acknowledgedAt,
    this.assignedAt,
    this.workStartedAt,
    this.resolvedAt,
    this.closedAt,
    this.productionStoppedAt,
    this.productionResumedAt,
    this.lastManualEscalationAt,
    this.lastAutomaticEscalationAt,
  });

  final String id;
  final String humanCode;
  final String title;
  final String description;
  final String categoryId;
  final String? categoryName;
  final String requesterUid;
  final String requesterName;
  final String sourceDepartmentId;
  final String targetDepartmentId;
  final String location;
  final String? assetId;
  final String? assetName;
  final String? assetCode;
  final bool assetCritical;
  final bool productionStopped;
  final bool safetyRisk;
  final int? impactPercent;
  final String? impactNotes;
  final TicketPriority suggestedPriority;
  final int priorityScore;
  final String priorityPolicyVersion;
  final List<String> priorityFactors;
  final TicketPriority priority;
  final String? priorityOverrideReason;
  final TicketStatus status;
  final String? primaryAssigneeUid;
  final String? primaryAssigneeName;
  final List<String> participantUids;
  final int escalationCount;
  final Map<String, Object?> dynamicAnswers;
  final String? diagnosis;
  final String? workPerformed;
  final String? resolutionNotes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? acknowledgedAt;
  final DateTime? assignedAt;
  final DateTime? workStartedAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final DateTime? productionStoppedAt;
  final DateTime? productionResumedAt;
  final DateTime? lastManualEscalationAt;
  final DateTime? lastAutomaticEscalationAt;

  bool get isOpen => status.isOpen;

  factory MaintenanceTicket.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final map = document.data() ?? const <String, dynamic>{};
    final asset = objectMapFromFirestore(map['assetSnapshot']);
    return MaintenanceTicket(
      id: document.id,
      humanCode: (map['humanCode'] as String?) ?? document.id,
      title: (map['title'] as String?) ?? 'Sin título',
      description: (map['description'] as String?) ?? '',
      categoryId: (map['categoryId'] as String?) ?? 'other',
      categoryName: map['categoryName'] as String?,
      requesterUid: (map['requesterUid'] as String?) ?? '',
      requesterName: (map['requesterName'] as String?) ?? 'Usuario',
      sourceDepartmentId: (map['sourceDepartmentId'] as String?) ?? '',
      targetDepartmentId: (map['targetDepartmentId'] as String?) ?? '',
      location: (map['location'] as String?) ?? '',
      assetId: map['assetId'] as String?,
      assetName: (asset['name'] ?? map['assetName']) as String?,
      assetCode: (asset['code'] ?? map['assetCode']) as String?,
      assetCritical: asset['critical'] == true || map['assetCritical'] == true,
      productionStopped: map['productionStopped'] == true,
      safetyRisk: map['safetyRisk'] == true,
      impactPercent: ((map['impactPercentage'] ?? map['impactPercent']) as num?)
          ?.toInt(),
      impactNotes: map['impactNotes'] as String?,
      suggestedPriority: TicketPriority.fromValue(map['suggestedPriority']),
      priorityScore: (map['priorityScore'] as num?)?.toInt() ?? 0,
      priorityPolicyVersion:
          (map['priorityPolicyVersion'] as String?) ?? 'demo-v1',
      priorityFactors: stringListFromFirestore(map['priorityFactors']),
      priority: TicketPriority.fromValue(map['priority']),
      priorityOverrideReason: map['priorityOverrideReason'] as String?,
      status: TicketStatus.fromValue(map['status']),
      primaryAssigneeUid: map['primaryAssigneeUid'] as String?,
      primaryAssigneeName: map['primaryAssigneeName'] as String?,
      participantUids: stringListFromFirestore(map['participantUids']),
      escalationCount: (map['escalationCount'] as num?)?.toInt() ?? 0,
      dynamicAnswers: objectMapFromFirestore(
        map['formResponses'] ?? map['dynamicAnswers'],
      ),
      diagnosis: map['diagnosis'] as String?,
      workPerformed: map['workPerformed'] as String?,
      resolutionNotes: map['resolutionNotes'] as String?,
      createdAt: dateTimeFromFirestore(map['createdAt']),
      updatedAt: dateTimeFromFirestore(map['updatedAt']),
      acknowledgedAt: dateTimeFromFirestore(map['acknowledgedAt']),
      assignedAt: dateTimeFromFirestore(map['assignedAt']),
      workStartedAt: dateTimeFromFirestore(map['workStartedAt']),
      resolvedAt: dateTimeFromFirestore(map['resolvedAt']),
      closedAt: dateTimeFromFirestore(map['closedAt']),
      productionStoppedAt: dateTimeFromFirestore(map['productionStoppedAt']),
      productionResumedAt: dateTimeFromFirestore(map['productionResumedAt']),
      lastManualEscalationAt: dateTimeFromFirestore(
        map['lastManualEscalationAt'],
      ),
      lastAutomaticEscalationAt: dateTimeFromFirestore(
        map['lastAutomaticEscalationAt'],
      ),
    );
  }
}
