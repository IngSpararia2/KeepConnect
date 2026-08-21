import 'package:flutter/material.dart';

import '../../domain/form_template.dart';
import '../../domain/ticket_enums.dart';

class DynamicFormFieldWidget extends StatelessWidget {
  const DynamicFormFieldWidget({
    required this.field,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final DynamicFormField field;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    return switch (field.type) {
      DynamicFieldType.shortText => _textField(maxLines: 1),
      DynamicFieldType.longText => _textField(maxLines: 4),
      DynamicFieldType.number => _numberField(),
      DynamicFieldType.yesNo => _yesNo(),
      DynamicFieldType.singleChoice => _singleChoice(),
      DynamicFieldType.multipleChoice ||
      DynamicFieldType.checklist => _multipleChoice(),
      DynamicFieldType.date => _dateField(context),
      DynamicFieldType.photo => _photoHint(context),
    };
  }

  Widget _textField({required int maxLines}) {
    final maximumLength = field.type == DynamicFieldType.shortText
        ? 2000
        : 10000;
    return TextFormField(
      key: ValueKey(field.id),
      initialValue: value as String?,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: _label,
        helperText: field.helpText,
        alignLabelWithHint: maxLines > 1,
      ),
      onChanged: onChanged,
      validator: (input) {
        if (field.required && (input?.trim().isEmpty ?? true)) {
          return 'Este campo es obligatorio.';
        }
        if ((input?.length ?? 0) > maximumLength) {
          return 'Use máximo $maximumLength caracteres.';
        }
        return null;
      },
    );
  }

  Widget _numberField() {
    return TextFormField(
      key: ValueKey(field.id),
      initialValue: value?.toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: _label,
        helperText: field.helpText,
      ),
      onChanged: (input) => onChanged(num.tryParse(input)),
      validator: (input) {
        if (field.required && (input?.trim().isEmpty ?? true)) {
          return 'Este campo es obligatorio.';
        }
        final number = num.tryParse(input ?? '');
        if ((input?.isNotEmpty ?? false) && number == null) {
          return 'Ingrese un número válido.';
        }
        if (number != null &&
            field.minimum != null &&
            number < field.minimum!) {
          return 'El mínimo permitido es ${field.minimum}.';
        }
        if (number != null &&
            field.maximum != null &&
            number > field.maximum!) {
          return 'El máximo permitido es ${field.maximum}.';
        }
        return null;
      },
    );
  }

  Widget _yesNo() {
    final selected = value is bool ? <bool>{value! as bool} : <bool>{};
    return FormField<bool>(
      initialValue: value as bool?,
      validator: (input) =>
          field.required && input == null ? 'Seleccione Sí o No.' : null,
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (field.helpText != null) Text(field.helpText!),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Sí')),
              ButtonSegment(value: false, label: Text('No')),
            ],
            selected: selected,
            emptySelectionAllowed: true,
            onSelectionChanged: (selection) {
              final next = selection.firstOrNull;
              state.didChange(next);
              onChanged(next);
            },
          ),
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                state.errorText!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _singleChoice() {
    return DropdownButtonFormField<String>(
      initialValue: value as String?,
      decoration: InputDecoration(
        labelText: _label,
        helperText: field.helpText,
      ),
      items: field.options
          .map((option) => DropdownMenuItem(value: option, child: Text(option)))
          .toList(growable: false),
      onChanged: onChanged,
      validator: (input) =>
          field.required && input == null ? 'Seleccione una opción.' : null,
    );
  }

  Widget _multipleChoice() {
    final currentValue = value;
    final selected = currentValue is Iterable
        ? currentValue.whereType<String>().toSet()
        : <String>{};
    return FormField<Set<String>>(
      initialValue: selected,
      validator: (input) => field.required && (input?.isEmpty ?? true)
          ? 'Seleccione al menos una opción.'
          : null,
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (field.helpText != null) Text(field.helpText!),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: field.options
                .map((option) {
                  final checked = selected.contains(option);
                  return FilterChip(
                    label: Text(option),
                    selected: checked,
                    avatar: field.type == DynamicFieldType.checklist
                        ? Icon(
                            checked
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            size: 18,
                          )
                        : null,
                    onSelected: (enabled) {
                      final next = <String>{...selected};
                      enabled ? next.add(option) : next.remove(option);
                      state.didChange(next);
                      onChanged(next.toList(growable: false));
                    },
                  );
                })
                .toList(growable: false),
          ),
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                state.errorText!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateField(BuildContext context) {
    final date = switch (value) {
      final DateTime parsed => parsed,
      final String encoded => DateTime.tryParse(encoded),
      _ => null,
    };
    return FormField<DateTime>(
      initialValue: date,
      validator: (input) =>
          field.required && input == null ? 'Seleccione una fecha.' : null,
      builder: (state) {
        final selectedDate = state.value;
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final selected = await showDatePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 3650)),
              initialDate: selectedDate ?? DateTime.now(),
            );
            if (selected != null) {
              state.didChange(selected);
              onChanged(selected.toUtc().toIso8601String());
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: _label,
              helperText: field.helpText,
              errorText: state.errorText,
              prefixIcon: const Icon(Icons.calendar_today_outlined),
            ),
            child: Text(
              selectedDate == null
                  ? 'Seleccionar fecha'
                  : '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}',
            ),
          ),
        );
      },
    );
  }

  Widget _photoHint(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.add_a_photo_outlined),
        title: Text(_label),
        subtitle: const Text(
          'Agregue la fotografía en la sección Evidencias del siguiente paso.',
        ),
      ),
    );
  }

  String get _label => field.required ? '${field.label} *' : field.label;
}
