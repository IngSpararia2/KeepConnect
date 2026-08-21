import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/features/auth/domain/app_user.dart';
import 'package:gestion_interna/features/maintenance/domain/status_transition_policy.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';

void main() {
  group('StatusTransitionPolicy', () {
    test('mantenimiento puede reconocer un pendiente', () {
      expect(
        StatusTransitionPolicy.canTransition(
          from: TicketStatus.pending,
          to: TicketStatus.acknowledged,
          role: UserRole.maintenance,
          isRequester: false,
          isAssignee: false,
        ),
        isTrue,
      );
    });

    test('no permite saltar de pendiente a en proceso', () {
      expect(
        StatusTransitionPolicy.canTransition(
          from: TicketStatus.pending,
          to: TicketStatus.inProgress,
          role: UserRole.admin,
          isRequester: false,
          isAssignee: false,
        ),
        isFalse,
      );
    });

    test('solo solicitante de producción confirma el cierre', () {
      bool canClose(UserRole role, bool requester) =>
          StatusTransitionPolicy.canTransition(
            from: TicketStatus.resolved,
            to: TicketStatus.closed,
            role: role,
            isRequester: requester,
            isAssignee: false,
          );

      expect(canClose(UserRole.production, true), isTrue);
      expect(canClose(UserRole.production, false), isFalse);
      expect(canClose(UserRole.maintenance, false), isFalse);
    });

    test('un cerrado es terminal incluso para administrador', () {
      expect(
        StatusTransitionPolicy.allowedTargets(
          from: TicketStatus.closed,
          role: UserRole.admin,
          isRequester: true,
          isAssignee: true,
        ),
        isEmpty,
      );
    });

    test('solo responsable continúa estados de ejecución', () {
      bool canResolve(bool assignee) => StatusTransitionPolicy.canTransition(
        from: TicketStatus.inProgress,
        to: TicketStatus.resolved,
        role: UserRole.maintenance,
        isRequester: false,
        isAssignee: assignee,
      );

      expect(canResolve(true), isTrue);
      expect(canResolve(false), isFalse);
    });
  });
}
