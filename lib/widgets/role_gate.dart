import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../screens/auth/change_password_screen.dart';
import '../screens/auth/consent_screen.dart';
import '../screens/coach/coach_home_screen.dart';
import '../screens/adherent/adherent_home_screen.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import 'app_lock_gate.dart';
import 'cold_start_relogin_screen.dart';

/// Point d'entrée unique de navigation : redirige vers le bon écran selon
/// l'état d'authentification et le parcours "compte fermé" (section 3) :
/// non connecté → connexion ; première connexion → changement de mot de
/// passe ; consentement non donné → écran RGPD ; sinon → espace coach ou
/// adhérent selon le rôle.
///
/// Enregistre aussi le token de notifications push (voir
/// `push_notification_service.dart`) dès que la personne atteint cet état
/// "pleinement connectée" — une seule fois par session (voir
/// [_tokenRegisteredForUid]).
class RoleGate extends StatefulWidget {
  const RoleGate({super.key});

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  String? _tokenRegisteredForUid;

  void _maybeRegisterPushToken(String uid) {
    if (_tokenRegisteredForUid == uid) return;
    _tokenRegisteredForUid = uid;
    context.read<PushNotificationService>().registerForUser(uid);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (auth.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!auth.isSignedIn) {
      // 27 août 2026 : `ColdStartReloginScreen` tente d'abord une
      // reconnexion silencieuse via des identifiants biométriques stockés
      // (contournement d'un bug Firebase Auth Android, voir sa doc de
      // classe) et retombe sur `LoginScreen` si rien à tenter — donc aucun
      // changement de comportement pour qui n'utilise pas la biométrie.
      return const ColdStartReloginScreen();
    }

    final user = auth.currentUser;
    if (user == null) {
      // Le document Firestore n'existe pas encore (latence juste après
      // création du compte) ou le compte est clôturé.
      return const Scaffold(
        backgroundColor: AppColors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Verrou biométrique (switch du profil adhérent) : posé ici, avant même
    // le changement de mot de passe / consentement, pour couvrir tout
    // l'espace connecté. `Builder` garde le contenu réel (et donc
    // `_maybeRegisterPushToken`) paresseux : il n'est construit que si
    // `AppLockGate` décide d'afficher `child` (donc jamais tant que l'app
    // reste verrouillée).
    return AppLockGate(
      user: user,
      child: Builder(
        builder: (context) {
          if (user.needsPasswordChange) {
            return const ChangePasswordScreen();
          }

          if (!user.consentAccepted) {
            return const ConsentScreen();
          }

          _maybeRegisterPushToken(user.uid);

          return user.role == UserRole.coach
              ? const CoachHomeScreen()
              : const AdherentHomeScreen();
        },
      ),
    );
  }
}
