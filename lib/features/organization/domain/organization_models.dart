import '../../maintenance/domain/ticket_enums.dart';

enum PlatformPrivilege { superAdmin, user }

enum AreaAccessMode { all, selected }

enum CatalogKind {
  location,
  equipment;

  String get label =>
      this == location ? 'Ubicación / zona' : 'Equipo / máquina';
}

class Company {
  const Company({
    required this.id,
    required this.name,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  Company copyWith({String? name, bool? active, DateTime? updatedAt}) =>
      Company(
        id: id,
        name: name ?? this.name,
        active: active ?? this.active,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class WorkArea {
  const WorkArea({
    required this.id,
    required this.companyId,
    required this.name,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String name;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkArea copyWith({String? name, bool? active, DateTime? updatedAt}) =>
      WorkArea(
        id: id,
        companyId: companyId,
        name: name ?? this.name,
        active: active ?? this.active,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.privilege,
    required this.active,
    required this.areaAccessMode,
    required this.areaIds,
    required this.createdAt,
    required this.updatedAt,
    this.companyId,
    this.operationalRole,
    this.lastSeenAt,
  });

  final String id;
  final String username;
  final String displayName;
  final PlatformPrivilege privilege;
  final String? companyId;
  final AppRole? operationalRole;
  final bool active;
  final AreaAccessMode areaAccessMode;
  final Set<String> areaIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSeenAt;

  bool get isSuperAdmin => privilege == PlatformPrivilege.superAdmin;
  bool canAccessArea(String company, String area) =>
      isSuperAdmin ||
      (active &&
          companyId == company &&
          (areaAccessMode == AreaAccessMode.all || areaIds.contains(area)));
}

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.companyId,
    required this.areaId,
    required this.kind,
    required this.name,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String areaId;
  final CatalogKind kind;
  final String name;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  CatalogItem copyWith({String? name, bool? active, DateTime? updatedAt}) =>
      CatalogItem(
        id: id,
        companyId: companyId,
        areaId: areaId,
        kind: kind,
        name: name ?? this.name,
        active: active ?? this.active,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class AccessContext {
  const AccessContext({
    required this.userId,
    required this.privilege,
    required this.operationalRole,
    required this.companyId,
    required this.areaId,
    this.allowedAreaIds = const {},
    this.allCompanyAreas = false,
  });

  final String userId;
  final PlatformPrivilege privilege;
  final AppRole operationalRole;
  final String? companyId;
  final String? areaId;
  final Set<String> allowedAreaIds;
  final bool allCompanyAreas;

  bool get isSuperAdmin => privilege == PlatformPrivilege.superAdmin;
  bool permits(String company, String area) =>
      isSuperAdmin ||
      (companyId == company &&
          areaId == area &&
          (allCompanyAreas || allowedAreaIds.contains(area)));

  static const legacy = AccessContext(
    userId: 'legacy-system-user',
    privilege: PlatformPrivilege.superAdmin,
    operationalRole: AppRole.production,
    companyId: 'legacy-company',
    areaId: 'legacy-area-plant',
  );
}
