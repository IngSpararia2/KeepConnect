import '../../../core/utils/firestore_value.dart';
import 'priority_engine.dart';

class MaintenanceSettings {
  const MaintenanceSettings({
    required this.manualEscalationCooldownMinutes,
    required this.maxPhotosPerTicket,
    required this.maxPhotoBytes,
    required this.priorityPolicy,
  });

  static const defaults = MaintenanceSettings(
    manualEscalationCooldownMinutes: 15,
    maxPhotosPerTicket: 5,
    maxPhotoBytes: 5 * 1024 * 1024,
    priorityPolicy: PriorityPolicy.defaults,
  );

  final int manualEscalationCooldownMinutes;
  final int maxPhotosPerTicket;
  final int maxPhotoBytes;
  final PriorityPolicy priorityPolicy;

  factory MaintenanceSettings.fromMap(Map<String, Object?> map) {
    final policy = objectMapFromFirestore(map['priorityPolicy']);
    return MaintenanceSettings(
      manualEscalationCooldownMinutes:
          (map['manualEscalationCooldownMinutes'] as num?)?.toInt() ??
          defaults.manualEscalationCooldownMinutes,
      maxPhotosPerTicket:
          (map['maxPhotosPerTicket'] as num?)?.toInt() ??
          defaults.maxPhotosPerTicket,
      maxPhotoBytes:
          (map['maxPhotoBytes'] as num?)?.toInt() ?? defaults.maxPhotoBytes,
      priorityPolicy: policy.isEmpty
          ? PriorityPolicy.defaults
          : PriorityPolicy.fromMap(policy),
    );
  }
}
