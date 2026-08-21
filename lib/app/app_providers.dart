import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/notification_service.dart';
import '../core/session/local_session.dart';
import '../features/maintenance/data/maintenance_repository.dart';
import '../features/maintenance/domain/ticket_enums.dart';

final notificationServiceProvider = Provider<NotificationGateway>(
  (ref) => throw StateError('Falta inicializar notificaciones.'),
);
final maintenanceRepositoryProvider = Provider<MaintenanceRepository>(
  (ref) => throw StateError('Falta inicializar el repositorio.'),
);
final localSessionProvider = Provider<LocalSession>(
  (ref) => throw StateError('Falta inicializar la sesión.'),
);

class SessionState {
  const SessionState({
    required this.loggedIn,
    required this.accountRole,
    required this.effectiveRole,
  });
  final bool loggedIn;
  final AccountRole? accountRole;
  final AppRole effectiveRole;
  bool get isAdministrator => accountRole == AccountRole.administrator;
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => _snapshot(ref.read(localSessionProvider));

  SessionState _snapshot(LocalSession local) => SessionState(
    loggedIn: local.loggedIn,
    accountRole: local.accountRole,
    effectiveRole: local.effectiveRole,
  );

  Future<void> login(AccountRole role) async {
    final local = ref.read(localSessionProvider);
    await local.login(role);
    state = _snapshot(local);
  }

  Future<void> setEffectiveRole(AppRole role) async {
    final local = ref.read(localSessionProvider);
    await local.setEffectiveRole(role);
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
