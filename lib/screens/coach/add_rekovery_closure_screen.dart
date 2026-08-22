import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/rekovery_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../utils/adaptive_pickers.dart';
import '../../widgets/field_label.dart';
import '../../widgets/picker_tile.dart';

/// "AJOUTER AU REKOVERY" — bouton "+" de `coach_rekovery_screen.dart`
/// (21 août 2026, demande de Margaux ; titre raccourci le même jour, suite
/// à son retour). Reprend le pattern de design de
/// l'onglet "Ajouter un évènement" de `add_course_screen.dart` (même
/// `SegmentedButton` noir/blanc, mêmes `PickerTile`) — mais UN SEUL écran,
/// pas deux onglets : contrairement à "Ajouter au planning" (cours vs
/// évènement, deux flux totalement différents), les deux options ici
/// (Temporaire/Prolongée) sont juste deux variantes d'une seule et même
/// action (fermer l'espace Rekovery), donc un simple `SegmentedButton` en
/// tête d'un unique formulaire suffit.
///
/// - Temporaire : une seule journée + une plage horaire précise (heure de
///   début/fin) — ex. fermeture de 12h à 16h pour une opération de
///   maintenance.
/// - Prolongée : une période de plusieurs jours entiers, sans heure — ex.
///   fermeture du 10 au 24 août pour un changement de matériel.
///
/// Le titre par défaut ("Rekovery temporairement inaccessible") sert aussi
/// de titre à la notification envoyée aux adhérents formule Rekovery (voir
/// `functions/src/index.ts`, `onRekoveryClosureCreated`) — modifiable comme
/// le titre d'un workshop dans `add_course_screen.dart`.
class AddRekoveryClosureScreen extends StatefulWidget {
  const AddRekoveryClosureScreen({super.key});

  @override
  State<AddRekoveryClosureScreen> createState() => _AddRekoveryClosureScreenState();
}

final ButtonStyle _kSegmentedButtonStyle = SegmentedButton.styleFrom(
  backgroundColor: AppColors.white,
  foregroundColor: AppColors.black,
  selectedBackgroundColor: AppColors.black,
  selectedForegroundColor: AppColors.white,
  side: BorderSide(color: AppColors.mediumGrey.withValues(alpha: 0.35)),
);

class _AddRekoveryClosureScreenState extends State<AddRekoveryClosureScreen> {
  String _kind = 'temporaire'; // 'temporaire' | 'prolongee'

  final _titleController =
      TextEditingController(text: 'Rekovery temporairement inaccessible');
  // Message facultatif pour les adhérents (21 août 2026, demande de
  // Margaux) — même principe que le message d'une fermeture de salle.
  final _messageController = TextEditingController();

  // Temporaire : une seule date + heure de début/fin.
  DateTime? _date;
  // 8h-12h par défaut (21 août 2026, demande de Margaux) — même défaut que
  // l'heure d'un workshop (voir `add_course_screen.dart`), pour un rendu
  // identique dès l'ouverture de l'écran (texte orange gras via
  // `PickerTile`, voir plus bas) plutôt que "Choisir une heure" en gris.
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 12, minute: 0);

  // Prolongée : une période.
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtDateRaw(DateTime d) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${pad2(d.day)}/${pad2(d.month)}/${d.year}';
  }

  String _fmtDate(DateTime d) => 'Le ${_fmtDateRaw(d)}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: today,
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

  /// Une seule période de fermeture Rekovery — même composant
  /// (`showDateRangePicker`) que la période de fermeture de la salle, voir
  /// `add_course_screen.dart`/`_pickClosureRange`.
  Future<void> _pickRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialRange = _rangeStart != null
        ? DateTimeRange(start: _rangeStart!, end: _rangeEnd ?? _rangeStart!)
        : null;
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
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

  Future<void> _submit() async {
    final title = _titleController.text.trim().isEmpty
        ? 'Rekovery temporairement inaccessible'
        : _titleController.text.trim();

    if (_kind == 'temporaire') {
      if (_date == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Choisis une date.')));
        return;
      }
      final startMinutes = _startTime.hour * 60 + _startTime.minute;
      final endMinutes = _endTime.hour * 60 + _endTime.minute;
      if (endMinutes <= startMinutes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("L'heure de fin doit être après l'heure de début.")),
        );
        return;
      }
    } else {
      if (_rangeStart == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Choisis une période.')));
        return;
      }
    }

    final message = _messageController.text.trim().isEmpty ? null : _messageController.text.trim();

    setState(() => _submitting = true);
    try {
      final repo = context.read<RekoveryRepository>();
      if (_kind == 'temporaire') {
        await repo.addTemporaryClosure(
          date: _date!,
          startTime: _fmtTime(_startTime),
          endTime: _fmtTime(_endTime),
          title: title,
          message: message,
        );
      } else {
        await repo.addExtendedClosure(
          startDate: _rangeStart!,
          endDate: _rangeEnd ?? _rangeStart!,
          title: title,
          message: message,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Erreur lors de l'ajout : $e")));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text('Ajouter au Rekovery'.toUpperCase())),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                style: _kSegmentedButtonStyle,
                segments: const [
                  ButtonSegment(value: 'temporaire', label: Text('Temporaire')),
                  ButtonSegment(value: 'prolongee', label: Text('Prolongée')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              SizedBox(height: context.hp(20)),
              if (_kind == 'temporaire') ...[
                PickerTile(
                  icon: Icons.calendar_today,
                  label: _date == null ? 'Choisir une date' : _fmtDate(_date!),
                  valueSet: _date != null,
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
                        // que l'heure, même style (orange gras) — plus
                        // l'affichage empilé (stackedLabel), utilisé
                        // jusque-là uniquement ici.
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
              ] else ...[
                PickerTile(
                  icon: Icons.calendar_today,
                  label: _rangeStart == null
                      ? 'Choisir une période'
                      : (_rangeEnd == null || _rangeEnd!.isAtSameMomentAs(_rangeStart!)
                          ? _fmtDate(_rangeStart!)
                          : 'Du ${_fmtDateRaw(_rangeStart!)} au ${_fmtDateRaw(_rangeEnd!)}'),
                  valueSet: _rangeStart != null,
                  onTap: _pickRange,
                ),
              ],
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
              SizedBox(height: context.hp(24)),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? SizedBox(
                        height: context.hp(20),
                        width: context.wp(20),
                        child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Ajouter au planning'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
