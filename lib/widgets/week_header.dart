import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Hauteur commune à cet en-tête et à celui de l'écran "Politique de
/// confidentialité" (section 3.1) : alignée sur la hauteur standard de la
/// bottom bar (`NavigationBar`, 80 en Material 3) pour un en-tête compact,
/// maintenant qu'il n'affiche plus que le type de semaine.
const double kTallHeaderHeight = 80;

/// En-tête du planning (coach et adhérent, section 4) : logo à gauche, type
/// de semaine (Basique / Intermédiaire / Dynamique) au centre — modifiable
/// via [weekTypeContent] côté coach (menu déroulant), affiché en lecture
/// seule côté adhérent (simple texte).
///
/// La navigation de semaine ("< Semaine du XX/XX >") n'est plus ici : elle
/// est affichée par [WeekNavBar], en bandeau gris clair juste en dessous de
/// cet en-tête, au-dessus de la zone de défilement.
class WeekHeader extends StatelessWidget implements PreferredSizeWidget {
  final Widget weekTypeContent;
  // Un seul des deux est fourni selon le rôle : [onProfileTap] pour un
  // adhérent (ouvre `AdherentProfileScreen`, qui contient elle-même la
  // déconnexion), [onLogout] pour un coach (déconnexion directe, inchangée).
  final VoidCallback? onLogout;
  final VoidCallback? onProfileTap;

  const WeekHeader({
    super.key,
    required this.weekTypeContent,
    this.onLogout,
    this.onProfileTap,
  }) : assert(
          onLogout != null || onProfileTap != null,
          'onLogout ou onProfileTap est requis',
        );

  @override
  Size get preferredSize => const Size.fromHeight(kTallHeaderHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // `kTallHeaderHeight` reste ici en dur (non-responsive) : cette valeur
      // sert aussi à `preferredSize` ci-dessus, une propriété imposée par
      // l'interface `PreferredSizeWidget` que Flutter (Scaffold) lit
      // directement sur l'instance du widget, SANS passer de `BuildContext`
      // — impossible donc d'y appeler `context.hp(...)`. La conserver en dur
      // aux deux endroits évite un décalage entre la hauteur réservée par le
      // Scaffold (`preferredSize`) et la hauteur réelle de cet `AppBar`
      // (`toolbarHeight`), qui serait pire (chevauchement/espace vide) qu'une
      // hauteur d'en-tête non proportionnelle.
      toolbarHeight: kTallHeaderHeight,
      titleSpacing: context.wp(12),
      automaticallyImplyLeading: false,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/EK.svg',
            height: context.hp(48),
            fit: BoxFit.contain,
            // Le SVG est dessiné en noir par défaut : on le force en blanc
            // pour qu'il ressorte sur le fond noir de cet en-tête.
            colorFilter: const ColorFilter.mode(AppColors.white, BlendMode.srcIn),
          ),
          SizedBox(width: context.wp(12)),
          Expanded(child: Center(child: weekTypeContent)),
        ],
      ),
      actions: [
        if (onProfileTap != null)
          IconButton(
            tooltip: 'Profil',
            icon: const Icon(Icons.person_outline),
            onPressed: onProfileTap,
          )
        else
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: onLogout,
          ),
      ],
    );
  }
}
