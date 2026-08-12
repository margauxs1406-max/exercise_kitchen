import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Icône de l'onglet Rekovery de la bottom bar, côté adhérent
/// (`adherent_home_screen.dart`) ET côté coach (`coach_home_screen.dart`) —
/// nouveau, 9 août 2026, remplace `Icons.thermostat` par le SVG dédié déjà
/// utilisé partout ailleurs pour Rekovery (voir `rekovery_request_card.dart`).
///
/// Contrairement à un `Icon` Material, `SvgPicture` ne lit pas
/// automatiquement la couleur ambiante posée par `NavigationBar.iconTheme`
/// (blanc à pleine opacité si l'onglet est sélectionné, 60% sinon — voir
/// `app_theme.dart`) : le `Builder` ci-dessous récupère cette couleur
/// explicitement via `IconTheme.of(context).color`, pour que l'icône
/// réagisse bien à la sélection comme les icônes Material voisines
/// (Photos/Planning/Adhérents).
class RekoveryNavIcon extends StatelessWidget {
  const RekoveryNavIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => SvgPicture.asset(
        'assets/thermometer.svg',
        width: context.wp(24),
        height: context.wp(24),
        colorFilter: ColorFilter.mode(
          IconTheme.of(context).color ?? AppColors.white,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}
