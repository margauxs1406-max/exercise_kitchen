import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/auth/login_screen.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/credential_store.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import 'app_lock_gate.dart';

/// Contournement d'un bug connu du SDK Firebase Auth Android (27 août 2026,
/// diagnostiqué à partir des tests de Margaux sur Samsung Galaxy S10 : la
/// session survit à un simple passage en arrière-plan, mais est
/// systématiquement perdue après une fermeture complète de l'app —
/// `authStateChanges` émet alors `null` au lancement suivant alors que la
/// personne était bien connectée juste avant. Bug upstream du SDK natif
/// (firebase-android-sdk#8064, non corrigeable côté Flutter — voir
/// FlutterFire#17971, classé "wontfix"), pas une erreur de code de l'app.
///
/// Remplace `LoginScreen` comme écran affiché par `RoleGate` tant que
/// personne n'est connecté. Si des identifiants ont été enregistrés (voir
/// `credential_store.dart` — uniquement après une activation biométrique
/// réussie au moins une fois, jamais à l'aveugle) et que l'appareil supporte
/// la biométrie, tente automatiquement une reconnexion silencieuse protégée
/// par un prompt biométrique dès l'affichage de cet écran — sans jamais
/// redemander le mot de passe. Sinon (rien enregistré, biométrie non
/// supportée, ou tentative annulée/échouée), affiche `LoginScreen` — donc
/// aucune différence visible pour qui n'a jamais activé la biométrie, ni
/// pour une vraie déconnexion manuelle (qui efface toujours les identifiants
/// stockés, voir `AuthService.signOut`).
class ColdStartReloginScreen extends StatefulWidget {
  const ColdStartReloginScreen({super.key});

  @override
  State<ColdStartReloginScreen> createState() => _ColdStartReloginScreenState();
}

class _ColdStartReloginScreenState extends State<ColdStartReloginScreen> {
  final _credentialStore = CredentialStore();
  final _biometric = BiometricAuthService();

  // null = vérification initiale en cours (quasi instantané) ; true = une
  // tentative auto est en cours ou vient d'échouer (cet écran reste
  // affiché, avec un bouton "Réessayer") ; false = rien à tenter (aucun
  // identifiant stocké, biométrie non supportée, ou repli explicite vers la
  // connexion classique) → `LoginScreen`.
  bool? _attempting;
  bool _authenticating = false;
  String? _error;
  StoredCredentials? _stored;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndAttempt());
  }

  Future<void> _checkAndAttempt() async {
    final stored = await _credentialStore.read();
    final supported = stored == null ? false : await _biometric.isSupported;
    if (!mounted) return;
    if (stored == null || !supported) {
      setState(() => _attempting = false);
      return;
    }
    _stored = stored;
    setState(() => _attempting = true);
    await _tryRelogin(stored);
  }

  Future<void> _tryRelogin(StoredCredentials stored) async {
    if (!mounted) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    // Récupéré avant le premier `await` (plutôt qu'après, via
    // `context.read`) : évite d'utiliser le `BuildContext` de cet écran
    // après un "trou" asynchrone pendant lequel il pourrait avoir disparu.
    final authService = context.read<AuthService>();
    try {
      final authenticated = await _biometric.authenticate();
      if (!authenticated) {
        if (mounted) {
          setState(() {
            _authenticating = false;
            _error = 'Authentification annulée ou impossible.';
          });
        }
        return;
      }
      await authService.signIn(email: stored.email, password: stored.password);
      // Évite un second prompt biométrique juste après, côté `AppLockGate`.
      AppLockGate.markUnlockedThisLaunch();
    } on FirebaseAuthException {
      // Identifiants stockés devenus invalides (mot de passe changé depuis
      // un autre appareil, compte clôturé...) : on les efface — il suffira
      // de se reconnecter une fois avec le mot de passe, puis de retaper sur
      // "Utiliser la biométrie" pour réarmer la reconnexion automatique.
      await _credentialStore.clear();
      if (mounted) setState(() => _attempting = false);
      return;
    } catch (e) {
      if (mounted) {
        setState(() {
          _authenticating = false;
          _error = 'Reconnexion impossible : $e';
        });
      }
      return;
    }
    if (mounted) setState(() => _authenticating = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_attempting == null || _attempting == false) {
      return const LoginScreen();
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
                  'Reconnexion en cours',
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
                        onPressed: () {
                          final stored = _stored;
                          if (stored != null) _tryRelogin(stored);
                        },
                        child: const Text('Réessayer'),
                      ),
                SizedBox(height: context.hp(16)),
                TextButton(
                  onPressed: () => setState(() => _attempting = false),
                  child: const Text(
                    'Se connecter avec mon mot de passe',
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
