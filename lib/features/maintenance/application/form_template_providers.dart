import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/form_template_repository.dart';
import '../domain/form_template.dart';

final formTemplateRepositoryProvider = Provider<FormTemplateRepository>(
  (ref) => throw StateError('Falta inicializar el repositorio de plantillas.'),
);

final formTemplatesProvider = StreamProvider<List<FormTemplate>>(
  (ref) => ref.watch(formTemplateRepositoryProvider).watchTemplates(),
);

final formTemplateProvider = StreamProvider.family<FormTemplate?, String>(
  (ref, id) => ref.watch(formTemplateRepositoryProvider).watchTemplate(id),
);
