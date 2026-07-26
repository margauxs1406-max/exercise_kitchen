import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rekovery_session_model.dart';
import '../services/planning_repository.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import 'picker_tile.dart';

/// Section 2.4bis : appui sur sa propre ligne Rekovery (planning adhérent,
/// voir `weekly_planning_screen.dart`) — ouvre un menu d'actions "Modifier"
/// (date + heure) et "Supprimer", sur le même principe que
/// `slot_actions_sheet.dart` côté coach pour les cours duo/individuel.
Future<void> showRekoveryActionsSheet(
  BuildContext context,
  RekoverySessionModel session,
) async {
  final action = await showModalBottomSheet<_RekoveryAction>(
    context: context,
    backgroundColor: AppColors.white,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit, color: AppColors.black),
            title: const Text('Modifier la date/l\'heure'),
            onTap: () => Navigator.of(context).pop(_RekoveryAction.edit),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.orange),
            title: const Text(
              'Supprimer cette session',
              style: TextStyle(color: AppColors.orange),
            ),
            onTap: () => Navigator.of(context).pop(_RekoveryAction.delete),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;

  switch (action) {
    case _RekoveryAction.edit:
      await showDialog<void>(
        context: context,
        builder: (_) => _EditRekoveryDialog(session: session),
      );
      break;
    case _RekoveryAction.delete:
      await _confirmAndDelete(context, session);
      break;
  }
}

enum _RekoveryAction { edit, delete }

String _fmtDate(DateTime d) {
  String pad2(int n) => n.toString().padLeft(2, '0');
  return '${pad2(d.day)}/${pad2(d.month)}/${d.year}';
}

Future<void> _confirmAndDelete(BuildContext context, RekoverySessionModel session) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: Text('Supprimer ?'.toUpperCase()),
      content: Text(
        'Ton Rekovery du ${_fmtDate(session.date)} à ${session.startTime} sera '
        'annulé.',
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
    await context.read<PlanningRepository>().deleteRekoverySession(session.id);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Erreur lors de la suppression : $e')));
  }
}

/// Pop-up de modification, réutilisant [PickerTile] — le même composant que
/// pour l'ajout d'un cours duo côté coach et l'ajout d'un Rekovery côté
/// adhérent (`add_rekovery_dialog.dart`) — pour un rendu identique.
class _EditRekoveryDialog extends StatefulWidget {
  final RekoverySessionModel session;
  const _EditRekoveryDialog({required this.session});

  @override
  State<_EditRekoveryDialog> createState() => _EditRekoveryDialogState();
}

class _EditRekoveryDialogState extends State<_EditRekoveryDialog> {
  late DateTime _date = widget.session.date;
  late TimeOfDay _time = _parseTime(widget.session.startTime);
  bool _submitting = false;

  static TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtDateLabel(DateTime d) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return 'Le ${pad2(d.day)}/${pad2(d.month)}/${d.year}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // `initialDate` ne doit jamais être avant `firstDate` (voir le bug déjà
    // rencontré dans `add_course_screen.dart`/`slot_actions_sheet.dart`) :
    // une session déjà passée garde ici sa date d'origine comme point de
    // départ, mais on ne repropose jamais une date antérieure à aujourd'hui.
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    setState(() => _submitting = true);
    try {
      await context.read<PlanningRepository>().updateRekoverySession(
            sessionId: widget.session.id,
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
      title: Text('Modifier ta session Rekovery'.toUpperCase()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PickerTile(
            icon: Icons.calendar_today,
            label: _fmtDateLabel(_date),
            valueSet: true,
            onTap: _pickDate,
          ),
          SizedBox(height: context.hp(12)),
          PickerTile(
            icon: Icons.access_time,
            label: _fmtTime(_time),
            valueSet: true,
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