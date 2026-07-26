/// Retourne le lundi (à minuit, heure locale) de la semaine contenant [date].
/// Utilisé par les écrans coach et adhérent pour afficher le même
/// découpage "semaine du lundi au dimanche" (section 1.3 / 2.2).
DateTime mondayOf(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return d.subtract(Duration(days: d.weekday - 1));
}
