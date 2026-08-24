import 'dart:async';

import 'package:sqlite3/sqlite3.dart';

import '../../../core/database/database_service.dart';
import '../../organization/domain/organization_models.dart';
import '../domain/form_template.dart';
import '../domain/ticket_enums.dart';
import '../domain/ticket_question.dart';
import 'form_template_repository.dart';

final class SqliteFormTemplateRepository implements FormTemplateRepository {
  SqliteFormTemplateRepository(
    this._service, {
    AccessContext? Function()? context,
  }) : _context = context ?? (() => AccessContext.legacy);

  final DatabaseService _service;
  final AccessContext? Function() _context;
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
        'INSERT INTO form_templates(id, name, description, created_at, updated_at, company_id, area_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          template.id,
          template.name.trim(),
          _nullable(template.description),
          template.createdAt.toUtc().toIso8601String(),
          template.updatedAt.toUtc().toIso8601String(),
          template.companyId,
          template.areaId,
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
        'WHERE id = ? AND company_id = ? AND (area_id = ? OR area_id IS NULL)',
        [
          template.name.trim(),
          _nullable(template.description),
          template.updatedAt.toUtc().toIso8601String(),
          template.id,
          template.companyId,
          template.areaId,
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
    final scope = _requireScope();
    if (!scope.isSuperAdmin) {
      throw StateError('Solo el superadministrador administra plantillas.');
    }
    _db.execute(
      'DELETE FROM form_templates WHERE id = ? AND company_id = ? AND (area_id = ? OR area_id IS NULL)',
      [id, scope.companyId, scope.areaId],
    );
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

  List<FormTemplate> _readTemplates() {
    final scope = _requireScope();
    return _db
        .select(
          'SELECT * FROM form_templates WHERE company_id = ? AND (area_id = ? OR area_id IS NULL) ORDER BY name COLLATE NOCASE',
          [scope.companyId, scope.areaId],
        )
        .map(_fromRow)
        .toList();
  }

  FormTemplate? _readTemplate(String id) {
    final scope = _requireScope();
    final rows = _db.select(
      'SELECT * FROM form_templates WHERE id = ? AND company_id = ? AND (area_id = ? OR area_id IS NULL)',
      [id, scope.companyId, scope.areaId],
    );
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
      companyId: row['company_id'] as String,
      areaId: row['area_id'] as String?,
      questions: questions,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
    );
  }

  void _validate(FormTemplate template) {
    final scope = _requireScope();
    if (!scope.isSuperAdmin) {
      throw StateError('Solo el superadministrador administra plantillas.');
    }
    if (template.companyId != scope.companyId ||
        (template.areaId != null && template.areaId != scope.areaId)) {
      throw StateError('La plantilla no pertenece al contexto seleccionado.');
    }
    final errors = template.validate();
    if (errors.isNotEmpty) throw ArgumentError(errors.join('\n'));
  }

  AccessContext _requireScope() {
    final scope = _context();
    if (scope == null || scope.companyId == null || scope.areaId == null) {
      throw StateError('Selecciona una empresa y un área.');
    }
    if (!scope.permits(scope.companyId!, scope.areaId!)) {
      throw StateError('No tienes acceso al contexto seleccionado.');
    }
    return scope;
  }

  String? _nullable(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  @override
  Future<void> close() => _changes.close();
}
