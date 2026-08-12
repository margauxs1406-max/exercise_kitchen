import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/user_model.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Statut d'UNE occurrence (une formule précise, un jour précis) dans le
/// récap de semaine (voir [WeekRecapRow]) — seulement 2 valeurs, contrairement
/// à l'ancienne version (10 août 2026) qui avait un 3ᵉ état [empty] : une
/// formule présente ce jour-là est TOUJOURS soit confirmée, soit en attente,
/// jamais "vide" (l'absence de toute occurrence se lit directement sur
/// `dayFormulas[i].isEmpty`, voir [WeekRecapRow], pas sur ce statut).
/// - [waitlisted] : liste d'attente collective/duo, ou demande Rekovery
///   `pending`/`proposed`.
/// - [confirmed] : inscription confirmée, créneau individuel (toujours
///   confirmé), ou demande Rekovery `accepted`.
///
/// Le calcul lui-même vit dans `_WeekRecapLoader` (`weekly_planning_screen.dart`).
enum DayRecapStatus { waitlisted, confirmed }

/// Rangée de récap de la semaine (section 2.2ter), affichée dans le bandeau
/// "Semaine du XX/XX" de l'écran adhérent UNIQUEMENT (voir
/// `weekly_planning_screen.dart` — l'écran coach,
/// `manage_planning_screen.dart`, n'utilise pas ce widget), via le
/// paramètre `recap` de [WeekNavBar].
///
/// Historique de la mise en page (10 août 2026) : ce widget a brièvement
/// remplacé la ligne "Semaine du XX/XX" par une rangée de dates JJ/MM avec
/// les flèches de navigation alignées sur les carrés (`WeekRecapNavBar`,
/// depuis supprimé) — **revenu en arrière le même jour, à la demande de
/// Margaux** : la ligne "Semaine du XX/XX" et les initiales de jour
/// ("L M M J V") sont rétablies telles qu'avant, la taille des carrés
/// (54x54) et des icônes (20) restant elle inchangée.
///
/// **Couleur d'un carré** (refonte du 10 août 2026, demande de Margaux — le
/// but est de voir en un coup d'œil à quels jours l'adhérent est
/// CONFIRMÉ et à quels jours il est seulement EN ATTENTE, y compris quand
/// les deux se produisent le même jour sur des formules différentes) :
/// - **gris clair** (`AppColors.recapEmptyGrey`), si l'adhérent n'a AUCUNE
///   occurrence ce jour-là (`dayFormulas[i].isEmpty`).
/// - **une seule occurrence** ce jour-là : le carré entier prend la couleur
///   de son statut (vert flashy si confirmée, moutarde si en attente).
/// - **2 occurrences** ce jour-là, avec des statuts DIFFÉRENTS (ex. un
///   cours confirmé + un Rekovery en attente) : le carré est coupé en 2
///   par la diagonale (voir [_DiagonalLinePainter]) — chaque triangle
///   prend la couleur du statut de l'occurrence placée de son côté (voir
///   [_DiagonalIcons] : même côté que l'icône elle-même, jamais un statut
///   agrégé arbitraire). Si les statuts sont identiques, les 2 triangles
///   ont simplement la même couleur (visuellement continu, seul le trait
///   de séparation reste visible).
/// - **3 occurrences** ce jour-là (11 août 2026, demande de Margaux — cas
///   rare mais possible, ex. collectif + duo + Rekovery le même jour) : le
///   grand triangle haut-gauche garde la couleur de la 1ʳᵉ occurrence ; le
///   grand triangle bas-droit se sous-divise à son tour en 2 PETITS
///   triangles (2ᵉ trait, du centre du carré au coin bas-droit), un par
///   occurrence restante (voir [_SplitSquarePainter] pour le détail
///   géométrique). Les icônes rétrécissent en conséquence pour tenir dans
///   ces plus petits triangles (voir `_DaySquare.build`).
///
/// Dans tous les cas où le carré n'est pas vide, une ou plusieurs petites
/// icônes blanches apparaissent à l'intérieur (une par formule à laquelle
/// l'adhérent a une occurrence CE jour précis — collectif/duo/individuel/
/// Rekovery, dans l'ordre de `kAllFormulas`). Depuis le 10 août 2026
/// (demande de Margaux), plusieurs icônes le même jour ne sont plus
/// centrées côte à côte mais réparties de part et d'autre d'un trait
/// diagonal fin (coin haut-droite → coin bas-gauche, voir
/// [_DiagonalLinePainter]) — les icônes elles-mêmes se placent dans les
/// coins haut-GAUCHE/bas-DROIT, donc bien à côté du trait et jamais
/// dessus (voir [_DiagonalIcons] pour le détail). Ce trait n'apparaît que
/// pour un jour avec 2 occurrences ou plus ; un jour avec une seule
/// occurrence (ou aucune) ne l'affiche pas.
///
/// [dayFormulas] et [dayFormulaStatuses] doivent tous les deux contenir
/// exactement 5 éléments (index 0 = lundi … index 4 = vendredi) ; pour
/// chaque jour, [dayFormulaStatuses] doit avoir une entrée pour CHAQUE
/// formule de [dayFormulas] à cet index (une formule présente a toujours
/// un statut). Le calcul lui-même vit dans `_WeekRecapLoader`
/// (`weekly_planning_screen.dart`), ce widget ne fait qu'afficher.
class WeekRecapRow extends StatelessWidget {
  final List<Set<String>> dayFormulas;
  final List<Map<String, DayRecapStatus>> dayFormulaStatuses;

  // Initiales des 5 jours (lundi à vendredi), affichées au-dessus de chaque
  // carré. "Mardi" et "Mercredi" partagent la même initiale ("M") — sans
  // ambiguïté ici puisque l'ordre (toujours lundi → vendredi) porte déjà le
  // sens, exactement comme sur la maquette fournie par Margaux.
  static const _dayLetters = ['L', 'M', 'M', 'J', 'V'];

  const WeekRecapRow({super.key, required this.dayFormulas, required this.dayFormulaStatuses})
      : assert(dayFormulas.length == 5, 'dayFormulas doit contenir exactement 5 jours (lun-ven)'),
        assert(dayFormulaStatuses.length == 5,
            'dayFormulaStatuses doit contenir exactement 5 jours (lun-ven)');

  @override
  Widget build(BuildContext context) {
    // Même style que "Semaine du XX/XX" (`WeekNavBar`), pour que les
    // initiales des jours s'accordent visuellement avec le reste du
    // bandeau.
    const dayLetterStyle = TextStyle(color: AppColors.black, fontWeight: FontWeight.w600);
    return Padding(
      padding: EdgeInsets.only(bottom: context.hp(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < dayFormulas.length; i++) ...[
            if (i > 0) SizedBox(width: context.wp(10)),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_dayLetters[i], style: dayLetterStyle),
                SizedBox(height: context.hp(4)),
                _DaySquare(formulas: dayFormulas[i], statuses: dayFormulaStatuses[i]),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DaySquare extends StatelessWidget {
  final Set<String> formulas;
  final Map<String, DayRecapStatus> statuses;
  const _DaySquare({required this.formulas, required this.statuses});

  static Color _colorFor(DayRecapStatus status) => switch (status) {
        // Vert flashy — remplace l'orange le 10 août 2026 (confusion avec
        // les CTA "S'inscrire"/"File d'attente" du planning).
        DayRecapStatus.confirmed => AppColors.flashyGreen,
        // Moutarde (10 août 2026, demande de Margaux) — déjà la couleur du
        // statut "En attente" ailleurs dans l'app, voir
        // `AppColors.mustardYellow`.
        DayRecapStatus.waitlisted => AppColors.mustardYellow,
      };

  @override
  Widget build(BuildContext context) {
    // 54x54 (taille conservée lors du retour en arrière du 10 août 2026 —
    // seule la mise en page autour des carrés a été annulée, pas leur
    // taille).
    final size = context.wp(54);
    final radius = BorderRadius.circular(context.wp(8));

    if (formulas.isEmpty) {
      // Gris clair (10 août 2026, couleur exacte fournie par Margaux —
      // remplace le gris semi-foncé générique utilisé un temps, lui-même
      // un remplacement du vert pâle d'origine).
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: AppColors.recapEmptyGrey, borderRadius: radius),
      );
    }

    // Toujours dans l'ordre de `kAllFormulas`, pour un ordre d'icônes
    // cohérent d'un carré à l'autre — `icons`/`iconColors` restent donc
    // synchronisés index par index (même formule, même position).
    final orderedFormulas = [for (final f in kAllFormulas) if (formulas.contains(f)) f];
    // Icônes rétrécies à partir de 3 occurrences le même jour (11 août
    // 2026, demande de Margaux) : au-delà de 2, les triangles sont plus
    // petits (voir [_SplitSquarePainter], cas à 3 couleurs ci-dessous), la
    // taille d'icône d'origine (20) déborderait de son triangle.
    final iconSize = orderedFormulas.length >= 3 ? context.wp(14) : context.wp(20);
    final icons = [
      for (final f in orderedFormulas) _FormulaMiniIcon(formula: f, size: iconSize),
    ];
    final iconColors = [for (final f in orderedFormulas) _colorFor(statuses[f]!)];

    if (icons.length == 1) {
      // Une seule occurrence : carré uniforme, pas de diagonale à tracer
      // (rien à séparer visuellement).
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: iconColors.single, borderRadius: radius),
        alignment: Alignment.center,
        child: icons.single,
      );
    }

    // 2 occurrences ou plus : le carré se coupe en plusieurs triangles
    // (10-11 août 2026, demande de Margaux) — chaque triangle reprend la
    // couleur du statut de l'occurrence placée de son côté (voir
    // [_DiagonalIcons]), pour distinguer par exemple un cours confirmé
    // (vert) d'un Rekovery en attente (moutarde) le même jour. À partir de
    // 3 occurrences, le grand triangle bas-droit se sous-divise lui-même
    // en 2 (voir [_SplitSquarePainter]/[_DiagonalLinePainter] pour le
    // détail géométrique) — au-delà de 3 (4 formules le même jour,
    // extrêmement rare), seules les 3 premières ont un triangle dédié, la
    // 4ᵉ éventuelle n'a pour l'instant pas de représentation propre.
    return Container(
      width: size,
      height: size,
      // `Clip.antiAlias` : le trait diagonal ET les triangles de fond
      // (voir `_SplitSquarePainter`/`_DiagonalLinePainter` ci-dessous)
      // restent ainsi coupés net aux coins arrondis, sans dépasser
      // visuellement la forme du carré.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: radius),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _SplitSquarePainter(colors: iconColors)),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _DiagonalLinePainter(splitRightTriangle: iconColors.length >= 3),
            ),
          ),
          Padding(
            // Marge intérieure : les icônes des coins (voir
            // `_DiagonalIcons`) restent ainsi bien à l'intérieur des coins
            // arrondis du carré, sans les chevaucher.
            padding: EdgeInsets.all(context.wp(6)),
            child: _DiagonalIcons(icons: icons),
          ),
        ],
      ),
    );
  }
}

/// Fond en 2 ou 3 triangles d'un carré du récap avec 2 occurrences ou plus
/// (10-11 août 2026, demande de Margaux) — [colors] contient une couleur
/// par occurrence, dans le même ordre que les icônes correspondantes (voir
/// [_DiagonalIcons] : les 2 widgets doivent donc rester basés sur le même
/// ordre, `orderedFormulas` dans `_DaySquare.build`).
///
/// - **2 couleurs** : la diagonale principale (coin haut-droite → coin
///   bas-gauche, même axe que [_DiagonalLinePainter]) partage le carré en
///   2 — grand triangle haut-GAUCHE ([colors]\[0\]), grand triangle
///   bas-DROIT ([colors]\[1\]).
/// - **3 couleurs** (11 août 2026 — ex. cours confirmé + duo en attente +
///   Rekovery en attente le même jour) : le grand triangle haut-gauche
///   reste entier ([colors]\[0\]) ; le grand triangle bas-droit se
///   sous-divise à son tour en 2 PETITS triangles, via un 2ᵉ trait
///   partant du CENTRE du carré (où la diagonale principale le traverse)
///   jusqu'au coin bas-droit — soit la moitié de l'AUTRE diagonale du
///   carré (haut-gauche → bas-droit), non tracée sur son autre moitié
///   puisque le grand triangle haut-gauche n'est lui pas subdivisé. Ça
///   donne un petit triangle haut-DROIT ([colors]\[1\]) et un petit
///   triangle bas-GAUCHE-de-la-zone-restante, càd collé au coin bas-droit
///   côté bas ([colors]\[2\]).
/// - **4 couleurs ou plus** (4 formules le même jour — extrêmement rare) :
///   seules les 3 premières sont utilisées pour l'instant, la 4ᵉ n'a pas
///   encore de triangle dédié (pas demandé à ce jour).
class _SplitSquarePainter extends CustomPainter {
  final List<Color> colors;
  const _SplitSquarePainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final topLeft = Offset.zero;
    final topRight = Offset(size.width, 0);
    final bottomRight = Offset(size.width, size.height);
    final bottomLeft = Offset(0, size.height);
    final center = Offset(size.width / 2, size.height / 2);

    final bigTopLeftTriangle = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(topRight.dx, topRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..close();
    canvas.drawPath(bigTopLeftTriangle, Paint()..color = colors.first);

    if (colors.length < 3) {
      // 2 couleurs (ou 1, par sécurité — ne devrait pas arriver en
      // pratique, `_DaySquare` gère ce cas séparément) : grand triangle
      // bas-droit entier.
      final bigBottomRightTriangle = Path()
        ..moveTo(topRight.dx, topRight.dy)
        ..lineTo(bottomRight.dx, bottomRight.dy)
        ..lineTo(bottomLeft.dx, bottomLeft.dy)
        ..close();
      canvas.drawPath(
        bigBottomRightTriangle,
        Paint()..color = colors.length > 1 ? colors[1] : colors.first,
      );
      return;
    }

    // 3 couleurs (ou plus, voir doc de classe) : grand triangle bas-droit
    // sous-divisé en 2 petits triangles par le trait centre → coin
    // bas-droit.
    final smallTopRightTriangle = Path()
      ..moveTo(topRight.dx, topRight.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(center.dx, center.dy)
      ..close();
    final smallBottomTriangle = Path()
      ..moveTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..lineTo(center.dx, center.dy)
      ..close();
    canvas.drawPath(smallTopRightTriangle, Paint()..color = colors[1]);
    canvas.drawPath(smallBottomTriangle, Paint()..color = colors[2]);
  }

  @override
  bool shouldRepaint(covariant _SplitSquarePainter oldDelegate) {
    if (oldDelegate.colors.length != colors.length) return true;
    for (var i = 0; i < colors.length; i++) {
      if (oldDelegate.colors[i] != colors[i]) return true;
    }
    return false;
  }
}

/// Trait(s) diagonal(aux) fin(s) séparant les triangles de fond (voir
/// [_SplitSquarePainter] pour le détail géométrique exact), de la couleur
/// du fond de l'app (`AppColors.lightGrey`, `scaffoldBackgroundColor` —
/// voir `app_theme.dart`), affiché(s) par-dessus les triangles de fond
/// d'un carré du récap avec 2 occurrences ou plus.
///
/// - Trait principal (coin haut-DROITE → coin bas-GAUCHE — sens précisé
///   par Margaux le 10 août 2026, différent du sens de répartition des
///   icônes, voir [_DiagonalIcons] ci-dessous pour le même sens) :
///   toujours tracé.
/// - [splitRightTriangle] (11 août 2026, demande de Margaux — cas à 3
///   occurrences le même jour) : trait supplémentaire du CENTRE du carré
///   au coin bas-droit, qui sous-divise le grand triangle bas-droit en 2
///   petits triangles (voir [_SplitSquarePainter]).
///
/// Épaisseur volontairement FIXE à 2 pixels physiques (1 à l'origine,
/// épaissi le 10 août 2026 à la demande de Margaux), pas de
/// `context.wp(2)` : comme `strokeWidth` d'un indicateur de chargement
/// (voir la convention responsive, `responsive.dart`), c'est un trait de
/// séparation fin, pas une dimension de mise en page à l'échelle de
/// l'écran — un nombre fixe de pixels logiques reste net sur tous les
/// appareils.
class _DiagonalLinePainter extends CustomPainter {
  final bool splitRightTriangle;
  const _DiagonalLinePainter({this.splitRightTriangle = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.lightGrey
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
    if (splitRightTriangle) {
      canvas.drawLine(
        Offset(size.width / 2, size.height / 2),
        Offset(size.width, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DiagonalLinePainter oldDelegate) =>
      oldDelegate.splitRightTriangle != splitRightTriangle;
}

/// Répartit une ou plusieurs icônes de part et d'autre de la diagonale
/// dessinée par [_DiagonalLinePainter] (coin haut-droite → coin
/// bas-gauche), plutôt que de les centrer côte à côte (évite que deux
/// icônes se chevauchent visuellement pour un jour avec 2 occurrences, par
/// exemple un Rekovery et un duo le même jour).
///
/// **Important (correction du 10 août 2026, signalée par Margaux)** : les
/// icônes elles-mêmes ne se placent PAS aux mêmes coins que les
/// extrémités du trait (haut-droite/bas-gauche) — elles se chevaucheraient
/// alors avec le trait, puisqu'elles seraient positionnées pile sur ses
/// points de départ/arrivée. Elles se placent plutôt dans les deux moitiés
/// (triangles) que le trait délimite : coin haut-GAUCHE pour la première,
/// coin bas-DROIT pour la seconde — bien de chaque côté de la diagonale,
/// jamais dessus. Ce sont ces mêmes 2 coins que reprend
/// [_SplitSquarePainter] pour colorer chaque triangle.
///
/// - 1 icône : centrée (aucune diagonale à faire apparaître — pas utilisé
///   en pratique depuis `_DaySquare`, qui gère ce cas séparément, mais
///   conservé pour la robustesse du widget).
/// - 2 icônes : une dans chaque grand triangle opposé (coin haut-GAUCHE /
///   coin bas-DROIT).
/// - 3 icônes (11 août 2026, demande de Margaux) : une par triangle — le
///   grand triangle garde son icône au coin haut-GAUCHE (inchangé). Les 2
///   petits triangles avaient d'abord chacun leur icône au centre de
///   gravité géométrique exact de leur triangle, mais Margaux a trouvé ça
///   trop proche du sommet commun aux 2 petits triangles (le centre du
///   carré, où les 2 traits se rejoignent) — corrigé le même jour :
///   l'icône du petit triangle haut-droit est désormais au milieu du bord
///   DROIT du carré (`Alignment.centerRight`, décalée vers la droite),
///   celle du petit triangle bas au milieu du bord BAS
///   (`Alignment.bottomCenter`, décalée vers le bas) — ces 2 bords
///   appartiennent chacun entièrement à leur petit triangle respectif
///   (voir [_SplitSquarePainter]), donc l'icône reste bien à l'intérieur,
///   loin du sommet central ET du trait diagonal principal.
/// - 4+ icônes (extrêmement rare, pas de triangle dédié au-delà de 3 pour
///   l'instant, voir [_SplitSquarePainter]) : réparties à intervalles
///   réguliers le long de l'axe haut-gauche → bas-droit, comme avant le 11
///   août 2026 (repli de sécurité, non demandé explicitement).
class _DiagonalIcons extends StatelessWidget {
  final List<Widget> icons;
  const _DiagonalIcons({required this.icons});

  static const _threeIconAlignments = [
    Alignment.topLeft, // grand triangle : inchangé
    Alignment.centerRight, // petit triangle haut-droit : décalé vers la droite
    Alignment.bottomCenter, // petit triangle bas : décalé vers le bas
  ];

  @override
  Widget build(BuildContext context) {
    if (icons.isEmpty) return const SizedBox.shrink();
    if (icons.length == 1) return Center(child: icons.single);

    final alignments = icons.length == 3
        ? _threeIconAlignments
        : [
            for (var i = 0; i < icons.length; i++)
              Alignment.lerp(Alignment.topLeft, Alignment.bottomRight, i / (icons.length - 1))!,
          ];

    return Stack(
      children: [
        for (var i = 0; i < icons.length; i++) Align(alignment: alignments[i], child: icons[i]),
      ],
    );
  }
}

class _FormulaMiniIcon extends StatelessWidget {
  final String formula;
  // Taille passée par `_DaySquare.build` (20 par défaut, réduite à 14 à
  // partir de 3 occurrences le même jour depuis le 11 août 2026 — voir
  // le commentaire dédié là-bas).
  final double size;
  const _FormulaMiniIcon({required this.formula, required this.size});

  @override
  Widget build(BuildContext context) {
    switch (formula) {
      case 'duo':
        return Icon(Icons.people, color: AppColors.white, size: size);
      case 'individuel':
        return Icon(Icons.person, color: AppColors.white, size: size);
      case 'rekovery':
        return SvgPicture.asset(
          'assets/thermometer.svg',
          width: size,
          height: size,
          colorFilter: const ColorFilter.mode(AppColors.white, BlendMode.srcIn),
        );
      default: // 'collectif'
        return Icon(Icons.groups, color: AppColors.white, size: size);
    }
  }
}
