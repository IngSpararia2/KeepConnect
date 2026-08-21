import 'ticket_enums.dart';

class PriorityRecommendation {
  const PriorityRecommendation({
    required this.priority,
    required this.score,
    required this.factors,
    this.policyVersion = 'demo-v1',
  });

  final TicketPriority priority;
  final int score;
  final List<String> factors;
  final String policyVersion;
}

class PriorityPolicy {
  const PriorityPolicy({
    required this.version,
    required this.productionStoppedWeight,
    required this.safetyRiskWeight,
    required this.criticalAssetWeight,
    required this.moderateImpactWeight,
    required this.severeImpactWeight,
    required this.moderateImpactFromPercentage,
    required this.severeImpactFromPercentage,
    required this.mediumThreshold,
    required this.highThreshold,
    required this.criticalThreshold,
    required this.safetyRiskMinimumPriority,
    required this.stoppedCriticalAssetMinimumPriority,
  });

  static const defaults = PriorityPolicy(
    version: 'demo-v1',
    productionStoppedWeight: 5,
    safetyRiskWeight: 7,
    criticalAssetWeight: 2,
    moderateImpactWeight: 1,
    severeImpactWeight: 2,
    moderateImpactFromPercentage: 25,
    severeImpactFromPercentage: 75,
    mediumThreshold: 2,
    highThreshold: 5,
    criticalThreshold: 7,
    safetyRiskMinimumPriority: TicketPriority.critical,
    stoppedCriticalAssetMinimumPriority: TicketPriority.critical,
  );

  final String version;
  final int productionStoppedWeight;
  final int safetyRiskWeight;
  final int criticalAssetWeight;
  final int moderateImpactWeight;
  final int severeImpactWeight;
  final int moderateImpactFromPercentage;
  final int severeImpactFromPercentage;
  final int mediumThreshold;
  final int highThreshold;
  final int criticalThreshold;
  final TicketPriority safetyRiskMinimumPriority;
  final TicketPriority stoppedCriticalAssetMinimumPriority;

  factory PriorityPolicy.fromMap(Map<String, Object?> map) {
    int number(String key, int fallback) =>
        (map[key] as num?)?.toInt() ?? fallback;
    final defaults = PriorityPolicy.defaults;
    return PriorityPolicy(
      version: (map['version'] as String?) ?? defaults.version,
      productionStoppedWeight: number(
        'productionStoppedWeight',
        defaults.productionStoppedWeight,
      ),
      safetyRiskWeight: number('safetyRiskWeight', defaults.safetyRiskWeight),
      criticalAssetWeight: number(
        'criticalAssetWeight',
        defaults.criticalAssetWeight,
      ),
      moderateImpactWeight: number(
        'moderateImpactWeight',
        defaults.moderateImpactWeight,
      ),
      severeImpactWeight: number(
        'severeImpactWeight',
        defaults.severeImpactWeight,
      ),
      moderateImpactFromPercentage: number(
        'moderateImpactFromPercentage',
        defaults.moderateImpactFromPercentage,
      ),
      severeImpactFromPercentage: number(
        'severeImpactFromPercentage',
        defaults.severeImpactFromPercentage,
      ),
      mediumThreshold: number('mediumThreshold', defaults.mediumThreshold),
      highThreshold: number('highThreshold', defaults.highThreshold),
      criticalThreshold: number(
        'criticalThreshold',
        defaults.criticalThreshold,
      ),
      safetyRiskMinimumPriority: TicketPriority.fromValue(
        map['safetyRiskMinimumPriority'],
      ),
      stoppedCriticalAssetMinimumPriority: TicketPriority.fromValue(
        map['stoppedCriticalAssetMinimumPriority'],
      ),
    );
  }
}

/// Criterios operativos configurables del MVP; no son una norma industrial.
abstract final class PriorityEngine {
  static PriorityRecommendation suggest({
    required bool productionStopped,
    required bool safetyRisk,
    required bool criticalAsset,
    int? impactPercent,
    PriorityPolicy policy = PriorityPolicy.defaults,
  }) {
    var score = 0;
    final factors = <String>[];

    if (safetyRisk) {
      score += policy.safetyRiskWeight;
      factors.add('Riesgo para personas o equipos');
    }
    if (productionStopped) {
      score += policy.productionStoppedWeight;
      factors.add('Producción detenida');
    }
    if (criticalAsset) {
      score += policy.criticalAssetWeight;
      factors.add('Activo marcado como crítico');
    }
    if ((impactPercent ?? 0) >= policy.severeImpactFromPercentage) {
      score += policy.severeImpactWeight;
      factors.add(
        'Afectación igual o superior al '
        '${policy.severeImpactFromPercentage} %',
      );
    } else if ((impactPercent ?? 0) >= policy.moderateImpactFromPercentage) {
      score += policy.moderateImpactWeight;
      factors.add(
        'Afectación igual o superior al '
        '${policy.moderateImpactFromPercentage} %',
      );
    }

    var priority = score >= policy.criticalThreshold
        ? TicketPriority.critical
        : score >= policy.highThreshold
        ? TicketPriority.high
        : score >= policy.mediumThreshold
        ? TicketPriority.medium
        : TicketPriority.low;
    if (safetyRisk && priority.rank < policy.safetyRiskMinimumPriority.rank) {
      priority = policy.safetyRiskMinimumPriority;
    }
    if (productionStopped &&
        criticalAsset &&
        priority.rank < policy.stoppedCriticalAssetMinimumPriority.rank) {
      priority = policy.stoppedCriticalAssetMinimumPriority;
    }

    return PriorityRecommendation(
      priority: priority,
      score: score,
      factors: List.unmodifiable(factors),
      policyVersion: policy.version,
    );
  }
}
