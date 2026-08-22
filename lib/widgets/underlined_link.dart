import 'package:flutter/material.dart';

import '../theme/responsive.dart';

/// Texte souligné cliquable (liens "Modifier", "Se déconnecter", "Mot de
/// passe oublié ?"...), couleur passée en paramètre pour couvrir aussi bien
/// le cas orange (le plus courant, sur fond clair) que le cas blanc (écran
/// de connexion, sur fond noir).
///
/// Style "lien souligné" (9ᵉ style, optionnel, du système typographique —
/// voir `audit_polices.md`, rationalisation des polices, 22 août 2026,
/// demande de Margaux) : semi-gras (w600), taille responsive 14,
/// soulignement de la même couleur que le texte. Remplace 3 implémentations
/// non partagées du même rendu (`_UnderlinedOrangeText` dans
/// `adherent_profile_screen.dart`, copies manuelles dans
/// `adherent_detail_screen.dart` et `login_screen.dart`).
class UnderlinedLink extends StatelessWidget {
  final String text;
  final Color color;
  final FontWeight fontWeight;

  const UnderlinedLink(
    this.text, {
    super.key,
    required this.color,
    this.fontWeight = FontWeight.w600,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontWeight: fontWeight,
        fontSize: context.sp(14),
        decoration: TextDecoration.underline,
        decorationColor: color,
      ),
    );
  }
}
