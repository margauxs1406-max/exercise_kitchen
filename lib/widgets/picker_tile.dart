import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Sélecteur de date/heure générique : fond blanc, icône toujours orange
/// (élément cliquable), texte gris non gras tant qu'aucune valeur n'est
/// choisie ("Choisir une date"/"Choisir une heure"), orange gras une fois la
/// valeur choisie/modifiée.
///
/// Extrait de `add_course_screen.dart` (où il stylait "Choisir une
/// date"/"Choisir une heure" pour l'ajout d'un cours duo côté coach) afin
/// d'être réutilisé tel quel ailleurs avec exactement le même rendu — par
/// exemple dans `add_rekovery_dialog.dart` — sans dupliquer le style.
///
/// [stackedLabel] : si fourni, bascule sur un affichage en deux lignes —
/// icône + ce texte court ("Début"/"Fin") sur la première, la valeur
/// choisie (`label`) seule sur la seconde. Sert dans les mises en page à
/// deux colonnes côte à côte, trop étroites pour tenir icône + date sur une
/// seule ligne sans retour à la ligne (voir la période de fermeture dans
/// `closure_actions_sheet.dart`/`add_course_screen.dart`) — `null` par
/// défaut, qui garde l'affichage classique sur une seule ligne partout
/// ailleurs (une tuile pleine largeur a la place pour icône + valeur).
class PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool valueSet;
  final VoidCallback onTap;
  final String? stackedLabel;

  const PickerTile({
    super.key,
    required this.icon,
    required this.label,
    required this.valueSet,
    required this.onTap,
    this.stackedLabel,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor = valueSet ? AppColors.orange : AppColors.mediumGrey;
    final valueWeight = valueSet ? FontWeight.w600 : FontWeight.normal;

    final content = stackedLabel == null
        ? Row(
            children: [
              Icon(icon, color: AppColors.orange),
              SizedBox(width: context.wp(12)),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: valueColor, fontWeight: valueWeight),
                ),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppColors.orange, size: context.wp(16)),
                  SizedBox(width: context.wp(6)),
                  Text(
                    stackedLabel!,
                    style: TextStyle(
                      color: AppColors.mediumGrey,
                      fontSize: context.sp(12),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              SizedBox(height: context.hp(4)),
              Text(
                label,
                style: TextStyle(color: valueColor, fontWeight: valueWeight),
              ),
            ],
          );

    // Hauteur verticale de l'encart : distincte pour l'affichage empilé
    // (Début/Fin d'une fermeture, deux lignes) et l'affichage classique sur
    // une seule ligne (toutes les autres tuiles de l'app) — pour pouvoir
    // ajuster l'un sans changer l'autre. C'est CETTE valeur (16 ci-dessous)
    // qu'il faut réduire pour rapetisser uniquement les encarts Début/Fin.
    final verticalPadding = stackedLabel == null ? context.hp(16) : context.hp(16);

    // Fond peint directement en blanc littéral (pas via un `Material` élevé,
    // qui reçoit sinon la surimpression "surface tint" orange du thème) —
    // le clic reste géré par InkWell, qui dessine son effet sur le Material
    // ancêtre fourni par le Scaffold.
    return ClipRRect(
      borderRadius: BorderRadius.circular(context.wp(10)),
      child: Container(
        color: AppColors.white,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(context.wp(10)),
              border: Border.all(color: AppColors.mediumGrey.withValues(alpha: 0.35)),
            ),
            padding: EdgeInsets.symmetric(horizontal: context.wp(14), vertical: verticalPadding),
            child: content,
          ),
        ),
      ),
    );
  }
}
