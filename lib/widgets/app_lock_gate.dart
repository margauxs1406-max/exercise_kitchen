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
///   `adherent_profile_screen.dart`) → prompt biométrique, à chaque
///   lancement "à froid" du processus (app réellement fermée, ou tuée par
///   l'OS, puis rouverte) — jamais lors d'un simple passage en arrière-plan
///   suivi d'un retour au premier plan. Mécanisme géré par [_unlockedThisLaunch],
///   une variable STATIQUE en mémoire (jamais persistée sur disque), qui ne
///   repart à `false` que lorsque le processus redémarre.
/// - sinon → **aucun verrou** (depuis le 6 août 2026, demande explicite de
///   Margaux) : une fois connecté.e une première fois, l'adhérent reste
///   connecté indéfiniment (fermeture complète de l'app, arrière-plan,
///   redémarrage du téléphone...), jusqu'à une déconnexion manuelle — la
///   persistance native de Firebase Auth s'applique donc sans restriction
///   supplémentaire. **Avant ce changement**, une session restaurée
///   automatiquement par Firebase au lancement (sans nouvel appel explicite
///   à `AuthService.signIn`) déclenchait une déconnexion forcée pour
///   ramener vers `LoginScreen` — ce mécanisme a été retiré : ni l'app
///   Flutter ni Firebase Auth ne peuvent distinguer de façon fiable "l'app a
///   été fermée" de "le téléphone a redémarré" (les deux se traduisent par
///   un processus qui repart de zéro), donc il n'existait aucun moyen de
///   forcer la reconnexion UNIQUEMENT après un redémarrage du téléphone sans
///   la forcer aussi après une simple fermeture — ce qui aurait recréé
///   exactement le problème que Margaux voulait résoudre.
class AppLockGate extends StatefulWidget {
  final UserModel user;
  final Widget child;
  const AppLockGate({super.key, required this.user, required this.child});

  /// Permet à un autre écran (typiquement `LoginScreen` ou
  /// `ColdStartReloginScreen`, juste après une reconnexion silencieuse
  /// réussie protégée par sa propre biométrie — voir `credential_store.dart`)
  /// de signaler que la biométrie vient déjà d'être validée pour ce
  /// lancement de l'app. Sans cet appel, `AppLockGate` redéclencherait un
  /// second prompt biométrique immédiatement après, ce qui serait redondant
  /// et déroutant (27 août 2026).
  static void markUnlockedThisLaunch() {
    _AppLockGateState._unlockedThisLaunch = true;
  }

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
    if (widget.user.biometricUnlockEnabled && !_unlockedThisLaunch) {
      // Déclenche le prompt automatiquement dès l'affichage de l'écran de
      // verrouillage, sans attendre un appui sur "Déverrouiller".
      WidgetsBinding.instance.addPostFrameCallback((_) => _attemptUnlock());
    }
    // Pas de biométrie activée : aucun verrou (voir doc de classe ci-dessus,
    // mise à jour du 6 août 2026) — on laisse simplement passer.
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
                  // Poppins ajouté le 22 août 2026 (rationalisation des
                  // polices, demande de Margaux) : seul titre plein écran de
                  // l'app à ne pas utiliser la police des titres — taille
                  // sp(18) volontairement conservée (compacte pour cet
                  // écran), voir `audit_polices.md`.
                  style: TextStyle(
                    fontFamily: AppTheme.titleFontFamily,
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
