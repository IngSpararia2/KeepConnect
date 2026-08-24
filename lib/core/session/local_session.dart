import 'package:shared_preferences/shared_preferences.dart';

import '../../features/maintenance/domain/ticket_enums.dart';
import '../../features/organization/domain/organization_models.dart';

abstract interface class SessionStore {
  Future<bool?> getBool(String key);
  Future<String?> getString(String key);
  Future<void> setBool(String key, bool value);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

final class SharedPreferencesSessionStore implements SessionStore {
  SharedPreferencesSessionStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;
  @override
  Future<bool?> getBool(String key) => _preferences.getBool(key);
  @override
  Future<String?> getString(String key) => _preferences.getString(key);
  @override
  Future<void> setBool(String key, bool value) =>
      _preferences.setBool(key, value);
  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);
  @override
  Future<void> remove(String key) => _preferences.remove(key);
}

class LocalSession {
  LocalSession._(
    this._store, {
    required this.validateContext,
    required this.user,
    required this.selectedCompanyId,
    required this.selectedAreaId,
  });

  static const _userIdKey = 'session_user_id';
  static const _companyIdKey = 'session_company_id';
  static const _areaIdKey = 'session_area_id';

  final SessionStore _store;
  final Future<bool> Function(AppUser user, String companyId, String areaId)?
  validateContext;
  AppUser? user;
  String? selectedCompanyId;
  String? selectedAreaId;

  static Future<LocalSession> load({
    SessionStore? store,
    Future<AppUser?> Function(String id)? resolveUser,
    Future<bool> Function(AppUser user, String companyId, String areaId)?
    validateContext,
  }) async {
    final sessionStore = store ?? SharedPreferencesSessionStore();
    final userId = await sessionStore.getString(_userIdKey);
    AppUser? user;
    if (userId != null && resolveUser != null) user = await resolveUser(userId);
    if (user?.active != true) user = null;
    var selectedCompanyId = user == null
        ? null
        : await sessionStore.getString(_companyIdKey);
    var selectedAreaId = user == null
        ? null
        : await sessionStore.getString(_areaIdKey);
    if (user != null && selectedCompanyId != null && selectedAreaId != null) {
      final valid =
          user.canAccessArea(selectedCompanyId, selectedAreaId) &&
          (validateContext == null ||
              await validateContext(user, selectedCompanyId, selectedAreaId));
      if (!valid) {
        selectedCompanyId = null;
        selectedAreaId = null;
        await sessionStore.remove(_companyIdKey);
        await sessionStore.remove(_areaIdKey);
      }
    } else if (selectedCompanyId != null || selectedAreaId != null) {
      selectedCompanyId = null;
      selectedAreaId = null;
      await sessionStore.remove(_companyIdKey);
      await sessionStore.remove(_areaIdKey);
    }
    return LocalSession._(
      sessionStore,
      validateContext: validateContext,
      user: user,
      selectedCompanyId: selectedCompanyId,
      selectedAreaId: selectedAreaId,
    );
  }

  bool get loggedIn => user != null;
  bool get isSuperAdmin => user?.isSuperAdmin ?? false;
  AppRole get effectiveRole => user?.operationalRole ?? AppRole.production;

  AccessContext? get accessContext {
    final current = user;
    if (current == null) return null;
    return AccessContext(
      userId: current.id,
      privilege: current.privilege,
      operationalRole: effectiveRole,
      companyId: selectedCompanyId,
      areaId: selectedAreaId,
      allowedCompanyIds: current.companyIds,
      allowedAreaIds: current.areaIds,
      allCompanyAreas: current.areaAccessMode == AreaAccessMode.all,
    );
  }

  Future<void> start(AppUser authenticatedUser) async {
    if (!authenticatedUser.active) {
      throw StateError('Esta cuenta está deshabilitada.');
    }
    user = authenticatedUser;
    selectedCompanyId = null;
    selectedAreaId = null;
    await _store.setString(_userIdKey, authenticatedUser.id);
    await _store.remove(_companyIdKey);
    await _store.remove(_areaIdKey);
  }

  Future<void> selectArea({
    required String companyId,
    required String areaId,
  }) async {
    final current = user;
    if (current == null || !current.canAccessArea(companyId, areaId)) {
      throw StateError('No tienes acceso a esta área.');
    }
    if (validateContext != null &&
        !await validateContext!(current, companyId, areaId)) {
      throw StateError('La empresa o el área ya no está disponible.');
    }
    selectedCompanyId = companyId;
    selectedAreaId = areaId;
    await _store.setString(_companyIdKey, companyId);
    await _store.setString(_areaIdKey, areaId);
  }

  Future<void> clearContext() async {
    selectedCompanyId = null;
    selectedAreaId = null;
    await _store.remove(_companyIdKey);
    await _store.remove(_areaIdKey);
  }

  Future<void> logout() async {
    user = null;
    selectedCompanyId = null;
    selectedAreaId = null;
    await _store.remove(_userIdKey);
    await _store.remove(_companyIdKey);
    await _store.remove(_areaIdKey);
  }
}
