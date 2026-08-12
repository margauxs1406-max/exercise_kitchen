import 'package:flutter/material.dart';

import '../models/registration_model.dart';
import '../models/slot_model.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Détermine d'où [SlotCard] tire la couleur d'un créneau (10 août 2026,
/// demande de Margaux — avant cette date, un seul jeu de couleurs, basé sur
/// le type, s'appliquait aux deux écrans) :
/// - [byType] (écran coach, `manage_planning_screen.dart`, valeur par
///   défaut) : la couleur distingue le TYPE de cours (utile au coach pour
///   repérer d'un coup d'œil individuels/duos/collectifs).
/// - [byRegistrationStatus] (écran adhérent, `weekly_planning_screen.dart`) :
///   la couleur distingue le STATUT D'INSCRIPTION de l'adhérent courant
///   (utile pour repérer où il est inscrit / en attente), quel que soit le
///   type de cours — voir [SlotCard.registrationStatus].
enum SlotCardColorMode { byType, byRegistrationStatus }

/// Un jeu de couleurs pour [SlotCard] : fond de la carte entière, fond de
/// l'avatar rond, et couleur de l'icône à l'intérieur.
class _SlotColors {
  final Color cardBackground;
  final Color avatarBackground;
  final Color iconColor;
  const _SlotColors(this.cardBackground, this.avatarBackground, this.iconColor);

  /// Jeu neutre (gris/noir), utilisé pour un collectif/workshop côté coach,
  /// et pour tout créneau non concerné par un statut particulier côté
  /// adhérent (créneau auquel l'adhérent n'est pas inscrit).
  static const neutral = _SlotColors(AppColors.white, AppColors.lightGrey, AppColors.black);

  /// Jeu "teinté" : fond de carte clair, avatar blanc, icône en couleur
  /// pleine — utilisé pour toute mise en avant (type de cours côté coach,
  /// statut d'inscription côté adhérent). [lightBackground] est l'une des
  /// couleurs claires de `AppColors` (10 août 2026, voir
  /// `lightGreen`/`lightMustard`/`lightOrange`).
  factory _SlotColors.tinted(Color lightBackground, Color fullColor) =>
      _SlotColors(lightBackground, AppColors.white, fullColor);
}

/// Carte d'affichage d'un créneau, utilisée par les écrans coach et
/// adhérent. [trailing] permet à chaque écran d'ajouter son action propre
/// (bouton d'inscription côté adhérent) ; il s'affiche à droite, après le
/// nombre d'inscrits.
///
/// **Couleurs (refonte du 10 août 2026, demande de Margaux)** — voir
/// [SlotCardColorMode] pour le principe général. Dans tous les cas, le
/// titre du créneau reste noir (seuls le fond de la carte et l'icône
/// changent) :
/// - [SlotCardColorMode.byType] (coach) : individuel → fond vert clair,
///   icône vert flashy pleine sur avatar blanc (10 août 2026 — remplace le
///   moutarde utilisé un temps, désormais réservé au statut "En attente"
///   côté adhérent) ; duo → fond orange clair, icône orange pleine sur
///   avatar blanc ; collectif/workshop → inchangés (fond blanc, avatar
///   gris clair, icône noire).
/// - [SlotCardColorMode.byRegistrationStatus] (adhérent) : les 3 types de
///   cours ont par défaut des couleurs identiques (fond blanc, avatar gris
///   clair, icône noire — même jeu neutre que collectif/workshop côté
///   coach), puis, selon [registrationStatus] : `confirmed` → fond vert
///   clair, icône vert flashy sur avatar blanc ; `waitlisted` → fond
///   moutarde clair, icône moutarde sur avatar blanc.
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
/// L'alerte "créneau vide / à un seul inscrit" (côté coach uniquement,
/// [highlightAlert]) reste un texte en gras, mais SEULEMENT en orange pour
/// un duo (comportement d'origine) — pour un collectif, elle est
/// désormais juste en gras, sans couleur (10 août 2026, demande de
/// Margaux : la couleur orange du texte se confondait avec la nouvelle
/// couleur de fond des duos).
class SlotCard extends StatelessWidget {
  final SlotModel slot;
  final Widget? trailing;
  final bool highlightAlert;
  final bool countBelowTime;
  final bool showCount;
  final SlotCardColorMode colorMode;
  // Uniquement pertinent quand [colorMode] vaut
  // [SlotCardColorMode.byRegistrationStatus] (écran adhérent) : `null`
  // signifie "pas de statut" (l'adhérent n'est pas concerné par ce
  // créneau) → couleurs neutres.
  final RegistrationStatus? registrationStatus;
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
    this.colorMode = SlotCardColorMode.byType,
    this.registrationStatus,
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

  // Expressions `switch` (Dart 3) plutôt que des `switch` classiques — plus
  // sûr : le compilateur garantit l'exhaustivité, sans risque d'oubli de
  // `break`/`return`.
  _SlotColors get _colors {
    if (colorMode == SlotCardColorMode.byRegistrationStatus) {
      return switch (registrationStatus) {
        RegistrationStatus.confirmed =>
          _SlotColors.tinted(AppColors.lightGreen, AppColors.flashyGreen),
        RegistrationStatus.waitlisted =>
          _SlotColors.tinted(AppColors.lightMustard, AppColors.mustardYellow),
        null => _SlotColors.neutral,
      };
    }
    return switch (slot.type) {
      // Vert (10 août 2026, demande de Margaux — remplace le moutarde
      // utilisé un temps, désormais réservé au statut "En attente" côté
      // adhérent).
      'individual' => _SlotColors.tinted(AppColors.lightGreen, AppColors.flashyGreen),
      'duo' => _SlotColors.tinted(AppColors.lightOrange, AppColors.orange),
      _ => _SlotColors.neutral, // collective, workshop
    };
  }

  @override
  Widget build(BuildContext context) {
    final showAlert =
        showCount && highlightAlert && (slot.isEmpty || slot.hasOnlyOneRegistered);
    final alertStyle = !showAlert
        ? const TextStyle(color: AppColors.mediumGrey)
        : (slot.type == 'duo'
            // Duo : comportement d'origine, texte orange gras.
            ? const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w600)
            // Collectif (et tout autre type comptabilisé) : juste gras,
            // sans couleur (10 août 2026).
            : const TextStyle(fontWeight: FontWeight.w600));

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

    final colors = _colors;
    return Card(
      color: colors.cardBackground,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colors.avatarBackground,
          foregroundColor: colors.iconColor,
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
