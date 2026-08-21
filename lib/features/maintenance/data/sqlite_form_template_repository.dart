import 'dart:async';

import 'package:sqlite3/sqlite3.dart';

import '../../../core/database/database_service.dart';
import '../domain/form_template.dart';
import '../domain/ticket_enums.dart';
import '../domain/ticket_question.dart';
import 'form_template_repository.dart';

final class SqliteFormTemplateRepository implements FormTemplateRepository {
  SqliteFormTemplateRepository(this._service);

  final DatabaseService _service;
  final _changes = StreamController<void>.broadcast();
  Database get _db => _service.database;

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  @override
  Stream<List<FormTemplate>> watchTemplates() => _watch(_readTemplates);

  @override
  Stream<FormTemplate?> watchTemplate(String id) =>
      _watch(() => _readTemplate(id));

  @override
  Future<FormTemplate?> getTemplate(String id) async => _readTemplate(id);

  void _transaction(void Function() operation) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      operation();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> createTemplate(FormTemplate template) async {
    _validate(template);
    _transaction(() {
      _db.execute(
        'INSERT INTO form_templates(id, name, description, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [
          template.id,
          template.name.trim(),
          _nullable(template.description),
          template.createdAt.toUtc().toIso8601String(),
          template.updatedAt.toUtc().toIso8601String(),
        ],
      );
      _replaceQuestions(template);
    });
    _changes.add(null);
  }

  @override
  Future<void> updateTemplate(FormTemplate template) async {
    _validate(template);
    if (_readTemplate(template.id) == null) {
      throw StateError('La plantilla no existe.');
    }
    _transaction(() {
      _db.execute(
        'UPDATE form_templates SET name = ?, description = ?, updated_at = ? '
        'WHERE id = ?',
        [
          template.name.trim(),
          _nullable(template.description),
          template.updatedAt.toUtc().toIso8601String(),
          template.id,
        ],
      );
      _db.execute('DELETE FROM form_template_questions WHERE template_id = ?', [
        template.id,
      ]);
      _replaceQuestions(template);
    });
    _changes.add(null);
  }

  @override
  Future<void> deleteTemplate(String id) async {
    _db.execute('DELETE FROM form_templates WHERE id = ?', [id]);
    _changes.add(null);
  }

  void _replaceQuestions(FormTemplate template) {
    for (var index = 0; index < template.questions.length; index++) {
      final question = template.questions[index];
      _db.execute(
        'INSERT INTO form_template_questions '
        '(id, template_id, prompt, type, required, sort_order) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          question.id,
          template.id,
          question.prompt.trim(),
          question.type.name,
          question.required ? 1 : 0,
          index,
        ],
      );
      for (
        var optionIndex = 0;
        optionIndex < question.options.length;
        optionIndex++
      ) {
        _db.execute(
          'INSERT INTO form_template_question_options '
          '(question_id, value, sort_order) VALUES (?, ?, ?)',
          [question.id, question.options[optionIndex].trim(), optionIndex],
        );
      }
    }
  }

  List<FormTemplate> _readTemplates() => _db
      .select('SELECT * FROM form_templates ORDER BY name COLLATE NOCASE')
      .map(_fromRow)
      .toList();

  FormTemplate? _readTemplate(String id) {
    final rows = _db.select('SELECT * FROM form_templates WHERE id = ?', [id]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  FormTemplate _fromRow(Row row) {
    final id = row['id'] as String;
    final questions = _db
        .select(
          'SELECT * FROM form_template_questions WHERE template_id = ? '
          'ORDER BY sort_order',
          [id],
        )
        .map((questionRow) {
          final questionId = questionRow['id'] as String;
          return TicketQuestion(
            id: questionId,
            prompt: questionRow['prompt'] as String,
            type: QuestionType.fromValue(questionRow['type']),
            required: questionRow['required'] == 1,
            order: questionRow['sort_order'] as int,
            options: _db
                .select(
                  'SELECT value FROM form_template_question_options '
                  'WHERE question_id = ? ORDER BY sort_order',
                  [questionId],
                )
                .map((option) => option['value'] as String)
                .toList(),
          );
        })
        .toList();
    return FormTemplate(
      id: id,
      name: row['name'] as String,
      description: row['description'] as String?,
      questions: questions,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
    );
  }

  void _validate(FormTemplate template) {
    final errors = template.validate();
    if (errors.isNotEmpty) throw ArgumentError(errors.join('\n'));
  }

  String? _nullable(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}
