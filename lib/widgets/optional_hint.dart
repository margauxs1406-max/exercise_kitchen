import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Précision "Facultatif" affichée juste avant l'exemple d'un champ
/// optionnel (message aux adhérents lors d'une fermeture, description d'un
/// cours...) — remplace le suffixe "(facultatif)" ajouté au libellé lui-même.
///
/// Style unique "Précision Facultatif" du système typographique à 8 styles
/// (rationalisation des polices, 22 août 2026, demande de Margaux — voir
/// `audit_polices.md`) : gris moyen, normal, taille responsive 12. Remplace
/// 3 occurrences identiques recopiées à la main (`add_course_screen.dart`,
/// `add_rekovery_closure_screen.dart`, `rekovery_closure_actions_sheet.dart`).
class OptionalHint extends StatelessWidget {
  const OptionalHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.hp(4)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Facultatif',
          style: TextStyle(color: AppColors.mediumGrey, fontSize: context.sp(12)),
        ),
      ),
    );
  }
}
