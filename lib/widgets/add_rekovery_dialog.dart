import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/closure_model.dart';
import '../services/planning_repository.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import 'picker_tile.dart';

/// Section 2.4bis : pop-up d'ajout d'une session Rekovery, ouverte depuis le
/// bouton flottant du planning adhérent (voir `weekly_planning_screen.dart`).
///
/// Les champs "Choisir la date"/"Choisir l'heure" reprennent exactement le
/// même style que ceux de l'ajout d'un cours duo côté coach
/// (`add_course_screen.dart`), via le [PickerTile] désormais partagé entre
/// les deux écrans.
///
/// La date est pré-remplie sur aujourd'hui (mais reste modifiable, pour
/// prévenir d'un Rekovery à venir plus tard) ; l'heure, elle, doit toujours
/// être choisie explicitement — comme pour un cours duo, où aucune heure
/// n'est proposée par défaut.
Future<void> showAddRekoveryDialog(
  BuildContext context, {
  required String adherentUid,
  required String adherentName,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AddRekoveryDialog(adherentUid: adherentUid, adherentName: adherentName),
  );
}

class _AddRekoveryDialog extends StatefulWidget {
  final String adherentUid;
  final String adherentName;

  const _AddRekoveryDialog({required this.adherentUid, required this.adherentName});

  @override
  State<_AddRekoveryDialog> createState() => _AddRekoveryDialogState();
}

class _AddRekoveryDialogState extends State<_AddRekoveryDialog> {
  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  late DateTime _selectedDate = _today();
  TimeOfDay? _selectedTime;
  bool _submitting = false;

  // Fermetures existantes (section "ajouter un évènement > fermeture") —
  // chargées une fois à l'ouverture pour empêcher de choisir un jour fermé.
  // Chargement asynchrone, potentiellement vide un court instant à
  // l'ouverture (lecture Firestore quasi instantanée en pratique) : ce n'est
  // qu'un filet de sécurité supplémentaire, [_submit] revérifie de toute
  // façon avant d'enregistrer.
  List<ClosureModel> _closures = const [];

  @override
  void initState() {
    super.initState();
    _loadClosures();
  }

  Future<void> _loadClosures() async {
    final closures = await context.read<PlanningRepository>().fetchAllClosures();
    if (mounted) setState(() => _closures = closures);
  }

  bool _isClosed(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return _closures.any((c) => !d.isBefore(c.startDate) && !d.isAfter(c.endDate));
  }

  String _fmtDate(DateTime d) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return 'Le ${pad2(d.day)}/${pad2(d.month)}/${d.year}';
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final today = _today();
    // `initialDate` reste la date déjà choisie (aujourd'hui par défaut), pas
    // `today` littéralement : si l'adhérent a déjà avancé la date une
    // première fois puis rouvre le sélecteur, il doit repartir de son choix
    // précédent plutôt que de revenir à aujourd'hui.
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      // Empêche de sélectionner un jour couvert par une fermeture.
      selectableDayPredicate: (day) => !_isClosed(day),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _submit() async {
    if (_isClosed(_selectedDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La salle est fermée ce jour-là — choisis une autre date.')),
      );
      return;
    }
    if (_selectedTime == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Choisis une heure.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await context.read<PlanningRepository>().addRekoverySession(
            date: _selectedDate,
            startTime: _fmtTime(_selectedTime!),
            adherentUid: widget.adherentUid,
            adherentName: widget.adherentName,
          );
      if (!mounted) return;
      final dateLabel = _fmtDate(_selectedDate);
      final timeLabel = _fmtTime(_selectedTime!);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Rekovery prévu $dateLabel à $timeLabel.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Une erreur est survenue : $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: Text('Rekovery'.toUpperCase()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PickerTile(
            icon: Icons.calendar_today,
            label: _fmtDate(_selectedDate),
            // Toujours vrai : une date est présente dès l'ouverture (celle
            // du jour), contrairement à l'heure qui doit être choisie.
            valueSet: true,
            onTap: _pickDate,
          ),
          SizedBox(height: context.hp(12)),
          PickerTile(
            icon: Icons.access_time,
            label: _selectedTime == null ? 'Choisir une heure' : _fmtTime(_selectedTime!),
            valueSet: _selectedTime != null,
            onTap: _pickTime,
          ),
          // Avertissement immédiat si le jour actuellement sélectionné (par
          // défaut aujourd'hui) est fermé — sans attendre l'appui sur
          // "Valider" pour l'apprendre.
          if (_isClosed(_selectedDate)) ...[
            SizedBox(height: context.hp(12)),
            const Text(
              'La salle est fermée ce jour-là — choisis une autre date.',
              style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submitting || _isClosed(_selectedDate) ? null : _submit,
          child: _submitting
              ? SizedBox(
                  height: context.hp(18),
                  width: context.wp(18),
                  child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Valider'),
        ),
      ],
    );
  }
}
