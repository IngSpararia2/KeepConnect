import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_value.dart';
import '../../auth/domain/app_user.dart';

class AppModule {
  const AppModule({
    required this.id,
    required this.name,
    required this.description,
    required this.iconKey,
    required this.route,
    required this.sortOrder,
    required this.allowedRoles,
  });

  final String id;
  final String name;
  final String description;
  final String iconKey;
  final String route;
  final int sortOrder;
  final List<UserRole> allowedRoles;

  bool isVisibleFor(UserRole role) =>
      allowedRoles.isEmpty ||
      allowedRoles.contains(role) ||
      role == UserRole.admin;

  factory AppModule.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final map = document.data() ?? const <String, dynamic>{};
    return AppModule(
      id: document.id,
      name: (map['name'] as String?) ?? document.id,
      description: (map['description'] as String?) ?? '',
      iconKey: (map['iconKey'] as String?) ?? 'module',
      route: (map['route'] as String?) ?? '/${document.id}',
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      allowedRoles: stringListFromFirestore(
        map['allowedRoles'],
      ).map(UserRole.fromValue).toList(growable: false),
    );
  }

  static const maintenanceFallback = AppModule(
    id: 'maintenance',
    name: 'Mantenimiento',
    description:
        'Reportes, asignaciones, seguimiento y cierre con trazabilidad completa.',
    iconKey: 'maintenance',
    route: '/maintenance',
    sortOrder: 1,
    allowedRoles: [],
  );
}
