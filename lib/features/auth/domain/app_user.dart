import '../../../core/utils/firestore_value.dart';

enum UserRole {
  admin,
  production,
  maintenance;

  static UserRole fromValue(Object? value) => UserRole.values.firstWhere(
    (role) => role.name == value,
    orElse: () => UserRole.production,
  );

  String get label => switch (this) {
    UserRole.admin => 'Administrador',
    UserRole.production => 'Producción',
    UserRole.maintenance => 'Mantenimiento',
  };
}

class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.departmentId,
    required this.active,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final String departmentId;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isAdmin => role == UserRole.admin;
  bool get isProduction => role == UserRole.production;
  bool get isMaintenance => role == UserRole.maintenance;

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      name: (map['name'] as String?)?.trim().isNotEmpty == true
          ? (map['name'] as String).trim()
          : 'Usuario',
      email: (map['email'] as String?) ?? '',
      role: UserRole.fromValue(map['role']),
      departmentId: (map['departmentId'] as String?) ?? '',
      active: map['active'] == true,
      createdAt: dateTimeFromFirestore(map['createdAt']),
      updatedAt: dateTimeFromFirestore(map['updatedAt']),
    );
  }
}
