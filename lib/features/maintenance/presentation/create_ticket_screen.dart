import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/app_config.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/priority_badge.dart';
import '../../auth/application/auth_providers.dart';
import '../application/maintenance_providers.dart';
import '../domain/create_ticket_input.dart';
import '../domain/form_template.dart';
import '../domain/maintenance_asset.dart';
import '../domain/maintenance_category.dart';
import '../domain/maintenance_settings.dart';
import '../domain/priority_engine.dart';
import '../domain/ticket_enums.dart';
import 'widgets/dynamic_form_field_widget.dart';

class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _basicKey = GlobalKey<FormState>();
  final _impactKey = GlobalKey<FormState>();
  final _dynamicKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _impactController = TextEditingController();
  final _impactNotesController = TextEditingController();
  final _overrideReasonController = TextEditingController();
  final _picker = ImagePicker();

  var _step = 0;
  var _submitting = false;
  String? _categoryId;
  MaintenanceAsset? _asset;
  bool? _productionStopped;
  bool? _safetyRisk;
  TicketPriority? _selectedPriority;
  var _priorityManuallySelected = false;
  final Map<String, Object?> _dynamicAnswers = {};
  final List<XFile> _images = [];

  @override
  void initState() {
    super.initState();
    _recoverLostImages();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _impactController.dispose();
    _impactNotesController.dispose();
    _overrideReasonController.dispose();
    super.dispose();
  }

  PriorityRecommendation get _recommendation => PriorityEngine.suggest(
    productionStopped: _productionStopped == true,
    safetyRisk: _safetyRisk == true,
    criticalAsset: _asset?.critical == true,
    impactPercent: int.tryParse(_impactController.text),
    policy:
        ref.read(maintenanceSettingsProvider).value?.priorityPolicy ??
        PriorityPolicy.defaults,
  );

  int get _maxPhotos =>
      ref.read(maintenanceSettingsProvider).value?.maxPhotosPerTicket ??
      MaintenanceSettings.defaults.maxPhotosPerTicket;

  TicketPriority get _effectivePriority =>
      _selectedPriority ?? _recommendation.priority;

  Future<void> _recoverLostImages() async {
    final response = await _picker.retrieveLostData();
    if (!mounted || response.isEmpty || response.files == null) return;
    setState(() {
      final room = _maxPhotos - _images.length;
      _images.addAll(response.files!.take(room));
    });
  }

  bool _validateStep() {
    switch (_step) {
      case 0:
        return _basicKey.currentState?.validate() ?? false;
      case 1:
        final formValid = _impactKey.currentState?.validate() ?? false;
        if (_productionStopped == null || _safetyRisk == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Responda las dos preguntas de impacto.'),
            ),
          );
          return false;
        }
        return formValid;
      case 2:
        final settings = ref.read(maintenanceSettingsProvider);
        if (settings.isLoading || settings.hasError) {
          _showConfigurationPending('la política de prioridad');
          return false;
        }
        final lowersRecommendation =
            _effectivePriority.rank < _recommendation.priority.rank;
        if (lowersRecommendation &&
            _overrideReasonController.text.trim().length < 8) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Explique por qué selecciona una prioridad menor a la sugerida.',
              ),
            ),
          );
          return false;
        }
        return true;
      case 3:
        final template = ref.read(activeFormTemplateProvider);
        if (template.isLoading || template.hasError) {
          _showConfigurationPending('el formulario dinámico');
          return false;
        }
        return _dynamicKey.currentState?.validate() ?? true;
      case 4:
        if (_images.length > _maxPhotos) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Conserve como máximo $_maxPhotos fotografías.'),
            ),
          );
          return false;
        }
    }
    return true;
  }

  void _showConfigurationPending(String item) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Espere mientras se carga $item. Compruebe la conexión.'),
      ),
    );
  }

  void _continue() {
    if (!_validateStep()) return;
    if (_step < 4) {
      setState(() => _step += 1);
    } else {
      _submit();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_images.length >= _maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Se alcanzó el máximo de $_maxPhotos fotografías.'),
        ),
      );
      return;
    }
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 75,
      requestFullMetadata: false,
    );
    if (image != null && mounted) setState(() => _images.add(image));
  }

  Future<void> _chooseImageSource() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Tomar fotografía'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Seleccionar de la galería'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final repository = ref.read(maintenanceRepositoryProvider);
    final user = ref.read(currentUserProfileProvider).value;
    final templateState = ref.read(activeFormTemplateProvider);
    final settingsState = ref.read(maintenanceSettingsProvider);
    if (repository == null || user == null) return;
    if (templateState.isLoading ||
        templateState.hasError ||
        settingsState.isLoading ||
        settingsState.hasError) {
      _showConfigurationPending('la configuración de mantenimiento');
      return;
    }
    final template = templateState.value;
    if (template != null && !(_dynamicKey.currentState?.validate() ?? false)) {
      setState(() => _step = 3);
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await repository.createTicket(
        CreateTicketInput(
          title: _titleController.text,
          description: _descriptionController.text,
          sourceDepartmentId: user.isAdmin
              ? AppConfig.productionDepartmentId
              : user.departmentId,
          targetDepartmentId: AppConfig.maintenanceDepartmentId,
          location: _locationController.text,
          categoryId: _categoryId!,
          asset: _asset,
          productionStopped: _productionStopped!,
          safetyRisk: _safetyRisk!,
          impactPercent: int.tryParse(_impactController.text),
          impactNotes: _impactNotesController.text,
          suggested: _recommendation,
          priority: _effectivePriority,
          priorityOverrideReason: _overrideReasonController.text,
          templateId: template?.id,
          templateVersion: template?.version,
          dynamicAnswers: Map.unmodifiable(_dynamicAnswers),
        ),
      );

      var failedUploads = 0;
      final attachmentService = ref.read(attachmentServiceProvider);
      if (attachmentService != null) {
        for (final image in _images) {
          try {
            await attachmentService.uploadEvidence(
              ticketId: result.ticketId,
              uploaderUid: user.uid,
              image: image,
            );
          } catch (_) {
            failedUploads += 1;
          }
        }
      }

      if (mounted) {
        final suffix = failedUploads == 0
            ? ''
            : ' $failedUploads evidencia(s) no pudieron cargarse.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.humanCode} creado.$suffix')),
        );
        context.go('/maintenance/tickets/${result.ticketId}');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppException.from(error).message)),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(maintenanceAssetsProvider).value ?? const [];
    final categories =
        ref.watch(maintenanceCategoriesProvider).value ??
        MaintenanceCategory.fallback;
    final templateState = ref.watch(activeFormTemplateProvider);
    final template = templateState.value;
    ref.watch(maintenanceSettingsProvider);

    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        appBar: AppBar(title: const Text('Crear solicitud')),
        body: Stepper(
          currentStep: _step,
          onStepTapped: _submitting
              ? null
              : (step) {
                  if (step <= _step) setState(() => _step = step);
                },
          onStepContinue: _submitting ? null : _continue,
          onStepCancel: _submitting || _step == 0
              ? null
              : () => setState(() => _step -= 1),
          controlsBuilder: (context, details) => Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: details.onStepContinue,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _step == 4
                                ? Icons.send_rounded
                                : Icons.arrow_forward_rounded,
                          ),
                    label: Text(
                      _submitting
                          ? 'Guardando…'
                          : _step == 4
                          ? 'Crear ticket'
                          : 'Continuar',
                    ),
                  ),
                ),
                if (_step > 0) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Atrás'),
                  ),
                ],
              ],
            ),
          ),
          steps: [
            Step(
              title: const Text('Información básica'),
              subtitle: const Text('Qué ocurrió y dónde'),
              isActive: _step >= 0,
              state: _step > 0 ? StepState.complete : StepState.indexed,
              content: _basicSection(categories, assets),
            ),
            Step(
              title: const Text('Impacto'),
              subtitle: const Text('Producción y seguridad'),
              isActive: _step >= 1,
              state: _step > 1 ? StepState.complete : StepState.indexed,
              content: _impactSection(),
            ),
            Step(
              title: const Text('Prioridad'),
              subtitle: Text('Sugerida: ${_recommendation.priority.label}'),
              isActive: _step >= 2,
              state: _step > 2 ? StepState.complete : StepState.indexed,
              content: _prioritySection(),
            ),
            Step(
              title: const Text('Preguntas adicionales'),
              subtitle: Text(
                template == null
                    ? 'Sin plantilla adicional'
                    : '${template.fields.length} pregunta(s)',
              ),
              isActive: _step >= 3,
              state: _step > 3 ? StepState.complete : StepState.indexed,
              content: templateState.when(
                data: _dynamicSection,
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Card(
                  child: ListTile(
                    leading: Icon(Icons.cloud_off_outlined),
                    title: Text('No se pudo cargar el formulario'),
                    subtitle: Text(
                      'Compruebe la conexión e inténtelo de nuevo.',
                    ),
                  ),
                ),
              ),
            ),
            Step(
              title: const Text('Evidencias y revisión'),
              subtitle: Text('${_images.length}/$_maxPhotos fotografías'),
              isActive: _step >= 4,
              content: _reviewSection(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _basicSection(
    List<MaintenanceCategory> categories,
    List<MaintenanceAsset> assets,
  ) {
    return Form(
      key: _basicKey,
      child: Column(
        children: [
          TextFormField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Título breve *',
              hintText: 'Ej. Columbia 21 se detuvo',
            ),
            validator: (value) => (value?.trim().length ?? 0) < 5
                ? 'Describa brevemente la solicitud.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptionController,
            textCapitalization: TextCapitalization.sentences,
            minLines: 4,
            maxLines: 7,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Descripción detallada *',
              alignLabelWithHint: true,
            ),
            validator: (value) => (value?.trim().length ?? 0) < 10
                ? 'Incluya al menos 10 caracteres.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _locationController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Ubicación *',
              prefixIcon: Icon(Icons.location_on_outlined),
              hintText: 'Línea, zona o puesto',
            ),
            validator: (value) => (value?.trim().isEmpty ?? true)
                ? 'Indique la ubicación.'
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Categoría *'),
            items: categories
                .map(
                  (category) => DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _categoryId = value),
            validator: (value) =>
                value == null ? 'Seleccione una categoría.' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _asset?.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Equipo / activo relacionado',
              prefixIcon: Icon(Icons.precision_manufacturing_outlined),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('No aplica / sin equipo'),
              ),
              ...assets.map(
                (asset) => DropdownMenuItem<String?>(
                  value: asset.id,
                  child: Text(
                    '${asset.name}${asset.critical ? ' · CRÍTICO' : ''}',
                  ),
                ),
              ),
            ],
            onChanged: (id) => setState(() {
              _asset = id == null
                  ? null
                  : assets.where((asset) => asset.id == id).firstOrNull;
              if (!_priorityManuallySelected) {
                _selectedPriority = null;
              }
            }),
          ),
        ],
      ),
    );
  }

  Widget _impactSection() {
    return Form(
      key: _impactKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BinaryQuestion(
            icon: Icons.factory_outlined,
            title: '¿La falla tiene detenida la producción?',
            value: _productionStopped,
            onChanged: (value) => setState(() {
              _productionStopped = value;
              if (!_priorityManuallySelected) _selectedPriority = null;
            }),
          ),
          const SizedBox(height: 14),
          _BinaryQuestion(
            icon: Icons.health_and_safety_outlined,
            title: '¿Existe riesgo para personas o equipos?',
            value: _safetyRisk,
            onChanged: (value) => setState(() {
              _safetyRisk = value;
              if (!_priorityManuallySelected) _selectedPriority = null;
            }),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _impactController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Afectación aproximada (%)',
              suffixText: '%',
            ),
            onChanged: (_) => setState(() {
              if (!_priorityManuallySelected) _selectedPriority = null;
            }),
            validator: (value) {
              if (value?.trim().isEmpty ?? true) return null;
              final number = int.tryParse(value!);
              if (number == null || number < 0 || number > 100) {
                return 'Ingrese un valor entre 0 y 100.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _impactNotesController,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Observaciones del impacto',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _prioritySection() {
    final recommendation = _recommendation;
    final selected = _effectivePriority;
    final lowered = selected.rank < recommendation.priority.rank;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Prioridad recomendada',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                PriorityBadge(recommendation.priority),
                const SizedBox(height: 10),
                Text(
                  recommendation.factors.isEmpty
                      ? 'No se detectaron factores de impacto elevados.'
                      : recommendation.factors.join(' · '),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Criterio operativo configurable de la aplicación; no constituye una norma industrial.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<TicketPriority>(
          initialValue: selected,
          decoration: const InputDecoration(labelText: 'Prioridad final *'),
          items: TicketPriority.values
              .map(
                (priority) => DropdownMenuItem(
                  value: priority,
                  child: Text(priority.label),
                ),
              )
              .toList(growable: false),
          onChanged: (value) => setState(() {
            _selectedPriority = value;
            _priorityManuallySelected = true;
          }),
        ),
        if (lowered) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _overrideReasonController,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Motivo para reducir la prioridad *',
              prefixIcon: Icon(Icons.edit_note_rounded),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dynamicSection(FormTemplate? template) {
    if (template == null || template.fields.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.check_circle_outline_rounded),
          title: Text('No hay preguntas adicionales activas'),
          subtitle: Text(
            'La solicitud conservará todos los campos estructurados obligatorios.',
          ),
        ),
      );
    }
    return Form(
      key: _dynamicKey,
      child: Column(
        children: template.fields
            .map(
              (field) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DynamicFormFieldWidget(
                  field: field,
                  value: _dynamicAnswers[field.id],
                  onChanged: (value) => setState(() {
                    _dynamicAnswers[field.id] = value;
                  }),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Widget _reviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _images.length >= _maxPhotos ? null : _chooseImageSource,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text('Agregar evidencia (${_images.length}/$_maxPhotos)'),
        ),
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _images
                .asMap()
                .entries
                .map((entry) {
                  return InputChip(
                    avatar: const Icon(Icons.image_outlined, size: 18),
                    label: Text('Foto ${entry.key + 1}'),
                    onDeleted: () =>
                        setState(() => _images.removeAt(entry.key)),
                  );
                })
                .toList(growable: false),
          ),
        ],
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titleController.text,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                PriorityBadge(_effectivePriority),
                const SizedBox(height: 12),
                _ReviewRow(label: 'Ubicación', value: _locationController.text),
                _ReviewRow(label: 'Equipo', value: _asset?.name ?? 'No aplica'),
                _ReviewRow(
                  label: 'Producción detenida',
                  value: _productionStopped == true ? 'Sí' : 'No',
                ),
                _ReviewRow(
                  label: 'Riesgo de seguridad',
                  value: _safetyRisk == true ? 'Sí' : 'No',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BinaryQuestion extends StatelessWidget {
  const _BinaryQuestion({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Sí')),
                  ButtonSegment(value: false, label: Text('No')),
                ],
                selected: value == null ? const {} : {value!},
                emptySelectionAllowed: true,
                onSelectionChanged: (selection) {
                  final next = selection.firstOrNull;
                  if (next != null) onChanged(next);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
