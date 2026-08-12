import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Bandeau de navigation de semaine ("< Semaine du XX/XX >"), en gris clair,
/// affiché entre l'en-tête ([WeekHeader]) et la zone de défilement du
/// planning (sections 4.1/4.2).
///
/// [recap] (7 août 2026, écran adhérent uniquement — voir `WeekRecapRow`) :
/// rangée de carrés optionnelle affichée sous "Semaine du XX/XX", à
/// l'intérieur du même bandeau gris. `null` par défaut : l'écran coach
/// (`manage_planning_screen.dart`) n'en passe pas et garde le bandeau
/// inchangé (une seule ligne).
///
/// Historique (10 août 2026) : ce paramètre `recap` a été brièvement
/// retiré au profit d'un widget dédié (`WeekRecapNavBar`, qui supprimait la
/// ligne "Semaine du XX/XX" et alignait les flèches sur les carrés) — puis
/// rétabli tel quel LE MÊME JOUR, à la demande de Margaux : la ligne
/// "Semaine du XX/XX" doit rester affichée normalement, avec le récap
/// (désormais des carrés 54x54 avec initiales de jour, voir `WeekRecapRow`)
/// simplement en dessous, comme à l'origine.
class WeekNavBar extends StatelessWidget {
  final DateTime weekStart;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final Widget? recap;

  const WeekNavBar({
    super.key,
    required this.weekStart,
    required this.onPreviousWeek,
    required this.onNextWeek,
    this.recap,
  });

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.lightGrey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onPreviousWeek,
                icon: const Icon(Icons.chevron_left, color: AppColors.black),
              ),
              Expanded(
                child: Text(
                  // sections 4.1/4.2 : toujours 2 chiffres pour le jour ET le
                  // mois ("06/07", jamais "06/7").
                  'Semaine du ${_pad2(weekStart.day)}/${_pad2(weekStart.month)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.black, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: onNextWeek,
                icon: const Icon(Icons.chevron_right, color: AppColors.black),
              ),
            ],
          ),
          if (recap != null) recap!,
        ],
      ),
    );
  }
}
