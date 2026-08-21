import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/features/auth/domain/app_user.dart';
import 'package:gestion_interna/features/maintenance/domain/create_ticket_input.dart';
import 'package:gestion_interna/features/maintenance/domain/form_template.dart';
import 'package:gestion_interna/features/maintenance/domain/maintenance_asset.dart';
import 'package:gestion_interna/features/maintenance/domain/priority_engine.dart';
import 'package:gestion_interna/features/maintenance/domain/ticket_enums.dart';

void main() {
  test('AppUser interpreta rol y estado', () {
    final user = AppUser.fromMap('uid-1', {
      'name': 'Samuel',
      'email': 'samuel@example.com',
      'role': 'maintenance',
      'departmentId': 'maintenance',
      'active': true,
    });

    expect(user.uid, 'uid-1');
    expect(user.role, UserRole.maintenance);
    expect(user.active, isTrue);
  });

  test('DynamicFormField soporta selección múltiple', () {
    final field = DynamicFormField.fromMap({
      'id': 'symptoms',
      'type': 'multipleChoice',
      'label': 'Síntomas',
      'required': true,
      'options': ['Ruido', 'Vibración'],
      'order': 2,
    });

    expect(field.type, DynamicFieldType.multipleChoice);
    expect(field.options, ['Ruido', 'Vibración']);
    expect(field.required, isTrue);
  });

  test('CreateTicketInput conserva prioridad sugerida y final', () {
    const asset = MaintenanceAsset(
      id: 'columbia-21',
      name: 'Columbia 21',
      code: 'COL-21',
      departmentId: 'production',
      location: 'Línea 2',
      critical: true,
      active: true,
    );
    final suggested = PriorityEngine.suggest(
      productionStopped: true,
      safetyRisk: false,
      criticalAsset: true,
    );
    final input = CreateTicketInput(
      title: 'Falla Columbia 21',
      description: 'La máquina se detuvo durante la producción.',
      sourceDepartmentId: 'production',
      targetDepartmentId: 'maintenance',
      location: 'Línea 2',
      categoryId: 'production_equipment',
      asset: asset,
      productionStopped: true,
      safetyRisk: false,
      suggested: suggested,
      priority: TicketPriority.high,
      priorityOverrideReason: 'Hay línea de respaldo operativa.',
      dynamicAnswers: const {'noise': true},
    );

    final map = input.toCallableData(requestId: 'request-1');
    expect(map['assetId'], 'columbia-21');
    expect(map['suggestedPriority'], 'critical');
    expect(map['selectedPriority'], 'high');
    expect(map['requestId'], 'request-1');
  });
}
