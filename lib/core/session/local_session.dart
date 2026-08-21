import 'package:shared_preferences/shared_preferences.dart';

import '../../features/maintenance/domain/ticket_enums.dart';

class LocalSession {
  LocalSession(this._preferences, {bool? areaSelected, AppRole? role})
    : areaSelected = areaSelected ?? false,
      role = role ?? AppRole.production;

  final SharedPreferencesAsync _preferences;
  bool areaSelected;
  AppRole role;

  static Future<LocalSession> load() async {
    final preferences = SharedPreferencesAsync();
    final roleName = await preferences.getString('test_role');
    return LocalSession(
      preferences,
      areaSelected: await preferences.getBool('area_selected') ?? false,
      role: AppRole.values.firstWhere(
        (role) => role.name == roleName,
        orElse: () => AppRole.production,
      ),
    );
  }

  Future<void> selectPlant() async {
    areaSelected = true;
    await _preferences.setBool('area_selected', true);
  }

  Future<void> setRole(AppRole value) async {
    role = value;
    await _preferences.setString('test_role', value.name);
  }
}
