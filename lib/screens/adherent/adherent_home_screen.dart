import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/push_notification_service.dart';
import '../../widgets/rekovery_nav_icon.dart';
import 'adherent_rekovery_screen.dart';
import 'progress_gallery_screen.dart';
import 'weekly_planning_screen.dart';

/// Espace adhérent — section 2 des spécifications.
///
/// Bottom bar dynamique selon les formules souscrites (onglet Rekovery,
/// juillet/août 2026) :
/// - Aucune formule "Rekovery" : Photos + Planning, comme avant.
/// - Formule "Rekovery" EN PLUS d'une formule sportive : Photos + Planning +
///   Rekovery (icône thermomètre) — accès illimité, pas de carnet.
/// - "Rekovery seul" (AUCUNE formule sportive, voir
///   `UserModel.isRekoverySoloOnly`) : Rekovery devient le SEUL onglet, la
///   barre de navigation disparaît entièrement — inutile de naviguer vers un
///   planning de cours auxquels cet adhérent ne peut pas s'inscrire.
///
/// Ordre des onglets (demande du 6 août 2026) : Photos à gauche, Planning
/// au milieu (sélectionné par défaut), Rekovery à droite.
class AdherentHomeScreen extends StatefulWidget {
  const AdherentHomeScreen({super.key});

  @override
  State<AdherentHomeScreen> createState() => _AdherentHomeScreenState();
}

class _AdherentHomeScreenState extends State<AdherentHomeScreen> {
  // Ordre Photos / Planning / Rekovery (voir doc de classe) : Planning
  // reste sélectionné par défaut, donc l'index initial est 1, pas 0.
  int _index = 1;

  /// Ajouté le 21 août 2026 (demande de Margaux, points 1 et 2) : ouvre
  /// automatiquement l'onglet Rekovery (ou Planning) quand la personne
  /// appuie sur une notification. Voir `PushNotificationService.
  /// pendingNotificationTarget` pour le détail du mécanisme.
  void _onPendingNotificationTarget() {
    final target =
        context.read<PushNotificationService>().pendingNotificationTarget.value;
    if (target == null) return;
    final user = context.read<AuthService>().currentUser;
    final hasRekovery = user?.formulas.contains('rekovery') ?? false;
    setState(() {
      _index = target == 'rekovery' && hasRekovery ? 2 : 1;
    });
    // Consommé : on remet à `null` pour ne pas re-déclencher la navigation
    // au prochain rebuild (ex. changement d'autre chose dans `AuthService`).
    context.read<PushNotificationService>().pendingNotificationTarget.value = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<PushNotificationService>()
          .pendingNotificationTarget
          .addListener(_onPendingNotificationTarget);
      // Cas où la notification a été tapée AVANT que cet écran n'existe
      // (cold start : `getInitialMessage()` peut avoir résolu avant que ce
      // `initState` ne soit atteint) — on vérifie une fois immédiatement.
      _onPendingNotificationTarget();
    });
  }

  @override
  void dispose() {
    context
        .read<PushNotificationService>()
        .pendingNotificationTarget
        .removeListener(_onPendingNotificationTarget);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final uid = user?.uid;

    // `user` ne peut être `null` que dans le tout premier instant du
    // chargement de la session (voir `AuthService.refreshCurrentUser`) —
    // cet écran n'est de toute façon affiché qu'une fois connecté.
    if (user == null || uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (user.isRekoverySoloOnly) {
      return const Scaffold(body: AdherentRekoveryScreen());
    }

    final hasRekovery = user.formulas.contains('rekovery');
    // Photos à gauche, Planning au milieu (sélectionné par défaut), Rekovery
    // à droite.
    final screens = [
      ProgressGalleryScreen(adherentUid: uid),
      const WeeklyPlanningScreen(),
      if (hasRekovery) const AdherentRekoveryScreen(),
    ];
    // Le bouton flottant du planning et son propre en-tête restent gérés
    // par chaque écran ; on borne l'index affiché au cas où [hasRekovery]
    // change (coach qui retire la formule) pendant que l'onglet Rekovery
    // était sélectionné.
    final safeIndex = _index >= screens.length ? 1 : _index;

    return Scaffold(
      body: IndexedStack(index: safeIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.photo_library), label: 'Photos'),
          const NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Planning'),
          if (hasRekovery)
            NavigationDestination(icon: const RekoveryNavIcon(), label: 'Rekovery'),
        ],
      ),
    );
  }
}
