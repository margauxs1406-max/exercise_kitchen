import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/closure_model.dart';
import '../models/rekovery_closure_model.dart';
import '../services/rekovery_repository.dart';
import '../theme/responsive.dart';
import '../utils/adaptive_pickers.dart';
import '../utils/week_utils.dart';
import 'picker_tile.dart';

/// Bandeau de réservation d'un nouveau créneau Rekovery, affiché en haut de
/// l'écran adhérent (`adherent_rekovery_screen.dart`) — remplace l'ancienne
/// pop-up dédiée (`add_rekovery_dialog.dart`, supprimée) : la demande fait
/// maintenant partie d'un vrai flux avec réponse du coach (voir
/// `rekovery_request_model.dart`), donc mieux de la garder visible en
/// permanence, juste au-dessus de la liste des demandes, plutôt que derrière
/// un bouton flottant.
///
/// Fenêtre de réservation glissante : IDENTIQUE à celle du planning des
/// cours (`weekly_planning_screen.dart`) — la semaine en cours est toujours
/// ouverte, la semaine suivante ne s'ouvre qu'à partir du vendredi de la
/// semaine en cours (3 jours d'avance). Réimplémentée ici plutôt qu'extraite
/// en fonction partagée, pour ne pas risquer de casser l'écran de planning
/// existant en modifiant un utilitaire commun à ce stade.
class RekoveryReserveBar extends StatefulWidget {
  final List<ClosureModel> closures;
  // Fermetures Rekovery (21 août 2026, distinctes des fermetures de salle
  // ci-dessus) — voir `_isClosed`/`_temporaryClosuresFor` pour comment
  // chaque forme (temporaire/prolongée) affecte le choix de date/heure.
  final List<RekoveryClosureModel> rekoveryClosures;
  const RekoveryReserveBar({
    super.key,
    this.closures = const [],
    this.rekoveryClosures = const [],
  });

  @override
  State<RekoveryReserveBar> createState() => _RekoveryReserveBarState();
}

class _RekoveryReserveBarState extends State<RekoveryReserveBar> {
  DateTime? _date;
  TimeOfDay? _time;
  bool _submitting = false;

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime get _lastSelectableDay {
    final today = _dayOf(DateTime.now());
    final currentWeekStart = _dayOf(mondayOf(DateTime.now()));
    final fridayOfCurrentWeek = currentWeekStart.add(const Duration(days: 4));
    final nextWeekUnlocked = !today.isBefore(fridayOfCurrentWeek);
    return currentWeekStart.add(Duration(days: nextWeekUnlocked ? 13 : 6));
  }

  /// Vrai si [day] est ENTIÈREMENT inaccessible pour Rekovery : soit la
  /// salle est fermée ce jour-là (`widget.closures`), soit une fermeture
  /// Rekovery "prolongée" (`isTemporary == false`) le couvre. Une fermeture
  /// Rekovery "temporaire" (juste une plage horaire) NE bloque PAS la
  /// journée entière ici — seule la plage horaire concernée est bloquée,
  /// voir [_temporaryClosuresFor] et la vérification faite dans [_pickTime]
  /// une fois la date choisie (21 août 2026, demande de Margaux : l'accès
  /// Rekovery doit s'aligner sur les fermetures de salle ET se mettre à
  /// jour dès qu'une fermeture Rekovery est ajoutée).
  bool _isClosed(DateTime day) {
    final d = _dayOf(day);
    final roomClosed = widget.closures
        .any((c) => !d.isBefore(_dayOf(c.startDate)) && !d.isAfter(_dayOf(c.endDate)));
    if (roomClosed) return true;
    return widget.rekoveryClosures.any((c) =>
        !c.isTemporary && !d.isBefore(_dayOf(c.startDate)) && !d.isAfter(_dayOf(c.endDate)));
  }

  /// Fermetures Rekovery "temporaires" couvrant précisément [day] — utilisé
  /// par [_pickTime] pour refuser une heure qui tombe dans leur plage.
  List<RekoveryClosureModel> _temporaryClosuresFor(DateTime day) {
    final d = _dayOf(day);
    return widget.rekoveryClosures
        .where((c) => c.isTemporary && _dayOf(c.startDate) == d)
        .toList();
  }

  static int _parseMinutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  Future<void> _pickDate() async {
    final today = _dayOf(DateTime.now());
    final lastDay = _lastSelectableDay;
    final initial = _date == null || _date!.isBefore(today) || _date!.isAfter(lastDay)
        ? today
        : _date!;
    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: lastDay,
      selectableDayPredicate: (day) => !_isClosed(_dayOf(day)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  // Créneau Rekovery accepté : 9h00 à 17h45 inclus (demande du 6 août
  // 2026). Ni `showTimePicker` (Material) ni `CupertinoDatePicker` ne
  // permettent de bloquer nativement une plage horaire, donc la validation
  // se fait après le choix — avec un message explicite plutôt qu'un refus
  // silencieux.
  static const _kMinMinutesOfDay = 9 * 60;
  static const _kMaxMinutesOfDay = 17 * 60 + 45;

  bool _isWithinAllowedWindow(TimeOfDay t) {
    final minutes = t.hour * 60 + t.minute;
    return minutes >= _kMinMinutesOfDay && minutes <= _kMaxMinutesOfDay;
  }

  Future<void> _pickTime() async {
    final picked =
        await showAdaptiveTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
    if (picked == null) return;
    if (!_isWithinAllowedWindow(picked)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Les réservations avant 9h et après 17h45 ne sont pas acceptées.'),
        ));
      }
      return;
    }
    // Fermeture Rekovery temporaire ce jour-là (21 août 2026) : refuse une
    // heure qui tombe dans sa plage — voir [_temporaryClosuresFor].
    if (_date != null) {
      final minutes = picked.hour * 60 + picked.minute;
      for (final c in _temporaryClosuresFor(_date!)) {
        final startMinutes = _parseMinutes(c.startTime!);
        final endMinutes = _parseMinutes(c.endTime!);
        if (minutes >= startMinutes && minutes < endMinutes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                "L'espace Rekovery est fermé de ${c.startTime} à ${c.endTime} ce jour-là.",
              ),
            ));
          }
          return;
        }
      }
    }
    setState(() => _time = picked);
  }

  String _fmtDate(DateTime d) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${pad2(d.day)}/${pad2(d.month)}/${d.year}';
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _reserve() async {
    if (_date == null || _time == null) return;
    setState(() => _submitting = true);
    try {
      await context.read<RekoveryRepository>().requestSlot(date: _date!, startTime: _fmtTime(_time!));
      if (mounted) {
        setState(() {
          _date = null;
          _time = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Demande envoyée au coach.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur lors de la demande : $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: context.wp(12), vertical: context.hp(8)),
      child: Padding(
        padding: EdgeInsets.all(context.wp(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Le titre "Demander un créneau Rekovery" a été retiré (demande
            // du 6 août 2026) : les icônes calendrier/horloge des
            // `PickerTile` ci-dessous suffisent à comprendre l'intention.
            // Date et heure l'une sous l'autre (la date au-dessus), pas
            // côte à côte, depuis le 6 août 2026 (demande de Margaux).
            PickerTile(
              icon: Icons.calendar_today,
              label: _date == null ? 'Choisir une date' : _fmtDate(_date!),
              valueSet: _date != null,
              onTap: _pickDate,
            ),
            SizedBox(height: context.hp(10)),
            PickerTile(
              icon: Icons.access_time,
              label: _time == null ? 'Choisir une heure' : _fmtTime(_time!),
              valueSet: _time != null,
              onTap: _pickTime,
            ),
            SizedBox(height: context.hp(10)),
            ElevatedButton(
              onPressed: (_date == null || _time == null || _submitting) ? null : _reserve,
              child: _submitting
                  ? SizedBox(
                      height: context.hp(18),
                      width: context.wp(18),
                      child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Réserver'),
            ),
          ],
        ),
      ),
    );
  }
}
