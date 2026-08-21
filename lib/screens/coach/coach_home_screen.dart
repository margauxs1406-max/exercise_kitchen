import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/push_notification_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rekovery_nav_icon.dart';
import '../../widgets/week_header.dart';
import 'coach_rekovery_screen.dart';
import 'create_adherent_screen.dart';
import 'manage_planning_screen.dart';

/// Espace coach — section 1 des spécifications. Les deux coachs ont les
/// mêmes droits (pas de hiérarchie), donc un seul écran sert les deux.
///
/// Trois onglets, dans l'ordre Adhérents / Planning (par défaut) / Rekovery
/// (demande du 6 août 2026). Planning et Rekovery gèrent chacun leur propre
/// en-tête ([WeekHeader]/[ManagePlanningScreen] pour le second,
/// [CoachRekoveryScreen] pour le troisième) ; seul l'onglet Adhérents
/// utilise l'en-tête externe ci-dessous (logo à gauche, déconnexion à
/// droite, "Adhérent" au centre).
class CoachHomeScreen extends StatefulWidget {
  const CoachHomeScreen({super.key});

  @override
  State<CoachHomeScreen> createState() => _CoachHomeScreenState();
}

class _CoachHomeScreenState extends State<CoachHomeScreen> {
  // Planning (index 1) reste sélectionné par défaut.
  int _index = 1;

  /// Ajouté le 21 août 2026 (demande de Margaux, points 1 et 2) : ouvre
  /// automatiquement l'onglet Rekovery (toujours présent côté coach, index
  /// 2) ou Planning quand la personne appuie sur une notification. Voir
  /// `PushNotificationService.pendingNotificationTarget` pour le détail du
  /// mécanisme.
  void _onPendingNotificationTarget() {
    final target =
        context.read<PushNotificationService>().pendingNotificationTarget.value;
    if (target == null) return;
    setState(() {
      _index = target == 'rekovery' ? 2 : 1;
    });
    // Consommé : on remet à `null` pour ne pas re-déclencher la navigation
    // au prochain rebuild.
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
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: _index == 0
          ? WeekHeader(
              onLogout: () => auth.signOut(),
              weekTypeContent: Text(
                'Adhérent'.toUpperCase(),
                style: AppTheme.headerTitleStyle,
              ),
            )
          : null,
      body: IndexedStack(
        index: _index,
        children: const [
          CreateAdherentScreen(),
          ManagePlanningScreen(),
          CoachRekoveryScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.people), label: 'Adhérents'),
          const NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Planning'),
          const NavigationDestination(icon: RekoveryNavIcon(), label: 'Rekovery'),
        ],
      ),
    );
  }
}
