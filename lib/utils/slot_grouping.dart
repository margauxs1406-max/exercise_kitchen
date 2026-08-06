import '../models/closure_model.dart';
import '../models/slot_model.dart';

/// Regroupe le planning d'une semaine (créneaux, fermetures — déjà
/// filtrés/triés en amont si besoin) en une liste plate utilisable
/// directement par un `ListView.builder`, mélangeant :
/// - des marqueurs de jour ([DateTime], à minuit),
/// - des [ClosureModel] (bandeau de fermeture, en tête de journée),
/// - des [SlotModel] (cartes de cours, triées par heure).
///
/// Rekovery ne passe plus par cette fonction : c'est désormais un onglet
/// dédié avec sa propre liste (voir `adherent_rekovery_screen.dart` /
/// `coach_rekovery_screen.dart`), plus de mélange dans le planning.
///
/// Un jour n'apparaît que s'il contient au moins un de ces deux éléments.
List<Object> groupSlotsByDay(
  List<SlotModel> slots, {
  List<ClosureModel> closures = const [],
}) {
  DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  // Une fermeture peut désormais s'étendre sur plusieurs jours
  // (`startDate`..`endDate`) : elle doit apparaître sur CHACUN des jours
  // qu'elle couvre, pas seulement le premier — sinon son bandeau
  // disparaîtrait dès le lendemain de sa création alors que la salle est
  // toujours fermée ce jour-là.
  bool closureCoversDay(ClosureModel c, DateTime day) =>
      !day.isBefore(dayOf(c.startDate)) && !day.isAfter(dayOf(c.endDate));

  final closureDays = <DateTime>{};
  for (final c in closures) {
    var day = dayOf(c.startDate);
    final lastDay = dayOf(c.endDate);
    while (!day.isAfter(lastDay)) {
      closureDays.add(day);
      day = day.add(const Duration(days: 1));
    }
  }

  final days = <DateTime>{
    ...slots.map((s) => dayOf(s.date)),
    ...closureDays,
  }.toList()
    ..sort();

  final result = <Object>[];
  for (final day in days) {
    result.add(day);

    result.addAll(closures.where((c) => closureCoversDay(c, day)));

    final daySlots = slots.where((s) => dayOf(s.date) == day).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    result.addAll(daySlots);
  }
  return result;
}