import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/closure_model.dart';
import '../models/rekovery_request_model.dart';
import '../services/planning_repository.dart';
import '../services/rekovery_repository.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/adaptive_pickers.dart';
import '../utils/week_utils.dart';
import 'picker_tile.dart';

/// Adhérent : actions disponibles sur SA PROPRE demande Rekovery, selon son
/// statut actuel (voir `RekoveryRequestModel`), déclenchées par un appui
/// long sur la carte (un simple tap ne fait plus rien depuis le 6 août
/// 2026, voir `adherent_rekovery_screen.dart`) :
/// - [pending] : "Modifier la demande" (nouvelle date/heure, reste
///   [pending]) ou "Annuler la demande".
/// - [proposed] : "Accepter la proposition" (confirme le créneau proposé
///   par le coach, décompte le carnet si "Rekovery seul") ou "Refuser" (qui
///   annule la demande d'office — pas de nouvelle contre-proposition
///   possible, voir `RekoveryRequestModel`). Pas d'option "Modifier" ici :
///   il faut d'abord répondre à la contre-proposition du coach.
/// - [accepted] : "Modifier ma réservation" (nouvelle date/heure, repasse en
///   [pending] — le coach doit de nouveau valider, et le carnet est
///   recrédité comme pour une annulation) ou "Annuler ma réservation"
///   (recrédite le carnet si "Rekovery seul").
/// - [refused]/[cancelled] : appelant ne doit pas ouvrir ce menu pour ces
///   statuts (voir `adherent_rekovery_screen.dart`, qui ne branche
///   [onLongPress] que pour les trois statuts ci-dessus).
Future<void> showRekoveryRequestActionsSheet(
  BuildContext context,
  RekoveryRequestModel request,
) async {
  final repo = context.read<RekoveryRepository>();

  switch (request.status) {
    case RekoveryRequestStatus.pending:
      final action = await _showModifyOrCancelSheet(context, cancelLabel: 'Annuler');
      if (action == null || !context.mounted) return;
      if (action == _MenuAction.modify) {
        await showDialog<void>(context: context, builder: (_) => _ModifyRequestDialog(request: request));
      } else {
        await _confirmAndRun(
          context,
          title: 'Annuler ?',
          message: 'Ta demande sera annulée.',
          confirmLabel: 'Annuler',
          action: () => repo.cancelRequest(request.id),
        );
      }
      break;

    case RekoveryRequestStatus.accepted:
      final action = await _showModifyOrCancelSheet(context, cancelLabel: 'Annuler');
      if (action == null || !context.mounted) return;
      if (action == _MenuAction.modify) {
        await showDialog<void>(context: context, builder: (_) => _ModifyRequestDialog(request: request));
      } else {
        await _confirmAndRun(
          context,
          title: 'Annuler ?',
          message: 'Ta séance sera annulée, et recréditée si ton carnet est limité.',
          confirmLabel: 'Annuler',
          action: () => repo.cancelRequest(request.id),
        );
      }
      break;

    case RekoveryRequestStatus.proposed:
      final choice = await showModalBottomSheet<_ProposalChoice>(
        context: context,
        backgroundColor: AppColors.white,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.check, color: AppColors.flashyGreen),
                title: const Text('Accepter'),
                onTap: () => Navigator.of(context).pop(_ProposalChoice.accept),
              ),
              ListTile(
                leading: const Icon(Icons.close, color: AppColors.orange),
                title: const Text('Refuser', style: TextStyle(color: AppColors.orange)),
                onTap: () => Navigator.of(context).pop(_ProposalChoice.refuse),
              ),
            ],
          ),
        ),
      );
      if (choice == null || !context.mounted) return;
      if (choice == _ProposalChoice.accept) {
        await _runWithErrorHandling(
          context,
          () => repo.respondToProposal(request.id, accept: true),
        );
      } else {
        await _confirmAndRun(
          context,
          title: 'Refuser ?',
          message: 'Ta demande sera annulée, sans nouvelle proposition possible.',
          confirmLabel: 'Refuser',
          dismissLabel: 'Annuler',
          action: () => repo.respondToProposal(request.id, accept: false),
        );
      }
      break;

    case RekoveryRequestStatus.refused:
    case RekoveryRequestStatus.cancelled:
      // Rien à faire — voir la doc ci-dessus.
      break;
  }
}

enum _ProposalChoice { accept, refuse }

enum _MenuAction { modify, cancel }

/// Menu à deux choix ("Modifier" / annuler, libellé personnalisé) ouvert par
/// un appui long sur une demande [pending] ou [accepted] — voir doc de
/// `showRekoveryRequestActionsSheet` ci-dessus.
Future<_MenuAction?> _showModifyOrCancelSheet(
  BuildContext context, {
  required String cancelLabel,
}) {
  return showModalBottomSheet<_MenuAction>(
    context: context,
    backgroundColor: AppColors.white,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit, color: AppColors.black),
            title: const Text('Modifier'),
            onTap: () => Navigator.of(context).pop(_MenuAction.modify),
          ),
          ListTile(
            leading: const Icon(Icons.close, color: AppColors.orange),
            title: Text(cancelLabel, style: const TextStyle(color: AppColors.orange)),
            onTap: () => Navigator.of(context).pop(_MenuAction.cancel),
          ),
        ],
      ),
    ),
  );
}

Future<void> _confirmAndRun(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  // "Retour" par défaut (les 2 pop-up "Annuler ?" ci-dessus, dont le bouton
  // de confirmation dit déjà "Annuler" — pas de collision possible avec
  // "Annuler" en fermeture, voir `audit_modales.md`) ; passé explicitement à
  // "Annuler" pour "Refuser ?", où le bouton de confirmation dit "Refuser",
  // sans ce risque.
  String dismissLabel = 'Retour',
  required Future<void> Function() action,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(title.toUpperCase()),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(dismissLabel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await _runWithErrorHandling(context, action);
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

/// Pop-up "Modifier la demande" — choix d'une nouvelle date/heure, mêmes
/// contraintes que la réservation initiale (`rekovery_reserve_bar.dart`) :
/// fenêtre glissante (semaine en cours toujours ouverte, semaine suivante à
/// partir du vendredi), fermetures de la salle bloquées, et plage horaire
/// 9h00–17h45. Une fois validée, la demande repasse à [pending] côté
/// serveur (voir `RekoveryRepository.modifyRequest`), quel que soit son
/// statut de départ.
class _ModifyRequestDialog extends StatefulWidget {
  final RekoveryRequestModel request;
  const _ModifyRequestDialog({required this.request});

  @override
  State<_ModifyRequestDialog> createState() => _ModifyRequestDialogState();
}

class _ModifyRequestDialogState extends State<_ModifyRequestDialog> {
  late DateTime _date = widget.request.date;
  late TimeOfDay _time = _parseTime(widget.request.startTime);
  bool _submitting = false;
  List<ClosureModel> _closures = const [];

  static const _kMinMinutesOfDay = 9 * 60;
  static const _kMaxMinutesOfDay = 17 * 60 + 45;

  static TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    context.read<PlanningRepository>().fetchAllClosures().then((closures) {
      if (mounted) setState(() => _closures = closures);
    });
  }

  DateTime get _lastSelectableDay {
    final today = _dayOf(DateTime.now());
    final currentWeekStart = _dayOf(mondayOf(DateTime.now()));
    final fridayOfCurrentWeek = currentWeekStart.add(const Duration(days: 4));
    final nextWeekUnlocked = !today.isBefore(fridayOfCurrentWeek);
    return currentWeekStart.add(Duration(days: nextWeekUnlocked ? 13 : 6));
  }

  bool _isClosed(DateTime day) {
    return _closures
        .any((c) => !day.isBefore(_dayOf(c.startDate)) && !day.isAfter(_dayOf(c.endDate)));
  }

  bool _isWithinAllowedWindow(TimeOfDay t) {
    final minutes = t.hour * 60 + t.minute;
    return minutes >= _kMinMinutesOfDay && minutes <= _kMaxMinutesOfDay;
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtDate(DateTime d) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${pad2(d.day)}/${pad2(d.month)}/${d.year}';
  }

  Future<void> _pickDate() async {
    final today = _dayOf(DateTime.now());
    final lastDay = _lastSelectableDay;
    final initial = _date.isBefore(today) || _date.isAfter(lastDay) ? today : _date;
    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: lastDay,
      selectableDayPredicate: (day) => !_isClosed(_dayOf(day)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showAdaptiveTimePicker(context: context, initialTime: _time);
    if (picked == null) return;
    if (!_isWithinAllowedWindow(picked)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Les réservations avant 9h et après 17h45 ne sont pas acceptées.'),
        ));
      }
      return;
    }
    setState(() => _time = picked);
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await context.read<RekoveryRepository>().modifyRequest(
            widget.request.id,
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
      title: const Text('MODIFIER'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Repasse en attente de validation.',
              style: TextStyle(color: AppColors.mediumGrey),
            ),
            SizedBox(height: context.hp(12)),
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
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
