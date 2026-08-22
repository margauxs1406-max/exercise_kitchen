import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Libellé fixe au-dessus d'un champ de formulaire (au lieu d'un `labelText`
/// flottant qui, une fois posé sur le contour du champ, se retrouve à moitié
/// sur le fond blanc du champ et à moitié sur le fond gris de la page).
///
/// Style unique "Libellé de champ" du système typographique à 8 styles
/// (rationalisation des polices, 22 août 2026, demande de Margaux — voir
/// `audit_polices.md`) : noir, semi-gras (w600), taille responsive 14.
/// Remplace 3 implémentations dupliquées du même rendu, recopiées à la main
/// (`_FieldLabel` dans `add_course_screen.dart`, ex-canonique ; une copie
/// dans `add_rekovery_closure_screen.dart` ; une 3ᵉ dans
/// `rekovery_closure_actions_sheet.dart`).
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.hp(6)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.black,
            fontWeight: FontWeight.w600,
            fontSize: context.sp(14),
          ),
        ),
      ),
    );
  }
}
