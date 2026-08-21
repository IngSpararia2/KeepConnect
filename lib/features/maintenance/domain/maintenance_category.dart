import 'package:cloud_firestore/cloud_firestore.dart';

class MaintenanceCategory {
  const MaintenanceCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final int sortOrder;

  factory MaintenanceCategory.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final map = document.data() ?? const <String, dynamic>{};
    return MaintenanceCategory(
      id: document.id,
      name: (map['name'] as String?) ?? document.id,
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  static const fallback = [
    MaintenanceCategory(id: 'repair', name: 'Reparación', sortOrder: 1),
    MaintenanceCategory(
      id: 'corrective-maintenance',
      name: 'Mantenimiento correctivo',
      sortOrder: 2,
    ),
    MaintenanceCategory(
      id: 'preventive-maintenance',
      name: 'Mantenimiento preventivo',
      sortOrder: 3,
    ),
    MaintenanceCategory(id: 'installation', name: 'Instalación', sortOrder: 4),
    MaintenanceCategory(id: 'modification', name: 'Modificación', sortOrder: 5),
    MaintenanceCategory(
      id: 'infrastructure',
      name: 'Infraestructura',
      sortOrder: 6,
    ),
    MaintenanceCategory(id: 'electricity', name: 'Electricidad', sortOrder: 7),
    MaintenanceCategory(
      id: 'plumbing',
      name: 'Agua / fontanería',
      sortOrder: 8,
    ),
    MaintenanceCategory(
      id: 'production-equipment',
      name: 'Equipos de producción',
      sortOrder: 9,
    ),
    MaintenanceCategory(id: 'tools', name: 'Herramientas', sortOrder: 10),
    MaintenanceCategory(id: 'furniture', name: 'Mobiliario', sortOrder: 11),
    MaintenanceCategory(id: 'safety', name: 'Seguridad', sortOrder: 12),
    MaintenanceCategory(id: 'other', name: 'Otro', sortOrder: 99),
  ];
}
