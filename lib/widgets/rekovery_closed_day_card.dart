import 'package:flutter/material.dart';

import '../models/rekovery_closure_model.dart';
import '../theme/app_theme.dart';

/// Carte "jour fermé" affichée à la place des créneaux habituels, sur
/// chacun des jours couverts par une fermeture Rekovery (`coach_rekovery_screen.dart` /
/// `adherent_rekovery_screen.dart`) — 21 août 2026, demande de Margaux.
///
/// **Format aligné sur `SlotCard`/`ClosureBanner` (21 août 2026)** : même
/// `Card`/`ListTile`, même icône ronde à gauche (fond blanc, cadenas seul —
/// `Icons.lock`, sans horloge), fond de carte en orange clair
/// (`AppColors.lightOrange`) — pour que les fermetures Rekovery se lisent
/// exactement comme les fermetures de salle et les cours du planning.
///
/// N'affiche l'heure de début/fin (sous le titre, en gris) QUE pour une
/// fermeture temporaire ([RekoveryClosureModel.isTemporary]) : une
/// fermeture prolongée n'a pas d'heure. Le message facultatif
/// ([RekoveryClosureModel.message]) s'affiche en dessous, s'il est
/// renseigné.
///
/// [onLongPress] : `null` par défaut (planning adhérent, lecture seule) —
/// branché côté coach uniquement, voir `rekovery_closure_actions_sheet.dart`.
class RekoveryClosedDayCard extends StatelessWidget {
  final RekoveryClosureModel closure;
  final VoidCallback? onLongPress;
  const RekoveryClosedDayCard({super.key, required this.closure, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final hasWindow =
        closure.isTemporary && closure.startTime != null && closure.endTime != null;
    final hasMessage = closure.message != null && closure.message!.trim().isNotEmpty;

    final subtitleLines = <Widget>[
      if (hasWindow) Text('${closure.startTime} - ${closure.endTime}'),
      if (hasMessage)
        Text(closure.message!, style: const TextStyle(color: AppColors.mediumGrey)),
    ];

    return Card(
      color: AppColors.lightOrange,
      child: ListTile(
        onLongPress: onLongPress,
        leading: const CircleAvatar(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.orange,
          child: Icon(Icons.lock),
        ),
        title: Text(closure.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitleLines.isEmpty
            ? null
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: subtitleLines),
      ),
    );
  }
}
