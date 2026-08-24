import '../domain/form_template.dart';

abstract interface class FormTemplateRepository {
  Stream<List<FormTemplate>> watchTemplates();
  Stream<FormTemplate?> watchTemplate(String id);
  Future<FormTemplate?> getTemplate(String id);
  Future<void> createTemplate(FormTemplate template);
  Future<void> updateTemplate(FormTemplate template);
  Future<void> deleteTemplate(String id);
  Future<void> close();
}
