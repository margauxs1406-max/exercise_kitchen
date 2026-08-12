import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/slot_model.dart';
import '../services/planning_repository.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/adaptive_pickers.dart';
import 'picker_tile.dart';

/// Section 1.3 : appui long sur une carte de cours duo, individuel ou
/// workshop (voir `manage_planning_screen.dart`) — ouvre un menu d'actions
/// "Modifier" et "Supprimer". Les cours collectifs (fixes, régénérés chaque
/// semaine) n'y sont pas branchés ; les fermetures ont leur propre menu (voir
/// `closure_actions_sheet.dart`).
///
/// "Modifier" ouvre une pop-up différente selon le type : [_EditSlotDialog]
/// (date + heure de début, durée fixe d'1h) pour un duo/individuel, ou
/// [_EditWorkshopDialog] (date, heure de début ET de fin, titre,
/// description) pour un workshop, qui a bien plus de champs propres.
Future<void> showSlotActionsSheet(BuildContext context, SlotModel slot) async {
  final action = await showModalBottomSheet<_SlotAction>(
    context: context,
    backgroundColor: AppColors.white,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit, color: AppColors.black),
            title: const Text('Modifier la date/l\'heure'),
            onTap: () => Navigator.of(context).pop(_SlotAction.edit),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.orange),
            title: const Text(
              'Supprimer ce cours',
              style: TextStyle(color: AppColors.orange),
            ),
            onTap: () => Navigator.of(context).pop(_SlotAction.delete),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;

  switch (action) {
    case _SlotAction.edit:
      await showDialog<void>(
        context: context,
        builder: (_) =>
            slot.type == 'workshop' ? _EditWorkshopDialog(slot: slot) : _EditSlotDialog(slot: slot),
      );
      break;
    case _SlotAction.delete:
      await _confirmAndDelete(context, slot);
      break;
  }
}

enum _SlotAction { edit, delete }

Future<void> _confirmAndDelete(BuildContext context, SlotModel slot) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(
        (slot.type == 'workshop' ? 'Supprimer ce workshop ?' : 'Supprimer ce cours ?')
            .toUpperCase(),
      ),
      content: Text(
        slot.registeredCount > 0
            ? '« ${slot.courseTitle} » (${slot.startTime}–${slot.endTime}) a '
                '${slot.registeredCount} inscrit(s) : il(s) ne verra/verront plus '
                'ce créneau une fois supprimé.'
            : 'Le cours « ${slot.courseTitle} » (${slot.startTime}–${slot.endTime}) '
                'sera définitivement supprimé du planning.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await context.read<PlanningRepository>().deleteSlot(slot.id);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Erreur lors de la suppression : $e')));
  }
}

/// Pop-up de modification de la date/heure d'un cours duo ou individuel déjà
/// créé. Pas de champ "heure de fin" : ces créneaux durent toujours 1h,
/// recalculée automatiquement (voir `PlanningRepository.updateSlotDateTime`).
class _EditSlotDialog extends StatefulWidget {
  final SlotModel slot;
  const _EditSlotDialog({required this.slot});

  @override
  State<_EditSlotDialog> createState() => _EditSlotDialogState();
}

class _EditSlotDialogState extends State<_EditSlotDialog> {
  late DateTime _date = widget.slot.date;
  late TimeOfDay _time = _parseTime(widget.slot.startTime);
  bool _submitting = false;

  static TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtDate(DateTime d) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${pad2(d.day)}/${pad2(d.month)}/${d.year}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // `initialDate` ne doit jamais être avant `firstDate` (voir le bug déjà
    // rencontré dans `add_course_screen.dart`) : un cours déjà passé garde
    // ici sa date d'origine comme point de départ, mais on ne repropose
    // jamais une date antérieure à aujourd'hui dans le calendrier.
    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showAdaptiveTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    setState(() => _submitting = true);
    try {
      await context.read<PlanningRepository>().updateSlotDateTime(
            slotId: widget.slot.id,
            date: _date,
            startTime: _fmtTime(_time),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur lors de la modification : $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: Text('Modifier « ${widget.slot.courseTitle} »'.toUpperCase()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today, color: AppColors.orange),
            title: Text(_fmtDate(_date)),
            onTap: _pickDate,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.access_time, color: AppColors.orange),
            title: Text(_fmtTime(_time)),
            onTap: _pickTime,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _save,
          child: _submitting
              ? SizedBox(
                  height: context.hp(18),
                  width: context.wp(18),
                  child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}

/// Pop-up de modification d'un workshop déjà créé : date, heure de début ET
/// de fin (indépendantes, contrairement à un duo/individuel), titre et
/// description — les mêmes champs que la création (voir
/// `add_course_screen.dart` > `_AddEventTab`), réutilisant [PickerTile] pour
/// un rendu identique.
class _EditWorkshopDialog extends StatefulWidget {
  final SlotModel slot;
  const _EditWorkshopDialog({required this.slot});

  @override
  State<_EditWorkshopDialog> createState() => _EditWorkshopDialogState();
}

class _EditWorkshopDialogState extends State<_EditWorkshopDialog> {
  late DateTime _date = widget.slot.date;
  late TimeOfDay _startTime = _parseTime(widget.slot.startTime);
  late TimeOfDay _endTime = _parseTime(widget.slot.endTime);
  late final _titleController = TextEditingController(text: widget.slot.courseTitle);
  late final _descriptionController = TextEditingController(text: widget.slot.description ?? '');
  bool _submitting = false;

  static TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtDate(DateTime d) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return 'Le ${pad2(d.day)}/${pad2(d.month)}/${d.year}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showAdaptiveTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _submitting = true);
    try {
      await context.read<PlanningRepository>().updateWorkshop(
            slotId: widget.slot.id,
            date: _date,
            startTime: _fmtTime(_startTime),
            endTime: _fmtTime(_endTime),
            title:
                _titleController.text.trim().isEmpty ? 'Workshop' : _titleController.text.trim(),
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur lors de la modification : $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: Text('Modifier le workshop'.toUpperCase()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PickerTile(
              icon: Icons.calendar_today,
              label: _fmtDate(_date),
              valueSet: true,
              onTap: _pickDate,
            ),
            SizedBox(height: context.hp(12)),
            Row(
              children: [
                Expanded(
                  child: PickerTile(
                    icon: Icons.access_time,
                    label: 'Début : ${_fmtTime(_startTime)}',
                    valueSet: true,
                    onTap: () => _pickTime(isStart: true),
                  ),
                ),
                SizedBox(width: context.wp(12)),
                Expanded(
                  child: PickerTile(
                    icon: Icons.access_time,
                    label: 'Fin : ${_fmtTime(_endTime)}',
                    valueSet: true,
                    onTap: () => _pickTime(isStart: false),
                  ),
                ),
              ],
            ),
            SizedBox(height: context.hp(12)),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Titre'),
            ),
            SizedBox(height: context.hp(12)),
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description (facultatif)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _save,
          child: _submitting
              ? SizedBox(
                  height: context.hp(18),
                  width: context.wp(18),
                  child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
