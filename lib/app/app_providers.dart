import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/notification_service.dart';
import '../core/session/local_session.dart';
import '../features/maintenance/data/maintenance_repository.dart';
import '../features/maintenance/domain/ticket_enums.dart';
import '../features/organization/data/organization_repository.dart';
import '../features/organization/domain/organization_models.dart';
import 'theme/theme_mode_store.dart';

final themeModeStoreProvider = Provider<ThemeModeStore>(
  (ref) => SharedPreferencesThemeModeStore(),
);

class ThemeModeController extends Notifier<ThemeMode> {
  var _changedByUser = false;

  @override
  ThemeMode build() {
    Future<void>.microtask(_load);
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final stored = await ref.read(themeModeStoreProvider).read();
      if (!_changedByUser) state = themeModeFromStorage(stored);
    } catch (_) {
      // SharedPreferences no tiene plataforma nativa en algunos widget tests.
      // El modo automático es también el fallback seguro de producción.
      if (!_changedByUser) state = ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    _changedByUser = true;
    state = mode;
    await ref.read(themeModeStoreProvider).write(mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

final notificationServiceProvider = Provider<NotificationGateway>(
  (ref) => throw StateError('Falta inicializar notificaciones.'),
);
final maintenanceRepositoryProvider = Provider<MaintenanceRepository>(
  (ref) => throw StateError('Falta inicializar el repositorio.'),
);
final organizationRepositoryProvider = Provider<OrganizationRepository>(
  (ref) => throw StateError('Falta inicializar organizaciones.'),
);
final authenticationRepositoryProvider = Provider<AuthenticationRepository>(
  (ref) => throw StateError('Falta inicializar autenticación.'),
);
final localSessionProvider = Provider<LocalSession>(
  (ref) => throw StateError('Falta inicializar la sesión.'),
);

class SessionState {
  const SessionState({
    required this.user,
    required this.companyId,
    required this.areaId,
  });

  final AppUser? user;
  final String? companyId;
  final String? areaId;
  bool get loggedIn => user != null;
  bool get hasSelectedContext =>
      loggedIn && companyId != null && areaId != null;
  bool get isSuperAdmin => user?.isSuperAdmin ?? false;
  AppRole get effectiveRole => user?.operationalRole ?? AppRole.production;
  AccessContext? get accessContext => user == null
      ? null
      : AccessContext(
          userId: user!.id,
          privilege: user!.privilege,
          operationalRole: effectiveRole,
          companyId: companyId,
          areaId: areaId,
          allowedCompanyIds: user!.companyIds,
          allowedAreaIds: user!.areaIds,
          allCompanyAreas: user!.areaAccessMode == AreaAccessMode.all,
        );
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => _snapshot(ref.read(localSessionProvider));

  SessionState _snapshot(LocalSession local) => SessionState(
    user: local.user,
    companyId: local.selectedCompanyId,
    areaId: local.selectedAreaId,
  );

  Future<void> login(String username, String password) async {
    final user = await ref
        .read(authenticationRepositoryProvider)
        .authenticate(username.trim(), password);
    final local = ref.read(localSessionProvider);
    await local.start(user);
    state = _snapshot(local);
  }

  Future<void> bootstrap({
    required String username,
    required String displayName,
    required String password,
  }) async {
    final user = await ref
        .read(authenticationRepositoryProvider)
        .bootstrapOwner(
          username: username,
          displayName: displayName,
          password: password,
        );
    final local = ref.read(localSessionProvider);
    await local.start(user);
    state = _snapshot(local);
  }

  Future<void> selectArea(String companyId, String areaId) async {
    final local = ref.read(localSessionProvider);
    await local.selectArea(companyId: companyId, areaId: areaId);
    state = _snapshot(local);
  }

  Future<void> logout() async {
    final local = ref.read(localSessionProvider);
    await local.logout();
    state = _snapshot(local);
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);
