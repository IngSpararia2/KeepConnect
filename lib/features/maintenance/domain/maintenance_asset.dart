import 'package:cloud_firestore/cloud_firestore.dart';

class MaintenanceAsset {
  const MaintenanceAsset({
    required this.id,
    required this.name,
    required this.code,
    required this.departmentId,
    required this.location,
    required this.critical,
    required this.active,
  });

  final String id;
  final String name;
  final String code;
  final String departmentId;
  final String location;
  final bool critical;
  final bool active;

  factory MaintenanceAsset.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final map = document.data() ?? const <String, dynamic>{};
    return MaintenanceAsset(
      id: document.id,
      name: (map['name'] as String?) ?? document.id,
      code: (map['code'] as String?) ?? '',
      departmentId: (map['departmentId'] as String?) ?? '',
      location: (map['location'] as String?) ?? '',
      critical: map['critical'] == true,
      active: map['active'] != false,
    );
  }
}
