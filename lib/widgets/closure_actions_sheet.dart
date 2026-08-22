import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/closure_model.dart';
import '../services/planning_repository.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/adaptive_pickers.dart';
import 'picker_tile.dart';

/// Appui long sur un bandeau de fermeture (planning coach, voir
/// `manage_planning_screen.dart`) — ouvre un menu d'actions "Modifier"
/// (période + message) et "Supprimer", sur le même principe que
/// `slot_actions_sheet.dart` pour les cours duo/individuel/workshop.
Future<void> showClosureActionsSheet(BuildContext context, ClosureModel closure) async {
  final action = await showModalBottomSheet<_ClosureAction>(
    context: context,
    backgroundColor: AppColors.white,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit, color: AppColors.black),
            title: const Text('Modifier'),
            onTap: () => Navigator.of(context).pop(_ClosureAction.edit),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.orange),
            title: const Text('Supprimer', style: TextStyle(color: AppColors.orange)),
            onTap: () => Navigator.of(context).pop(_ClosureAction.delete),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;

  switch (action) {
    case _ClosureAction.edit:
      await showDialog<void>(
        context: context,
        builder: (_) => _EditClosureDialog(closure: closure),
      );
      break;
    case _ClosureAction.delete:
      await _confirmAndDelete(context, closure);
      break;
  }
}

enum _ClosureAction { edit, delete }

Future<void> _confirmAndDelete(BuildContext context, ClosureModel closure) async {
  // Le message est facultatif depuis le 21 août 2026 (voir doc de
  // `_EditClosureDialog._save`) : on retombe sur "cette fermeture" plutôt
  // que d'afficher des guillemets vides s'il n'a pas été renseigné.
  final label = closure.message.trim().isEmpty ? 'cette fermeture' : '« ${closure.message} »';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: Text('Supprimer ?'.toUpperCase()),
      content: Text(
        closure.removedSlots.isEmpty
            ? 'La fermeture $label sera définitivement supprimée.'
            : 'La fermeture $label sera définitivement supprimée — '
                '${closure.removedSlots.length} cours annulé.s seront restaurés.',
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
    await context.read<PlanningRepository>().deleteClosure(closure.id);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Erreur lors de la suppression : $e')));
  }
}

/// Pop-up de modification d'une fermeture — période (date de début/fin, via
/// [PickerTile], même style que le reste de l'app) et message (texte libre,
/// plusieurs lignes).
///
/// Modifier la période ici déclenche la même réconciliation des créneaux
/// qu'à la création (voir `PlanningRepository.updateClosure`) : les
/// créneaux nouvellement couverts sont supprimés, et ceux qui sortent de la
/// période (si elle est réduite ou déplacée) sont recréés automatiquement.
class _EditClosureDialog extends StatefulWidget {
  final ClosureModel closure;
  const _EditClosureDialog({required this.closure});

  @override
  State<_EditClosureDialog> createState() => _EditClosureDialogState();
}

class _EditClosureDialogState extends State<_EditClosureDialog> {
  late DateTime _startDate = widget.closure.startDate;
  late DateTime _endDate = widget.closure.endDate;
  late final _messageController = TextEditingController(text: widget.closure.message);
  bool _submitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return 'Le ${pad2(d.day)}/${pad2(d.month)}/${d.year}';
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // `initialDate` ne doit jamais être avant `firstDate` : une fermeture
    // déjà passée garde sa date d'origine comme point de départ, mais on ne
    // repropose jamais une date antérieure à aujourd'hui.
    // Sélecteur adapté à la plateforme (22 août 2026 — cette pop-up
    // utilisait encore le calendrier Material brut, contrairement au reste
    // de l'app depuis le 7 août 2026).
    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: _startDate.isBefore(today) ? today : _startDate,
      firstDate: today,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      // La date de fin ne peut jamais être avant la date de début.
      if (_endDate.isBefore(picked)) _endDate = picked;
    });
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    // Message facultatif depuis le 21 août 2026 (demande de Margaux) — plus
    // aucune validation ici, contrairement à avant.
    setState(() => _submitting = true);
    try {
      await context.read<PlanningRepository>().updateClosure(
            closureId: widget.closure.id,
            startDate: _startDate,
            endDate: _endDate,
            message: _messageController.text.trim(),
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: PickerTile(
                  icon: Icons.calendar_today,
                  label: _fmtDate(_startDate),
                  valueSet: true,
                  stackedLabel: 'Début',
                  onTap: _pickStartDate,
                ),
              ),
              SizedBox(width: context.wp(12)),
              Expanded(
                child: PickerTile(
                  icon: Icons.calendar_today,
                  label: _fmtDate(_endDate),
                  valueSet: true,
                  stackedLabel: 'Fin',
                  onTap: _pickEndDate,
                ),
              ),
            ],
          ),
          SizedBox(height: context.hp(12)),
          TextFormField(
            controller: _messageController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Ex. : Salle fermée exceptionnellement, réouverture demain.',
            ),
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
