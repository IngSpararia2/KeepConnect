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
    required this.user,
    required this.selectedCompanyId,
    required this.selectedAreaId,
  });

  static const _userIdKey = 'session_user_id';
  static const _companyIdKey = 'session_company_id';
  static const _areaIdKey = 'session_area_id';

  final SessionStore _store;
  AppUser? user;
  String? selectedCompanyId;
  String? selectedAreaId;

  static Future<LocalSession> load({
    SessionStore? store,
    Future<AppUser?> Function(String id)? resolveUser,
  }) async {
    final sessionStore = store ?? SharedPreferencesSessionStore();
    final userId = await sessionStore.getString(_userIdKey);
    AppUser? user;
    if (userId != null && resolveUser != null) user = await resolveUser(userId);
    if (user?.active != true) user = null;
    return LocalSession._(
      sessionStore,
      user: user,
      selectedCompanyId: user == null
          ? null
          : await sessionStore.getString(_companyIdKey),
      selectedAreaId: user == null
          ? null
          : await sessionStore.getString(_areaIdKey),
    );
  }

  bool get loggedIn => user != null;
  bool get isSuperAdmin => user?.isSuperAdmin ?? false;
  AppRole get effectiveRole => user?.operationalRole ?? AppRole.production;

  AccessContext? get accessContext {
    final current = user;
    if (current == null) return null;
    final companyId = current.isSuperAdmin
        ? selectedCompanyId
        : current.companyId;
    return AccessContext(
      userId: current.id,
      privilege: current.privilege,
      operationalRole: effectiveRole,
      companyId: companyId,
      areaId: selectedAreaId,
      allowedAreaIds: current.areaIds,
      allCompanyAreas: current.areaAccessMode == AreaAccessMode.all,
    );
  }

  Future<void> start(AppUser authenticatedUser) async {
    if (!authenticatedUser.active) {
      throw StateError('Esta cuenta está deshabilitada.');
    }
    user = authenticatedUser;
    selectedCompanyId = authenticatedUser.companyId;
    selectedAreaId = null;
    await _store.setString(_userIdKey, authenticatedUser.id);
    if (selectedCompanyId case final company?) {
      await _store.setString(_companyIdKey, company);
    } else {
      await _store.remove(_companyIdKey);
    }
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
    selectedCompanyId = companyId;
    selectedAreaId = areaId;
    await _store.setString(_companyIdKey, companyId);
    await _store.setString(_areaIdKey, areaId);
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
