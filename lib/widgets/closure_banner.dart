import 'package:flutter/material.dart';

import '../models/closure_model.dart';
import '../theme/app_theme.dart';

/// Bandeau de fermeture affiché en tête d'une journée du planning (coach ET
/// adhérent, et depuis le 21 août 2026 aussi dans les écrans Rekovery — voir
/// `coach_rekovery_screen.dart`/`adherent_rekovery_screen.dart`) — section
/// "ajouter un évènement > fermeture".
///
/// **Format aligné sur `SlotCard` (21 août 2026, demande de Margaux)** :
/// même `Card`/`ListTile`, même icône ronde à gauche (fond blanc, icône
/// pleine — ici un simple cadenas, `Icons.lock`, sans horloge), et fond de
/// carte en orange clair (`AppColors.lightOrange`, la même teinte que les
/// cours duo) — pour que les fermetures se lisent comme n'importe quel
/// autre créneau du planning, plutôt que comme un bandeau à part.
///
/// MVP : purement informatif dans le planning, pas d'envoi d'email/
/// notification automatique pour l'instant (voir décision du 2026-07-09).
///
/// [onLongPress] : appui long ouvrant "Modifier"/"Supprimer" (voir
/// `closure_actions_sheet.dart`) — branché côté coach, aussi bien dans le
/// planning principal (`manage_planning_screen.dart`) que dans l'onglet
/// Rekovery (`coach_rekovery_screen.dart`, depuis le 21 août 2026 — "où
/// qu'il soit", demande de Margaux) ; `null` par défaut, ce qui laisse le
/// bandeau non cliquable côté adhérent (toujours en lecture seule).
class ClosureBanner extends StatelessWidget {
  final ClosureModel closure;
  final VoidCallback? onLongPress;
  const ClosureBanner({super.key, required this.closure, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    // Le message est facultatif depuis le 21 août 2026 (demande de Margaux)
    // — texte de repli si le coach ne l'a pas renseigné.
    final message = closure.message.trim().isEmpty ? 'Fermeture de la salle' : closure.message;
    return Card(
      color: AppColors.lightOrange,
      child: ListTile(
        onLongPress: onLongPress,
        leading: const CircleAvatar(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.orange,
          child: Icon(Icons.lock),
        ),
        title: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
