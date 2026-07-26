/// Planning fixe des cours collectifs — ces créneaux ne changent jamais et
/// n'ont donc pas besoin d'écran de création : ils sont générés
/// automatiquement chaque semaine à partir de cette liste (voir
/// `PlanningRepository.ensureCollectiveSlotsForWeek`).
///
class DefaultCollectiveSlot {
  final int dayOfWeek; // 1 = lundi ... 7 = dimanche
  final String startTime; // "HH:mm"

  const DefaultCollectiveSlot(this.dayOfWeek, this.startTime);
}

const int kDefaultCollectiveCapacity = 6;

const List<DefaultCollectiveSlot> kDefaultCollectiveSchedule = [
  DefaultCollectiveSlot(1, '12:00'), // Lundi 12h
  DefaultCollectiveSlot(1, '16:30'), // Lundi 16h30
  DefaultCollectiveSlot(2, '12:00'), // Mardi 12h
  DefaultCollectiveSlot(2, '16:30'), // Mardi 16h30
  DefaultCollectiveSlot(2, '17:30'), // Mardi 17h30
  DefaultCollectiveSlot(3, '12:00'), // Mercredi 12h
  DefaultCollectiveSlot(3, '16:30'), // Mercredi 16h30
  DefaultCollectiveSlot(4, '12:00'), // Jeudi 12h
  DefaultCollectiveSlot(4, '16:30'), // Jeudi 16h30
  DefaultCollectiveSlot(4, '17:30'), // Jeudi 17h30
  DefaultCollectiveSlot(5, '12:00'), // Vendredi 12h
];

/// Tous les créneaux (collectifs et duo) durent 1h par défaut.
String addOneHour(String hhmm) {
  final parts = hhmm.split(':');
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  final endHour = (hour + 1) % 24;
  return '${endHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}