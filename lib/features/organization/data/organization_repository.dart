import '../domain/organization_models.dart';

abstract interface class OrganizationRepository {
  Stream<List<Company>> watchCompanies({bool includeInactive = true});
  Stream<List<WorkArea>> watchAreas(
    String companyId, {
    bool includeInactive = true,
  });
  Stream<List<AppUser>> watchUsers();
  Stream<List<CatalogItem>> watchCatalog(
    String companyId,
    String areaId,
    CatalogKind kind, {
    bool includeInactive = false,
  });
  Future<Company?> getCompany(String id);
  Future<WorkArea?> getArea(String id);
  Future<AppUser?> getUser(String id);
  Future<void> saveCompany(Company company);
  Future<void> saveArea(WorkArea area);
  Future<void> saveUser(AppUser user, {String? newPassword});
  Future<void> resetPassword(String userId, String newPassword);
  Future<void> saveCatalogItem(CatalogItem item);
  Future<void> close();
}

abstract interface class AuthenticationRepository {
  Future<bool> needsBootstrap();
  Future<AppUser> bootstrapOwner({
    required String username,
    required String displayName,
    required String password,
  });
  Future<AppUser> authenticate(String username, String password);
  Future<AppUser?> findUser(String id);
  Future<void> recordActivity(String userId);
  Future<bool> isContextAvailable(
    AppUser user,
    String companyId,
    String areaId,
  );
}
