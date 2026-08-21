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
  const SessionState({required this.areaSelected, required this.role});
  final bool areaSelected;
  final AppRole role;
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    final local = ref.read(localSessionProvider);
    return SessionState(areaSelected: local.areaSelected, role: local.role);
  }

  Future<void> selectPlant() async {
    await ref.read(localSessionProvider).selectPlant();
    state = SessionState(areaSelected: true, role: state.role);
  }

  Future<void> setRole(AppRole role) async {
    await ref.read(localSessionProvider).setRole(role);
    state = SessionState(areaSelected: state.areaSelected, role: role);
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);
