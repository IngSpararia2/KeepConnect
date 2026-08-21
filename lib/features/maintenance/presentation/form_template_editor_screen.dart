import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../application/form_template_providers.dart';
import '../domain/form_template.dart';
import '../domain/ticket_question.dart';
import 'widgets/question_editor.dart';

class FormTemplateEditorScreen extends ConsumerStatefulWidget {
  const FormTemplateEditorScreen({this.templateId, super.key});
  final String? templateId;

  @override
  ConsumerState<FormTemplateEditorScreen> createState() =>
      _FormTemplateEditorScreenState();
}

class _FormTemplateEditorScreenState
    extends ConsumerState<FormTemplateEditorScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _questions = <TicketQuestion>[];
  DateTime? _createdAt;
  var _loading = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.templateId != null) {
      _loading = true;
      Future<void>.microtask(_load);
    }
  }

  Future<void> _load() async {
    final template = await ref
        .read(formTemplateRepositoryProvider)
        .getTemplate(widget.templateId!);
    if (!mounted) return;
    if (template == null) {
      context.pop();
      return;
    }
    setState(() {
      _name.text = template.name;
      _description.text = template.description ?? '';
      _questions.addAll(template.questions);
      _createdAt = template.createdAt;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _addQuestion() async {
    final question = await showQuestionEditor(context);
    if (question != null) setState(() => _questions.add(question));
  }

  Future<void> _editQuestion(int index) async {
    final edited = await showQuestionEditor(
      context,
      initial: _questions[index],
    );
    if (edited != null) setState(() => _questions[index] = edited);
  }

  Future<void> _save() async {
    final now = DateTime.now();
    final template = FormTemplate(
      id: widget.templateId ?? const Uuid().v4(),
      name: _name.text,
      description: _description.text,
      questions: [
        for (var index = 0; index < _questions.length; index++)
          TicketQuestion(
            id: _questions[index].id,
            prompt: _questions[index].prompt,
            type: _questions[index].type,
            required: _questions[index].required,
            order: index,
            options: _questions[index].options,
          ),
      ],
      createdAt: _createdAt ?? now,
      updatedAt: now,
    );
    final errors = template.validate();
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errors.join('\n'))));
      return;
    }
    setState(() => _saving = true);
    try {
      final repository = ref.read(formTemplateRepositoryProvider);
      if (widget.templateId == null) {
        await repository.createTemplate(template);
      } else {
        await repository.updateTemplate(template);
      }
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.templateId == null ? 'Nueva plantilla' : 'Editar plantilla',
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      key: const Key('template-name'),
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Nombre *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('template-description'),
                      controller: _description,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Descripción (opcional)',
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Preguntas',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const Key('template-add-question'),
                          onPressed: _addQuestion,
                          icon: const Icon(Icons.add),
                          label: const Text('Pregunta'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_questions.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('Añade al menos una pregunta.'),
                        ),
                      )
                    else
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _questions.length,
                        onReorderItem: (oldIndex, newIndex) => setState(() {
                          if (newIndex > oldIndex) newIndex--;
                          _questions.insert(
                            newIndex,
                            _questions.removeAt(oldIndex),
                          );
                        }),
                        itemBuilder: (_, index) {
                          final question = _questions[index];
                          return Card(
                            key: ValueKey(question.id),
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.drag_handle),
                              title: Text(question.prompt),
                              subtitle: Text(
                                '${question.type.label}${question.required ? ' · Obligatoria' : ''}',
                              ),
                              onTap: () => _editQuestion(index),
                              trailing: IconButton(
                                key: ValueKey(
                                  'delete-template-question-${question.id}',
                                ),
                                onPressed: () =>
                                    setState(() => _questions.removeAt(index)),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: const Key('save-template'),
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar plantilla'),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
