import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rekovery_closure_model.dart';
import '../services/rekovery_repository.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/adaptive_pickers.dart';
import 'field_label.dart';
import 'picker_tile.dart';

/// Coach : appui long sur une carte "jour fermé" Rekovery (voir
/// `rekovery_closed_day_card.dart`, écrans `coach_rekovery_screen.dart` ET
/// `manage_planning_screen.dart` — n'importe où la carte peut apparaître,
/// 21 août 2026, demande de Margaux) — ouvre un menu d'actions "Modifier"
/// et "Supprimer", sur le même principe que `closure_actions_sheet.dart`
/// pour les fermetures de salle (remplace l'ancienne version qui ne
/// proposait QUE la suppression).
Future<void> showRekoveryClosureActionsSheet(
  BuildContext context,
  RekoveryClosureModel closure,
) async {
  final action = await showModalBottomSheet<_RekoveryClosureAction>(
    context: context,
    backgroundColor: AppColors.white,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit, color: AppColors.black),
            title: const Text('Modifier'),
            onTap: () => Navigator.of(context).pop(_RekoveryClosureAction.edit),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.orange),
            title: const Text('Supprimer', style: TextStyle(color: AppColors.orange)),
            onTap: () => Navigator.of(context).pop(_RekoveryClosureAction.delete),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;

  switch (action) {
    case _RekoveryClosureAction.edit:
      await showDialog<void>(
        context: context,
        builder: (_) => _EditRekoveryClosureDialog(closure: closure),
      );
      break;
    case _RekoveryClosureAction.delete:
      await _confirmAndDelete(context, closure);
      break;
  }
}

enum _RekoveryClosureAction { edit, delete }

Future<void> _confirmAndDelete(BuildContext context, RekoveryClosureModel closure) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: Text('Supprimer ?'.toUpperCase()),
      content: Text('« ${closure.title} » sera définitivement supprimée.'),
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
    await context.read<RekoveryRepository>().deleteClosure(closure.id);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Erreur lors de la suppression : $e')));
  }
}

/// Pop-up de modification d'une fermeture Rekovery déjà créée — la forme
/// (temporaire/prolongée, voir `RekoveryClosureModel.isTemporary`) reste
/// fixe (voir doc de `RekoveryRepository.updateClosure`) : seuls le
/// créneau, le titre et le message sont modifiables. Reprend les mêmes
/// champs que `add_rekovery_closure_screen.dart`, pour un rendu identique.
class _EditRekoveryClosureDialog extends StatefulWidget {
  final RekoveryClosureModel closure;
  const _EditRekoveryClosureDialog({required this.closure});

  @override
  State<_EditRekoveryClosureDialog> createState() => _EditRekoveryClosureDialogState();
}

class _EditRekoveryClosureDialogState extends State<_EditRekoveryClosureDialog> {
  late DateTime _date = widget.closure.startDate;
  late TimeOfDay _startTime = _parseTime(widget.closure.startTime) ?? const TimeOfDay(hour: 8, minute: 0);
  late TimeOfDay _endTime = _parseTime(widget.closure.endTime) ?? const TimeOfDay(hour: 12, minute: 0);

  late DateTime _rangeStart = widget.closure.startDate;
  late DateTime _rangeEnd = widget.closure.endDate;

  late final _titleController = TextEditingController(text: widget.closure.title);
  late final _messageController = TextEditingController(text: widget.closure.message ?? '');
  bool _submitting = false;

  static TimeOfDay? _parseTime(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtDateRaw(DateTime d) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${pad2(d.day)}/${pad2(d.month)}/${d.year}';
  }

  String _fmtDate(DateTime d) => 'Le ${_fmtDateRaw(d)}';

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: now.add(const Duration(days: 180)),
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

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: _rangeStart.isBefore(today) ? today : _rangeStart,
        end: _rangeEnd.isBefore(_rangeStart) ? _rangeStart : _rangeEnd,
      ),
      firstDate: today,
      lastDate: now.add(const Duration(days: 180)),
      helpText: 'Période de fermeture Rekovery',
      saveText: 'OK',
    );
    if (picked == null) return;
    setState(() {
      _rangeStart = picked.start;
      _rangeEnd = picked.end;
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim().isEmpty
        ? 'Rekovery temporairement inaccessible'
        : _titleController.text.trim();
    final message = _messageController.text.trim().isEmpty ? null : _messageController.text.trim();

    if (widget.closure.isTemporary) {
      final startMinutes = _startTime.hour * 60 + _startTime.minute;
      final endMinutes = _endTime.hour * 60 + _endTime.minute;
      if (endMinutes <= startMinutes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("L'heure de fin doit être après l'heure de début.")),
        );
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      await context.read<RekoveryRepository>().updateClosure(
            closureId: widget.closure.id,
            isTemporary: widget.closure.isTemporary,
            startDate: widget.closure.isTemporary ? _date : _rangeStart,
            endDate: widget.closure.isTemporary ? _date : _rangeEnd,
            startTime: widget.closure.isTemporary ? _fmtTime(_startTime) : null,
            endTime: widget.closure.isTemporary ? _fmtTime(_endTime) : null,
            title: title,
            message: message,
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
      title: Text('Modifier'.toUpperCase()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.closure.isTemporary) ...[
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
                      // Alignée le 22 août 2026 (demande de Margaux) sur le
                      // rendu du workshop : "Début"/"Fin" sur la même ligne
                      // que l'heure, même style (orange gras).
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
            ] else
              PickerTile(
                icon: Icons.calendar_today,
                label: _rangeEnd.isAtSameMomentAs(_rangeStart)
                    ? _fmtDate(_rangeStart)
                    : 'Du ${_fmtDateRaw(_rangeStart)} au ${_fmtDateRaw(_rangeEnd)}',
                valueSet: true,
                onTap: _pickRange,
              ),
            SizedBox(height: context.hp(12)),
            const FieldLabel('Titre'),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(),
            ),
            SizedBox(height: context.hp(12)),
            const FieldLabel('Message aux adhérents (facultatif)'),
            TextFormField(
              controller: _messageController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Ex. : Maintenance du matériel, désolée pour la gêne occasionnée.',
              ),
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
