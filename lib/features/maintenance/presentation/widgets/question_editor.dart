import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/ticket_enums.dart';
import '../../domain/ticket_question.dart';

Future<TicketQuestion?> showQuestionEditor(BuildContext context) =>
    showDialog<TicketQuestion>(
      context: context,
      builder: (_) => const QuestionEditorDialog(),
    );

class QuestionEditorDialog extends StatefulWidget {
  const QuestionEditorDialog({super.key});
  @override
  State<QuestionEditorDialog> createState() => _QuestionEditorDialogState();
}

class _QuestionEditorDialogState extends State<QuestionEditorDialog> {
  final _prompt = TextEditingController();
  final _option = TextEditingController();
  final _options = <String>[];
  var _type = QuestionType.freeText;
  var _required = false;
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
      id: const Uuid().v4(),
      prompt: _prompt.text.trim(),
      type: _type,
      required: _required,
      order: 0,
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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Añadir pregunta'),
    content: SizedBox(
      width: 520,
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
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: QuestionType.values
                  .map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.label)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            SwitchListTile(
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
                      controller: _option,
                      decoration: const InputDecoration(
                        labelText: 'Nueva opción',
                      ),
                      onSubmitted: (_) => _addOption(),
                    ),
                  ),
                  IconButton(
                    onPressed: _addOption,
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Añadir opción',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _options.length; i++)
                ListTile(
                  dense: true,
                  title: Text(_options[i]),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _options.removeAt(i)),
                  ),
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        child: const Text('Añadir'),
      ),
    ],
  );
}
