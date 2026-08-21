import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/features/maintenance/domain/priority_engine.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';

void main() {
  group('PriorityEngine', () {
    test('recomienda baja sin factores de impacto', () {
      final result = PriorityEngine.suggest(
        productionStopped: false,
        safetyRisk: false,
        criticalAsset: false,
      );

      expect(result.priority, TicketPriority.low);
      expect(result.score, 0);
      expect(result.factors, isEmpty);
    });

    test('riesgo de seguridad fuerza prioridad crítica', () {
      final result = PriorityEngine.suggest(
        productionStopped: false,
        safetyRisk: true,
        criticalAsset: false,
      );

      expect(result.priority, TicketPriority.critical);
      expect(result.score, 7);
    });

    test('producción detenida en activo crítico es crítica', () {
      final result = PriorityEngine.suggest(
        productionStopped: true,
        safetyRisk: false,
        criticalAsset: true,
        impactPercent: 10,
      );

      expect(result.priority, TicketPriority.critical);
      expect(result.factors, contains('Producción detenida'));
      expect(result.factors, contains('Activo marcado como crítico'));
    });

    test('considera límites de afectación', () {
      final medium = PriorityEngine.suggest(
        productionStopped: false,
        safetyRisk: false,
        criticalAsset: false,
        impactPercent: 25,
      );
      final higher = PriorityEngine.suggest(
        productionStopped: false,
        safetyRisk: false,
        criticalAsset: false,
        impactPercent: 75,
      );

      expect(medium.score, 1);
      expect(medium.priority, TicketPriority.low);
      expect(higher.score, 2);
      expect(higher.priority, TicketPriority.medium);
    });
  });
}
