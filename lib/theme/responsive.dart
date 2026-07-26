import 'package:flutter/material.dart';

/// Système de dimensionnement "responsive" — nouveau, 23 juillet 2026, à la
/// demande explicite de Margaux : toutes les tailles en dur du code
/// (paddings, écarts entre éléments, rayons d'arrondi, tailles d'icônes,
/// tailles de police...) doivent désormais être exprimées en pourcentage de
/// la taille d'écran plutôt qu'en pixels logiques fixes, pour garder les
/// mêmes proportions visuelles quelle que soit la taille réelle de l'écran
/// (petit téléphone, grand téléphone, tablette...).
///
/// **Principe** : chaque valeur en dur d'origine (ex. `SizedBox(height: 16)`)
/// a été conçue et testée sur le téléphone de Margaux. On considère que cet
/// écran fait, en pixels logiques Flutter (le "dp" Android), [kBaseWidth] x
/// [kBaseHeight] — voir la note ci-dessous sur ce choix. La valeur en dur
/// est alors réinterprétée comme un pourcentage de cette largeur/hauteur de
/// référence (`16 / kBaseWidth`), et ce même pourcentage est réappliqué à la
/// largeur/hauteur RÉELLE de l'écran à l'exécution (`context.wp(16)` /
/// `context.hp(16)`). Résultat : sur l'écran de référence lui-même, le
/// rendu reste (quasi) identique à avant ; sur un écran plus petit ou plus
/// grand, tout est mis à l'échelle en conservant les proportions entre les
/// éléments.
///
/// **Note sur [kBaseWidth]/[kBaseHeight]** : valeurs approximatives (gabarit
/// Android courant), faute de connaître la résolution logique exacte du
/// téléphone de Margaux au moment de cette conversion. Ce qui compte pour
/// la demande de Margaux ("garder toutes les proportions actuelles") est
/// que TOUT le code utilise la MÊME référence — le choix exact de cette
/// référence ne change que l'échelle globale, pas les proportions relatives
/// entre les éléments. Si un jour un écart perceptible apparaît par rapport
/// au design d'origine sur son téléphone précis, il suffit d'ajuster ces
/// deux constantes (aucun autre fichier à toucher).
const double kBaseWidth = 412;
const double kBaseHeight = 915;

/// Bornes de sécurité pour éviter un texte illisible (trop petit) ou
/// disproportionné (trop grand) sur des écrans très inhabituels (tablette,
/// très petit téléphone) — appliquées uniquement à [ResponsiveSizing.sp].
const double _kMinFontScale = 0.85;
const double _kMaxFontScale = 1.3;

/// Extension centrale : `context.wp(x)` / `context.hp(x)` / `context.sp(x)`
/// remplacent partout une valeur en dur `x` (pixels logiques, pensés pour
/// [kBaseWidth]/[kBaseHeight]) par l'équivalent proportionnel sur l'écran
/// réel. `wp` = pourcentage de largeur (paddings/écarts/rayons horizontaux,
/// icônes, largeurs), `hp` = pourcentage de hauteur (écarts/paddings
/// verticaux, hauteurs), `sp` = taille de police (basée sur la largeur,
/// comportement le plus stable visuellement entre portrait/paysage — avec
/// un plafond/plancher pour rester lisible sur des écrans extrêmes).
extension ResponsiveSizing on BuildContext {
  Size get _screenSize => MediaQuery.sizeOf(this);

  /// Pourcentage de largeur : `designPixels` était pensé pour une largeur de
  /// référence [kBaseWidth] ; retourne l'équivalent sur la largeur réelle.
  double wp(double designPixels) => designPixels / kBaseWidth * _screenSize.width;

  /// Pourcentage de hauteur : idem, sur la hauteur de référence [kBaseHeight].
  double hp(double designPixels) => designPixels / kBaseHeight * _screenSize.height;

  /// Taille de police responsive, avec bornes de sécurité (voir
  /// [_kMinFontScale]/[_kMaxFontScale]) pour ne jamais devenir illisible ou
  /// disproportionnée sur un écran très inhabituel.
  double sp(double designPixels) {
    final scale = (_screenSize.width / kBaseWidth).clamp(_kMinFontScale, _kMaxFontScale);
    return designPixels * scale;
  }
}
