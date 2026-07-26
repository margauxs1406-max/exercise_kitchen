import 'package:flutter/material.dart';

import '../models/slot_model.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Carte d'affichage d'un créneau, utilisée par les écrans coach et
/// adhérent. [trailing] permet à chaque écran d'ajouter son action propre
/// (bouton d'inscription côté adhérent) ; il s'affiche à droite, après le
/// nombre d'inscrits.
///
/// Le fond de la carte est toujours blanc, quel que soit le type de cours.
/// Seule la forme de l'icône distingue les types (silhouette à deux
/// personnes pour un duo, une personne pour un individuel, groupe pour un
/// collectif, calendrier pour un workshop) — la couleur reste neutre
/// (noir/gris) dans tous les cas.
///
/// Le jour n'est plus répété ici : il est affiché une seule fois par
/// [DayHeader], au-dessus de chaque groupe de créneaux du même jour (voir
/// `slot_grouping.dart`).
///
/// [countBelowTime] (section 4.2, écran adhérent) place le nombre
/// d'inscrits sous l'heure plutôt qu'à côté (par défaut : à côté, comme sur
/// l'écran coach, inchangé).
///
/// [showCount] masque complètement le nombre d'inscrits — utilisé pour les
/// créneaux individuels et les workshops (section "ajouter un cours" /
/// "ajouter un évènement"), qui n'ont pas d'inscription libre.
///
/// L'alerte "créneau vide / à un seul inscrit" reste visuellement distincte
/// de la couleur de type : un texte en orange gras, pas un fond
/// supplémentaire.
class SlotCard extends StatelessWidget {
  final SlotModel slot;
  final Widget? trailing;
  final bool highlightAlert;
  final bool countBelowTime;
  final bool showCount;
  // Section 1.3 : côté coach, tapoter sur un créneau collectif ou duo ouvre
  // la pop-up listant les inscrits et la liste d'attente (voir
  // `manage_planning_screen.dart` et `slot_roster_dialog.dart`). `null` par
  // défaut : les autres écrans (adhérent) ne passent rien et gardent le
  // comportement actuel (carte non cliquable).
  final VoidCallback? onTap;
  // Un appui long sur un cours duo ou individuel ouvre les actions
  // "Modifier"/"Supprimer" (voir `manage_planning_screen.dart` et
  // `slot_actions_sheet.dart`). `null` par défaut, comme [onTap].
  final VoidCallback? onLongPress;

  const SlotCard({
    super.key,
    required this.slot,
    this.trailing,
    this.highlightAlert = false,
    this.countBelowTime = false,
    this.showCount = true,
    this.onTap,
    this.onLongPress,
  });

  IconData get _icon {
    switch (slot.type) {
      case 'duo':
        return Icons.people;
      case 'individual':
        return Icons.person;
      case 'workshop':
        return Icons.event;
      default:
        return Icons.groups;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showAlert =
        showCount && highlightAlert && (slot.isEmpty || slot.hasOnlyOneRegistered);
    final alertStyle = showAlert
        ? const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w600)
        : const TextStyle(color: AppColors.mediumGrey);

    final Widget subtitle;
    if (!showCount) {
      // Individuel / workshop : pas de compteur d'inscrits, juste l'heure
      // et, pour un workshop, sa description.
      subtitle = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${slot.startTime}–${slot.endTime}'),
          if (slot.description != null && slot.description!.isNotEmpty) ...[
            SizedBox(height: context.hp(2)),
            Text(slot.description!, style: const TextStyle(color: AppColors.mediumGrey)),
          ],
        ],
      );
    } else {
      final countText = Text(
        '${slot.registeredCount}/${slot.capacity} inscrit(s)'
        '${slot.waitlistCount > 0 ? ' · ${slot.waitlistCount} en attente' : ''}',
        style: alertStyle,
      );
      subtitle = countBelowTime
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${slot.startTime}–${slot.endTime}'),
                SizedBox(height: context.hp(2)),
                countText,
              ],
            )
          : Row(
              children: [
                Text('${slot.startTime}–${slot.endTime}'),
                const Spacer(),
                countText,
              ],
            );
    }

    return Card(
      color: AppColors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.lightGrey,
          foregroundColor: AppColors.black,
          child: Icon(_icon),
        ),
        title: Text(slot.courseTitle),
        subtitle: subtitle,
        trailing: trailing,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
