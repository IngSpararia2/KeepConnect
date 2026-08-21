import 'package:shared_preferences/shared_preferences.dart';

import '../../features/maintenance/domain/ticket_enums.dart';

enum AccountRole {
  production,
  maintenance,
  administrator;

  String get label => switch (this) {
    production => 'Planta',
    maintenance => 'Mantenimiento',
    administrator => 'Administrador',
  };
}

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
    required this.loggedIn,
    required this.accountRole,
    required this._administratorView,
  });

  static const _loggedInKey = 'session_logged_in';
  static const _accountRoleKey = 'session_account_role';
  static const _administratorViewKey = 'session_administrator_view';

  final SessionStore _store;
  bool loggedIn;
  AccountRole? accountRole;
  AppRole _administratorView;

  static Future<LocalSession> load({SessionStore? store}) async {
    final sessionStore = store ?? SharedPreferencesSessionStore();
    final loggedIn = await sessionStore.getBool(_loggedInKey) ?? false;
    final accountRoleName = await sessionStore.getString(_accountRoleKey);
    final administratorViewName = await sessionStore.getString(
      _administratorViewKey,
    );
    final accountRole = AccountRole.values
        .where((role) => role.name == accountRoleName)
        .firstOrNull;
    return LocalSession._(
      sessionStore,
      loggedIn: loggedIn && accountRole != null,
      accountRole: loggedIn ? accountRole : null,
      administratorView: AppRole.values.firstWhere(
        (role) => role.name == administratorViewName,
        orElse: () => AppRole.production,
      ),
    );
  }

  AppRole get effectiveRole => switch (accountRole) {
    AccountRole.maintenance => AppRole.maintenance,
    AccountRole.administrator => _administratorView,
    _ => AppRole.production,
  };

  bool get canChangeEffectiveRole =>
      loggedIn && accountRole == AccountRole.administrator;

  Future<void> login(AccountRole role) async {
    loggedIn = true;
    accountRole = role;
    _administratorView = AppRole.production;
    await _store.setBool(_loggedInKey, true);
    await _store.setString(_accountRoleKey, role.name);
    if (role == AccountRole.administrator) {
      await _store.setString(_administratorViewKey, _administratorView.name);
    } else {
      await _store.remove(_administratorViewKey);
    }
  }

  Future<void> setEffectiveRole(AppRole role) async {
    if (!canChangeEffectiveRole) {
      throw StateError(
        'Solo una cuenta Administrador puede cambiar la vista operativa.',
      );
    }
    _administratorView = role;
    await _store.setString(_administratorViewKey, role.name);
  }

  Future<void> logout() async {
    loggedIn = false;
    accountRole = null;
    _administratorView = AppRole.production;
    await _store.remove(_loggedInKey);
    await _store.remove(_accountRoleKey);
    await _store.remove(_administratorViewKey);
  }
}
