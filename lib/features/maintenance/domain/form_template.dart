import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_value.dart';
import 'ticket_enums.dart';

class DynamicFormField {
  const DynamicFormField({
    required this.id,
    required this.type,
    required this.label,
    required this.required,
    required this.order,
    this.helpText,
    this.options = const [],
    this.minimum,
    this.maximum,
  });

  final String id;
  final DynamicFieldType type;
  final String label;
  final String? helpText;
  final bool required;
  final int order;
  final List<String> options;
  final num? minimum;
  final num? maximum;

  factory DynamicFormField.fromMap(Map<String, Object?> map) {
    final validation = objectMapFromFirestore(map['validation']);
    return DynamicFormField(
      id: (map['id'] as String?) ?? '',
      type: DynamicFieldType.fromValue(map['type']),
      label: (map['label'] as String?) ?? 'Pregunta',
      helpText: map['helpText'] as String?,
      required: map['required'] == true,
      order: (map['order'] as num?)?.toInt() ?? 0,
      options: stringListFromFirestore(map['options']),
      minimum: validation['minimum'] as num?,
      maximum: validation['maximum'] as num?,
    );
  }
}

class FormTemplate {
  const FormTemplate({
    required this.id,
    required this.moduleId,
    required this.version,
    required this.fields,
  });

  final String id;
  final String moduleId;
  final int version;
  final List<DynamicFormField> fields;

  factory FormTemplate.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final map = document.data() ?? const <String, dynamic>{};
    final rawFields = map['fields'] as Iterable? ?? const [];
    final fields =
        rawFields
            .map(objectMapFromFirestore)
            .map(DynamicFormField.fromMap)
            .where((field) => field.id.isNotEmpty)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    return FormTemplate(
      id: document.id,
      moduleId: (map['moduleId'] as String?) ?? 'maintenance',
      version: (map['version'] as num?)?.toInt() ?? 1,
      fields: List.unmodifiable(fields),
    );
  }
}
