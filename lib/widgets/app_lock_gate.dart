import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Verrou d'accès à l'app posé pour tout adhérent (jamais pour un coach —
/// choix explicite de Margaux) :
/// - déverrouillage biométrique activé (switch du profil adhérent,
///   `adherent_profile_screen.dart`) → prompt biométrique ;
/// - sinon → reconnexion complète par mot de passe obligatoire (retour à
///   `LoginScreen`, via une déconnexion forcée déclenchée ici).
///
/// Dans les deux cas, ce verrou ne se déclenche QUE lors d'un lancement "à
/// froid" du processus (app réellement fermée, ou tuée par l'OS, puis
/// rouverte) — jamais lors d'un simple passage en arrière-plan suivi d'un
/// retour au premier plan. Le mécanisme est le même pour les deux : des
/// variables STATIQUES en mémoire (jamais persistées sur disque), qui ne
/// repartent à leur valeur initiale que lorsque le processus redémarre (le
/// processus, et donc ces variables, survivent intacts à un simple passage
/// en arrière-plan).
class AppLockGate extends StatefulWidget {
  final UserModel user;
  final Widget child;
  const AppLockGate({super.key, required this.user, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  static bool _unlockedThisLaunch = false;

  final _biometricAuth = BiometricAuthService();
  bool _authenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.user.biometricUnlockEnabled) {
      if (!_unlockedThisLaunch) {
        // Déclenche le prompt automatiquement dès l'affichage de l'écran de
        // verrouillage, sans attendre un appui sur "Déverrouiller".
        WidgetsBinding.instance.addPostFrameCallback((_) => _attemptUnlock());
      }
    } else if (!widget.user.isCoach) {
      _maybeForceRelogin();
    }
  }

  /// Pas de biométrie activée (et pas un coach) : si la session actuelle
  /// vient d'une restauration automatique de Firebase au lancement — donc
  /// PAS d'un appel explicite à `AuthService.signIn` pendant ce lancement,
  /// voir `hasExplicitlySignedIn` — on déconnecte immédiatement pour forcer
  /// une reconnexion par mot de passe. Si la personne vient au contraire de
  /// se (re)connecter explicitement pendant ce même lancement (juste après
  /// avoir tapé son mot de passe), on ne fait rien : ce n'est pas une
  /// session restaurée, pas besoin de la couper aussitôt.
  void _maybeForceRelogin() {
    final auth = context.read<AuthService>();
    if (!auth.hasExplicitlySignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => auth.signOut());
    }
  }

  Future<void> _attemptUnlock() async {
    if (!mounted || _authenticating) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    final ok = await _biometricAuth.authenticate();
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      if (ok) {
        _unlockedThisLaunch = true;
      } else {
        _error = "Authentification annulée ou impossible.";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (!widget.user.biometricUnlockEnabled &&
        !widget.user.isCoach &&
        !auth.hasExplicitlySignedIn) {
      // Écran neutre le temps que la déconnexion forcée (déclenchée dans
      // `initState`) prenne effet — évite d'afficher, ne serait-ce qu'une
      // frame, le contenu de l'app avant de rediriger vers la connexion.
      return const Scaffold(backgroundColor: AppColors.black, body: SizedBox.shrink());
    }

    if (!widget.user.biometricUnlockEnabled || _unlockedThisLaunch) {
      return widget.child;
    }
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: context.wp(24), vertical: context.hp(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fingerprint, color: AppColors.white, size: context.wp(64)),
                SizedBox(height: context.hp(16)),
                Text(
                  'Déverrouillage requis',
                  style: TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: context.sp(18),
                  ),
                ),
                if (_error != null) ...[
                  SizedBox(height: context.hp(12)),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.orange),
                    textAlign: TextAlign.center,
                  ),
                ],
                SizedBox(height: context.hp(24)),
                _authenticating
                    ? const CircularProgressIndicator(color: AppColors.orange)
                    : FilledButton(
                        onPressed: _attemptUnlock,
                        child: const Text('Déverrouiller'),
                      ),
                SizedBox(height: context.hp(16)),
                // Filet de sécurité : si l'appareil ne peut plus authentifier
                // (capteur défaillant, biométrie désenregistrée...), la
                // personne ne doit jamais rester bloquée définitivement hors
                // de l'app — se déconnecter reste toujours possible et
                // contourne le verrou (on revient à l'écran de connexion).
                TextButton(
                  onPressed: () => context.read<AuthService>().signOut(),
                  child: const Text(
                    'Se déconnecter',
                    style: TextStyle(color: AppColors.mediumGrey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
