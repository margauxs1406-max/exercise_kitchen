import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rekovery_request_model.dart';
import '../services/rekovery_repository.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import 'picker_tile.dart';

/// Coach : actions disponibles sur une demande Rekovery, selon son statut
/// actuel (voir `RekoveryRequestModel`) :
/// - [pending] : "Accepter", "Proposer un autre créneau" ou "Refuser".
/// - [proposed] : "Refuser" uniquement — la contre-proposition est déjà
///   envoyée, la suite dépend de la réponse de l'adhérent (voir
///   `rekovery_request_actions_sheet.dart`).
/// - [accepted] : "Annuler cette réservation" (recrédite le carnet de
///   l'adhérent si "Rekovery seul").
/// - [refused]/[cancelled] : appelant ne doit pas ouvrir ce menu pour ces
///   statuts (voir `coach_rekovery_screen.dart`).
Future<void> showCoachRekoveryActionsSheet(
  BuildContext context,
  RekoveryRequestModel request,
) async {
  final repo = context.read<RekoveryRepository>();

  switch (request.status) {
    case RekoveryRequestStatus.pending:
      final action = await showModalBottomSheet<_CoachAction>(
        context: context,
        backgroundColor: AppColors.white,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.check, color: AppColors.flashyGreen),
                title: const Text('Accepter'),
                onTap: () => Navigator.of(context).pop(_CoachAction.accept),
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz, color: AppColors.black),
                title: const Text('Proposer un autre créneau'),
                onTap: () => Navigator.of(context).pop(_CoachAction.propose),
              ),
              ListTile(
                leading: const Icon(Icons.close, color: AppColors.orange),
                title: const Text('Refuser', style: TextStyle(color: AppColors.orange)),
                onTap: () => Navigator.of(context).pop(_CoachAction.refuse),
              ),
            ],
          ),
        ),
      );
      if (action == null || !context.mounted) return;
      switch (action) {
        case _CoachAction.accept:
          await _runWithErrorHandling(context, () => repo.acceptRequest(request.id));
          break;
        case _CoachAction.propose:
          await showDialog<void>(
            context: context,
            builder: (_) => _ProposeAlternativeDialog(request: request),
          );
          break;
        case _CoachAction.refuse:
          await _promptNoteAndRun(
            context,
            title: 'Refuser cette demande ?',
            confirmLabel: 'Refuser',
            action: (note) => repo.refuseRequest(request.id, note: note),
          );
          break;
      }
      break;

    case RekoveryRequestStatus.proposed:
      await _promptNoteAndRun(
        context,
        title: 'Refuser cette demande ?',
        confirmLabel: 'Refuser',
        action: (note) => repo.refuseRequest(request.id, note: note),
      );
      break;

    case RekoveryRequestStatus.accepted:
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.white,
          surfaceTintColor: Colors.transparent,
          title: const Text('ANNULER CETTE RÉSERVATION ?'),
          content: Text(
            '${request.adherentName} sera prévenu.e. Si son carnet est limité, '
            'la séance lui sera recréditée.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Retour')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Annuler la réservation'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await _runWithErrorHandling(context, () => repo.cancelRequest(request.id));
      break;

    case RekoveryRequestStatus.refused:
    case RekoveryRequestStatus.cancelled:
      // Rien à faire — voir la doc ci-dessus.
      break;
  }
}

enum _CoachAction { accept, propose, refuse }

Future<void> _promptNoteAndRun(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required Future<void> Function(String? note) action,
}) async {
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(title.toUpperCase()),
      content: TextField(
        controller: controller,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Motif (facultatif, visible par l\'adhérent)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Retour')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  // La valeur doit être lue AVANT `dispose()` : un `TextEditingController`
  // ne peut plus être consulté une fois disposé (exception en mode debug).
  final note = controller.text.trim();
  controller.dispose();
  if (confirmed != true || !context.mounted) return;
  await _runWithErrorHandling(context, () => action(note.isEmpty ? null : note));
}

Future<void> _runWithErrorHandling(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Une erreur est survenue : $e')));
  }
}

/// Pop-up de contre-proposition (date/heure uniquement — pas de champ de
/// message au coach, retiré le 6 août 2026) — mêmes composants
/// (`PickerTile`, mise en page) que `_EditSlotDialog` dans
/// `slot_actions_sheet.dart`, pour un rendu cohérent avec le reste de l'app.
class _ProposeAlternativeDialog extends StatefulWidget {
  final RekoveryRequestModel request;
  const _ProposeAlternativeDialog({required this.request});

  @override
  State<_ProposeAlternativeDialog> createState() => _ProposeAlternativeDialogState();
}

class _ProposeAlternativeDialogState extends State<_ProposeAlternativeDialog> {
  late DateTime _date = widget.request.date;
  late TimeOfDay _time = _parseTime(widget.request.startTime);
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

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await context.read<RekoveryRepository>().proposeAlternative(
            widget.request.id,
            proposedDate: _date,
            proposedStartTime: _fmtTime(_time),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur lors de l\'envoi : $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: const Text('PROPOSER UN AUTRE CRÉNEAU'),
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
            PickerTile(
              icon: Icons.access_time,
              label: _fmtTime(_time),
              valueSet: true,
              onTap: _pickTime,
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
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? SizedBox(
                  height: context.hp(18),
                  width: context.wp(18),
                  child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Envoyer'),
        ),
      ],
    );
  }
}
