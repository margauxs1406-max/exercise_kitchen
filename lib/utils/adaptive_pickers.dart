import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Sélecteurs de date/heure adaptés à la plateforme (7 août 2026, demande de
/// Margaux : les utilisateurs iPhone trouvaient le calendrier/l'horloge
/// Material "typiquement Android"). Sur Android (et tout ce qui n'est pas
/// iOS), ces fonctions délèguent directement à `showDatePicker`/
/// `showTimePicker` (comportement strictement inchangé) ; sur iPhone, elles
/// affichent une feuille Cupertino (roue de défilement, boutons "Annuler"/
/// "OK") plutôt que le calendrier/l'horloge Material.
///
/// Même signature d'appel que `showDatePicker`/`showTimePicker` (moins les
/// options non utilisées ailleurs dans le code), pour remplacer directement
/// tous les appels existants sans changer leur logique environnante.
///
/// ⚠️ Exception volontaire : `showDateRangePicker` (choix d'une période de
/// fermeture, voir `add_course_screen.dart`) n'a PAS d'équivalent ici — il
/// n'existe pas de calendrier de plage Cupertino standard, et reconstruire
/// un composant de ce type maison pour cet unique usage (réservé au coach,
/// peu fréquent) n'a pas semblé proportionné. Il reste donc affiché dans son
/// style Material actuel sur les deux plateformes.
Future<DateTime?> showAdaptiveDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  bool Function(DateTime day)? selectableDayPredicate,
}) {
  if (!Platform.isIOS) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      selectableDayPredicate: selectableDayPredicate,
      // Correctif (11 août 2026, bug remarqué par Margaux : grand blanc
      // entre le calendrier et les boutons "Annuler"/"OK") : la boîte de
      // dialogue Material du calendrier a une hauteur FIXE, calculée pour
      // une échelle de texte "normale" (1.0). Si le réglage "taille
      // d'affichage/police" du téléphone Android s'écarte de cette
      // référence, le contenu (en-tête + calendrier) prend moins (ou plus)
      // de place que prévu, ce qui laisse ce grand blanc au-dessus des
      // boutons (ou, à l'inverse, fait déborder le contenu) — un
      // comportement connu de la boîte de dialogue Material 3 de Flutter,
      // sans lien avec l'adaptation des sélecteurs pour iPhone (la branche
      // Android ci-dessus délègue toujours, comme avant, directement à
      // `showDatePicker` sans aucune autre modification). On borne donc
      // l'échelle de texte à une plage raisonnable UNIQUEMENT pour cette
      // boîte de dialogue précise (le reste de l'app garde le réglage du
      // téléphone tel quel).
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 0.9,
        maxScaleFactor: 1.3,
        child: child!,
      ),
    );
  }
  return _showCupertinoDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    selectableDayPredicate: selectableDayPredicate,
  );
}

Future<TimeOfDay?> showAdaptiveTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  if (!Platform.isIOS) {
    // Même correctif que ci-dessus (`showAdaptiveDatePicker`) pour la boîte
    // de dialogue de l'horloge Material — voir le commentaire détaillé
    // là-bas.
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 0.9,
        maxScaleFactor: 1.3,
        child: child!,
      ),
    );
  }
  return _showCupertinoTimePicker(context: context, initialTime: initialTime);
}

Future<DateTime?> _showCupertinoDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  bool Function(DateTime day)? selectableDayPredicate,
}) {
  final clamped = initialDate.isBefore(firstDate)
      ? firstDate
      : (initialDate.isAfter(lastDate) ? lastDate : initialDate);
  var selected = clamped;
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: CupertinoColors.systemBackground,
    builder: (sheetContext) {
      String? error;
      return StatefulBuilder(
        builder: (context, setState) {
          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Annuler'),
                    ),
                    CupertinoButton(
                      onPressed: () {
                        if (selectableDayPredicate != null &&
                            !selectableDayPredicate(selected)) {
                          setState(() => error =
                              "La salle est fermée ce jour-là — choisis une autre date.");
                          return;
                        }
                        Navigator.of(context).pop(selected);
                      },
                      child: const Text('OK'),
                    ),
                  ],
                ),
                if (error != null)
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: context.wp(16), vertical: context.hp(4)),
                    child: Text(
                      error!,
                      style: const TextStyle(color: AppColors.flashyRed),
                    ),
                  ),
                SizedBox(
                  height: context.hp(260),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: clamped,
                    minimumDate: firstDate,
                    maximumDate: lastDate,
                    onDateTimeChanged: (d) => selected = d,
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<TimeOfDay?> _showCupertinoTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  final now = DateTime.now();
  final initial = DateTime(now.year, now.month, now.day, initialTime.hour, initialTime.minute);
  var selected = initial;
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: CupertinoColors.systemBackground,
    builder: (context) {
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuler'),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.of(context)
                      .pop(TimeOfDay(hour: selected.hour, minute: selected.minute)),
                  child: const Text('OK'),
                ),
              ],
            ),
            SizedBox(
              height: context.hp(260),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                use24hFormat: true,
                initialDateTime: initial,
                onDateTimeChanged: (d) => selected = d,
              ),
            ),
          ],
        ),
      );
    },
  );
}
