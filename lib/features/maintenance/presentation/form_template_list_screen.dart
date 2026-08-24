import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/form_template_providers.dart';
import '../domain/form_template.dart';

class FormTemplateListScreen extends ConsumerWidget {
  const FormTemplateListScreen({super.key});

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    FormTemplate template,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar plantilla'),
        content: Text(
          '¿Eliminar “${template.name}”? Los tickets existentes no cambiarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm-delete-template'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(formTemplateRepositoryProvider)
          .deleteTemplate(template.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No fue posible eliminar la plantilla.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Formularios prediseñados')),
    floatingActionButton: FloatingActionButton.extended(
      key: const Key('create-template'),
      onPressed: () => context.push('/form-templates/new'),
      icon: const Icon(Icons.add_rounded),
      label: const Text('Crear plantilla'),
    ),
    body: ref
        .watch(formTemplatesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'No fue posible cargar los formularios prediseñados.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    key: const Key('retry-template-list'),
                    onPressed: () => ref.invalidate(formTemplatesProvider),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
          data: (templates) => templates.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aún no hay formularios prediseñados.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: templates.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final template = templates[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.description_outlined),
                        ),
                        title: Text(
                          template.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          [
                            if (template.description?.isNotEmpty == true)
                              template.description!,
                            '${template.questions.length} pregunta${template.questions.length == 1 ? '' : 's'}',
                          ].join('\n'),
                        ),
                        isThreeLine: template.description?.isNotEmpty == true,
                        onTap: () =>
                            context.push('/form-templates/${template.id}/edit'),
                        trailing: IconButton(
                          key: ValueKey('delete-template-${template.id}'),
                          tooltip: 'Eliminar',
                          onPressed: () => _delete(context, ref, template),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    );
                  },
                ),
        ),
  );
}
