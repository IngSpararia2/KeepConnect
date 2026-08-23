import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/ticket_enums.dart';
import '../../domain/ticket_question.dart';

Future<TicketQuestion?> showQuestionEditor(
  BuildContext context, {
  TicketQuestion? initial,
}) => showDialog<TicketQuestion>(
  context: context,
  builder: (_) => QuestionEditorDialog(initial: initial),
);

class QuestionEditorDialog extends StatefulWidget {
  const QuestionEditorDialog({this.initial, super.key});
  final TicketQuestion? initial;

  @override
  State<QuestionEditorDialog> createState() => _QuestionEditorDialogState();
}

class _QuestionEditorDialogState extends State<QuestionEditorDialog> {
  late final _prompt = TextEditingController(text: widget.initial?.prompt);
  final _option = TextEditingController();
  late final _options = List<String>.of(widget.initial?.options ?? const []);
  late var _type = widget.initial?.type ?? QuestionType.freeText;
  late var _required = widget.initial?.required ?? false;
  String? _error;

  @override
  void dispose() {
    _prompt.dispose();
    _option.dispose();
    super.dispose();
  }

  void _addOption() {
    final value = _option.text.trim();
    if (value.isEmpty ||
        _options.any((item) => item.toLowerCase() == value.toLowerCase())) {
      setState(
        () => _error = value.isEmpty
            ? 'La opción no puede estar vacía.'
            : 'La opción ya existe.',
      );
      return;
    }
    setState(() {
      _options.add(value);
      _option.clear();
      _error = null;
    });
  }

  void _save() {
    final question = TicketQuestion(
      id: widget.initial?.id ?? const Uuid().v4(),
      prompt: _prompt.text.trim(),
      type: _type,
      required: _required,
      order: widget.initial?.order ?? 0,
      options: _type == QuestionType.freeText ? const [] : List.of(_options),
    );
    final error = question.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, question);
  }

  @override
  Widget build(BuildContext context) {
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).vertical;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        widget.initial == null ? 'Añadir pregunta' : 'Editar pregunta',
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: availableHeight * .58,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('question-prompt'),
                controller: _prompt,
                decoration: const InputDecoration(labelText: 'Enunciado'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<QuestionType>(
                key: const Key('question-type'),
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: QuestionType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _type = value ?? _type),
              ),
              SwitchListTile(
                key: const Key('question-required'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Respuesta obligatoria'),
                value: _required,
                onChanged: (value) => setState(() => _required = value),
              ),
              if (_type != QuestionType.freeText) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('question-option'),
                        controller: _option,
                        decoration: const InputDecoration(
                          labelText: 'Nueva opción',
                        ),
                        onSubmitted: (_) => _addOption(),
                      ),
                    ),
                    IconButton(
                      key: const Key('add-question-option'),
                      onPressed: _addOption,
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Añadir opción',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var index = 0; index < _options.length; index++)
                  ListTile(
                    dense: true,
                    title: Text(_options[index]),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _options.removeAt(index)),
                    ),
                  ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('save-question'),
          onPressed: _save,
          child: Text(widget.initial == null ? 'Añadir' : 'Guardar'),
        ),
      ],
    );
  }
}
