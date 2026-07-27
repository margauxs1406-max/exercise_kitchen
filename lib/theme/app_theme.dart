import 'package:flutter/material.dart';

import 'responsive.dart';

/// Palette graphique provisoire — section 7 des spécifications techniques.
/// À remplacer dès réception de la charte graphique officielle du gérant.
class AppColors {
  AppColors._();

  static const Color black = Color(0xFF222222); // Fond du logo, textes principaux
  static const Color white = Color(0xFFFFFFFF); // Fonds clairs, textes sur fond noir
  static const Color lightGrey = Color(0xFFF2F2F2); // Fonds de sections, cartes
  static const Color mediumGrey = Color(0xFF8C8C8C); // Textes secondaires, bordures
  static const Color orange = Color(0xFFFF6B35); // CTA, badges, alertes importantes
  static const Color flashyGreen = Color(0xFF41D952); // Statut "Actif" (texte + coche)
  static const Color mustardYellow = Color(0xFFCFB93B); // Statut "En attente" (texte + icône)
  static const Color darkGrey = Color(0xFF5C5C5C); // Statut "Clôturé" (texte + croix), sans fond ni contour
}

class AppTheme {
  AppTheme._();

  // Section design (21 juillet 2026) : police appliquée aux titres de
  // pop-up, titres de page et en-tête — SEUL endroit (avec `pubspec.yaml`,
  // où la famille de police est déclarée avec ses fichiers) à modifier pour
  // changer de police plus tard. `titleTextStyle` (ci-dessous, pour
  // `appBarTheme`/`dialogTheme`) ET `headerTitleStyle` (utilisé directement
  // par les 4 écrans avec un en-tête personnalisé — voir sa doc) lisent
  // tous les deux cette constante, donc rien d'autre à toucher ailleurs.
  static const String titleFontFamily = 'Poppins';

  /// Resserrement de l'espacement entre les lettres des titres (police
  /// Poppins), nouveau, 26 juillet 2026, à la demande de Margaux : -5% de
  /// la taille de police du titre. Appliqué uniquement via
  /// `appBarTheme.titleTextStyle`/`dialogTheme.titleTextStyle` ci-dessous
  /// (pas sur [headerTitleStyle] directement, qui n'a pas de `fontSize`
  /// propre) — `headerTitleStyle` hérite quand même de ce réglage car
  /// Flutter fusionne un `TextStyle` avec le style ambiant de l'`AppBar`
  /// (issu de `appBarTheme.titleTextStyle`) pour tout champ qu'il ne fixe
  /// pas lui-même, dont `letterSpacing`.
  static double titleLetterSpacing(double fontSize) => fontSize * -0.05;

  /// Style de texte du contenu de l'en-tête ([WeekHeader.weekTypeContent] —
  /// type de semaine, "Galerie", "Adhérent"). Ce contenu n'est pas un
  /// `AppBar(title: Text(...))` "classique" : chaque écran qui l'utilise
  /// fixe sa propre couleur/graisse (blanc, gras, sur fond noir) au lieu
  /// d'hériter du thème — voir `weekly_planning_screen.dart`,
  /// `progress_gallery_screen.dart`, `manage_planning_screen.dart` (menu
  /// déroulant coach) et `coach_home_screen.dart`, qui utilisent tous cette
  /// constante plutôt que de répéter `fontFamily`/`fontWeight` en dur.
  static const TextStyle headerTitleStyle = TextStyle(
    fontFamily: titleFontFamily,
    color: AppColors.white,
    fontWeight: FontWeight.bold,
  );

  /// Section responsive (23 juillet 2026, à la demande de Margaux) : ce
  /// thème dépendait auparavant uniquement de constantes (`AppTheme.light`,
  /// un simple getter) — il prend désormais un [BuildContext] pour pouvoir
  /// calculer les tailles (police, paddings, rayons...) en fonction de la
  /// taille réelle de l'écran via `context.wp`/`hp`/`sp` (voir
  /// `responsive.dart`). Appelé depuis `app.dart` (`AppTheme.light(context)`),
  /// où `context` provient du `Builder` juste au-dessus de `MaterialApp` —
  /// c'est le seul endroit à toucher si la référence de taille d'écran
  /// change un jour.
  static ThemeData light(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.orange,
      primary: AppColors.orange,
      onPrimary: AppColors.white,
      secondary: AppColors.black,
      surface: AppColors.white,
      // Désactive la surimpression automatique "surface tint" du Material 3
      // (qui teinte légèrement toute surface élevée — Card, AppBar,
      // NavigationBar, boutons custom... — avec la couleur primaire, ici
      // orange). Sans ça, des éléments censés être blancs apparaissent
      // légèrement orangés dès qu'ils ont de l'élévation.
      surfaceTint: Colors.transparent,
      // `surfaceTint: Colors.transparent` ci-dessus ne suffit pas à lui
      // seul : il désactive la surimpression liée à l'élévation, mais pas
      // la couleur de base des rôles "surfaceContainer*" eux-mêmes, que
      // `ColorScheme.fromSeed` dérive normalement de la teinte du thème
      // (ici orange) — et ce sont justement CES rôles que Material 3
      // utilise par défaut comme fond pour `Dialog`/`AlertDialog`,
      // `PopupMenuButton`/`showMenu`, `DropdownMenu`, `BottomSheet`... Sans
      // les forcer explicitement en blanc ici, chacun de ces composants
      // réapparaît légèrement orange pâle un par un à chaque fois qu'on en
      // ajoute un nouveau — d'où ce réglage global, une fois pour toutes.
      surfaceContainerLowest: AppColors.white,
      surfaceContainerLow: AppColors.white,
      surfaceContainer: AppColors.white,
      surfaceContainerHigh: AppColors.white,
      surfaceContainerHighest: AppColors.white,
      outline: AppColors.mediumGrey,
      outlineVariant: AppColors.lightGrey,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.lightGrey,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        // Section design (21 juillet 2026) : police du logo (Poppins,
        // graisse Bold) sur tous les titres de page — couvre à la fois les
        // `AppBar(title: Text(...))` "classiques" (Profil, FAQ, Fiche
        // adhérent...) ET le contenu de [WeekHeader] (logo + type de
        // semaine/"Galerie"/"Adhérent"), qui est lui-même construit à partir
        // d'un `AppBar` — mais pour ce dernier, chaque écran fixe déjà sa
        // propre couleur/graisse en dur sur son `Text` (voir
        // `weekly_planning_screen.dart` etc.), donc `fontFamily` a été
        // explicitement répété là-bas plutôt que de compter sur l'héritage
        // ambigu d'un `DefaultTextStyle`.
        titleTextStyle: TextStyle(
          fontFamily: titleFontFamily,
          fontWeight: FontWeight.bold,
          fontSize: context.sp(20),
          letterSpacing: titleLetterSpacing(context.sp(20)),
          color: AppColors.white,
        ),
      ),
      // Fond blanc explicite (et pas seulement hérité de
      // `surfaceContainerHigh` ci-dessus) pour toute pop-up `AlertDialog`/
      // `Dialog` ouverte dans l'app (ex. `SlotRosterDialog`).
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        // Section design (21 juillet 2026) : idem, Poppins Bold pour le
        // titre de toutes les pop-up (`AlertDialog`) — aucune ne fixe son
        // propre style de titre dans le code actuel, donc ce réglage
        // s'applique partout automatiquement.
        titleTextStyle: TextStyle(
          fontFamily: titleFontFamily,
          fontWeight: FontWeight.bold,
          fontSize: context.sp(20),
          letterSpacing: titleLetterSpacing(context.sp(20)),
          color: AppColors.black,
        ),
      ),
      // Même chose pour les menus contextuels (`PopupMenuButton`,
      // `showMenu` — utilisé par `_AdherentPicker` dans
      // `add_course_screen.dart`) et les menus déroulants (`DropdownMenu`,
      // `MenuAnchor`), au cas où l'un ou l'autre serait utilisé de nouveau
      // sans qu'on pense à repréciser `color`/`surfaceTintColor` à la main.
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.white),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
      ),
      // Barre de navigation basse (Planning / Adhérents côté coach,
      // Planning / Photos côté adhérent) : fond noir, pas de pastille
      // indicatrice colorée derrière l'onglet actif (supprimée — c'était le
      // rectangle arrondi orangé) ; à la place, l'onglet actif est en blanc
      // 100% opaque, les autres en blanc légèrement transparent.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.black,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: AppColors.white
                .withValues(alpha: states.contains(WidgetState.selected) ? 1.0 : 0.6),
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: AppColors.white
                .withValues(alpha: states.contains(WidgetState.selected) ? 1.0 : 0.6),
            fontSize: context.sp(12),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: AppColors.white,
          padding: EdgeInsets.symmetric(horizontal: context.wp(24), vertical: context.hp(14)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.wp(10))),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.black),
      ),
      cardTheme: CardThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.wp(14))),
        margin: EdgeInsets.symmetric(vertical: context.hp(6), horizontal: 0),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.wp(10)),
          borderSide: const BorderSide(color: AppColors.mediumGrey),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(14)),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontWeight: FontWeight.bold, color: AppColors.black),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, color: AppColors.black),
        bodyMedium: TextStyle(color: AppColors.black),
        bodySmall: TextStyle(color: AppColors.mediumGrey),
      ),
    );
  }
}
