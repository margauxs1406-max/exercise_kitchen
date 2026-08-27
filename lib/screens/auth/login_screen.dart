import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/credential_store.dart';
import '../../services/user_repository.dart';
import '../../widgets/app_lock_gate.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../widgets/labeled_text_field.dart';
import '../../widgets/underlined_link.dart';
import 'forgot_password_screen.dart';

/// Clé utilisée pour mémoriser le dernier email de connexion sur l'appareil
/// (se reconnecter plus vite, sans ressaisir l'email à chaque fois). Aucune
/// donnée sensible (mot de passe) n'est jamais mémorisée de cette façon.
const _kRememberedEmailKey = 'remembered_email';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _credentialStore = CredentialStore();
  bool _submitting = false;
  bool _settingUpBiometric = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kRememberedEmailKey);
    if (saved != null && mounted) {
      setState(() => _emailController.text = saved);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    // Récupérés avant le premier `await` (plutôt qu'après, via `context.read`
    // dans le corps de la fonction) : évite d'utiliser le `BuildContext` de
    // cet écran après un "trou" asynchrone pendant lequel il pourrait avoir
    // disparu (voir lint `use_build_context_synchronously`) — ces deux
    // services restent de toute façon valables même si l'écran disparaît en
    // cours de route (voir commentaire de [_useBiometricWithTypedPassword]
    // ci-dessous pour le même raisonnement).
    final authService = context.read<AuthService>();
    final userRepo = context.read<UserRepository>();
    try {
      await authService.signIn(email: email, password: password);
      // Connexion réussie : on mémorise l'email pour la prochaine fois.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRememberedEmailKey, email);
      // 27 août 2026 : si la biométrie est déjà activée sur ce compte (par
      // exemple après que les identifiants stockés ont été effacés suite à
      // un changement de mot de passe — voir `CredentialStore`), une
      // connexion classique par mot de passe les réarme silencieusement,
      // sans prompt biométrique supplémentaire puisque le mot de passe vient
      // déjà d'être vérifié par Firebase. Non bloquant si ça échoue : au
      // pire il suffira de retaper une fois sur "Utiliser la biométrie".
      try {
        final uid = authService.firebaseUser?.uid;
        if (uid != null) {
          final user = await userRepo.watchUser(uid).first;
          if (user != null && user.biometricUnlockEnabled) {
            await _credentialStore.save(email: email, password: password);
          }
        }
      } catch (_) {
        // Voir commentaire ci-dessus : pas bloquant.
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Bouton "Utiliser la biométrie" (27 juillet 2026, renommé et complété le
  /// 27 août 2026 à la demande de Margaux) : surtout utile sur Android, où —
  /// contrairement à iPhone — rien n'invite spontanément l'adhérent à
  /// enregistrer la biométrie après sa première connexion. Sans ce bouton,
  /// la seule façon d'activer le déverrouillage biométrique est de creuser
  /// jusqu'au profil adhérent une fois connecté(e) — beaucoup ne le trouvent
  /// jamais et retapent leur mot de passe à chaque lancement (voir
  /// `AppLockGate`).
  ///
  /// Deux cas, selon que le champ mot de passe est rempli ou non — voir
  /// [_useBiometricWithTypedPassword] et [_useBiometricWithStoredCredentials]
  /// ci-dessous pour le détail de chacun. Seul le champ email est requis
  /// dans les deux cas.
  Future<void> _useBiometric() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Email invalide');
      return;
    }
    if (_passwordController.text.isEmpty) {
      await _useBiometricWithStoredCredentials(email);
    } else {
      await _useBiometricWithTypedPassword(email);
    }
  }

  /// Cas "mot de passe renseigné" : comportement historique du bouton
  /// (27 juillet 2026) — se connecte normalement avec le mot de passe tapé,
  /// déclenche le prompt biométrique natif, puis enregistre
  /// `biometricUnlockEnabled = true` sur le compte ET les identifiants
  /// (email + mot de passe) de façon chiffrée sur l'appareil (voir
  /// `credential_store.dart`) — c'est cette étape qui permet ensuite les
  /// reconnexions silencieuses (voir `ColdStartReloginScreen`) et le second
  /// cas ci-dessous. La connexion elle-même ne dépend pas de la réussite de
  /// la biométrie : si l'appareil ne la supporte pas, ou si la personne
  /// annule le prompt, elle reste connectée normalement (juste sans le
  /// déverrouillage biométrique activé) plutôt que de tout annuler.
  ///
  /// Aucun `setState` n'est bloqué par le fait que cet écran peut disparaître
  /// en cours de route (dès la connexion, `RoleGate` bascule immédiatement
  /// vers l'écran suivant) : chaque mise à jour d'état est protégée par
  /// `mounted`, mais l'appel Firestore lui-même continue et aboutit même si
  /// ce widget n'est plus affiché.
  Future<void> _useBiometricWithTypedPassword(String email) async {
    setState(() {
      _settingUpBiometric = true;
      _error = null;
    });
    final password = _passwordController.text;
    final biometric = BiometricAuthService();
    // Récupérés avant le premier `await` — voir le commentaire équivalent
    // dans `_submit` ci-dessus.
    final authService = context.read<AuthService>();
    final userRepo = context.read<UserRepository>();
    try {
      final supported = await biometric.isSupported;
      if (!supported) {
        if (mounted) {
          setState(() => _error =
              "La biométrie n'est pas disponible sur cet appareil (empreinte / Face ID non configuré.e dans les réglages).");
        }
        return;
      }

      await authService.signIn(email: email, password: password);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRememberedEmailKey, email);

      final authenticated = await biometric.authenticate();
      if (!authenticated) {
        if (mounted) {
          setState(() => _error =
              "Tu es connecté.e, mais la biométrie n'a pas été activée (annulée ou impossible) — tu peux réessayer depuis ton profil.");
        }
        return;
      }

      final uid = authService.firebaseUser?.uid;
      if (uid != null) {
        await userRepo.updateBiometricUnlockEnabled(uid, true);
      }
      await _credentialStore.save(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _friendlyMessage(e));
    } catch (e) {
      if (mounted) setState(() => _error = "Impossible d'activer la biométrie : $e");
    } finally {
      if (mounted) setState(() => _settingUpBiometric = false);
    }
  }

  /// Cas "mot de passe laissé vide" (27 août 2026, à la demande de Margaux :
  /// "le bouton [...] doit marcher, même si le mot de passe n'est pas
  /// renseigné") : utilise les identifiants enregistrés lors d'une
  /// précédente activation réussie (voir [_useBiometricWithTypedPassword]) —
  /// prompt biométrique d'abord, puis connexion silencieuse seulement s'il
  /// réussit. S'il n'y a rien d'enregistré (jamais activé, ou effacé suite à
  /// une déconnexion/désactivation/changement de mot de passe), on l'indique
  /// clairement plutôt que d'échouer sans explication.
  Future<void> _useBiometricWithStoredCredentials(String email) async {
    setState(() {
      _settingUpBiometric = true;
      _error = null;
    });
    final biometric = BiometricAuthService();
    // Récupéré avant le premier `await` — voir le commentaire équivalent
    // dans `_submit` ci-dessus.
    final authService = context.read<AuthService>();
    try {
      final supported = await biometric.isSupported;
      if (!supported) {
        if (mounted) {
          setState(() => _error =
              "La biométrie n'est pas disponible sur cet appareil (empreinte / Face ID non configuré.e dans les réglages).");
        }
        return;
      }

      final stored = await _credentialStore.read();
      if (stored == null) {
        if (mounted) {
          setState(() => _error =
              "Aucune biométrie enregistrée sur cet appareil — connecte-toi une première fois avec ton mot de passe, puis appuie de nouveau ici.");
        }
        return;
      }
      if (stored.email.toLowerCase() != email.toLowerCase()) {
        if (mounted) {
          setState(() => _error =
              "Ces identifiants biométriques correspondent à un autre compte — saisis ton mot de passe.");
        }
        return;
      }

      final authenticated = await biometric.authenticate();
      if (!authenticated) {
        if (mounted) setState(() => _error = 'Authentification annulée ou impossible.');
        return;
      }

      await authService.signIn(email: stored.email, password: stored.password);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRememberedEmailKey, stored.email);
      // Évite un second prompt biométrique immédiat côté `AppLockGate` juste
      // après cet écran (`RoleGate` l'affiche dès la connexion détectée).
      AppLockGate.markUnlockedThisLaunch();
    } on FirebaseAuthException catch (e) {
      // Identifiants stockés devenus invalides (mot de passe changé depuis
      // un autre appareil...) : on les efface pour éviter d'échouer en
      // boucle silencieusement.
      await _credentialStore.clear();
      if (mounted) setState(() => _error = _friendlyMessage(e));
    } catch (e) {
      if (mounted) setState(() => _error = 'Connexion biométrique impossible : $e');
    } finally {
      if (mounted) setState(() => _settingUpBiometric = false);
    }
  }

  String _friendlyMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email ou mot de passe incorrect.';
      case 'user-disabled':
        return 'Ce compte a été clôturé par un coach.';
      case 'too-many-requests':
        return 'Trop de tentatives. Réessaie dans quelques minutes.';
      default:
        return 'Connexion impossible (${e.code}).';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Le clavier réduit la hauteur disponible (`viewInsets.bottom`) : on
    // rétrécit dynamiquement le logo quand il est ouvert, pour que le champ
    // en cours de saisie ET le bouton "Se connecter" restent visibles
    // au-dessus du clavier plutôt que d'être masqués par lui.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      // Section 1.1 : fond noir, même couleur que le fond du logo.
      backgroundColor: AppColors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: context.wp(24), vertical: context.hp(24)),
              child: ConstrainedBox(
                // Force le contenu à occuper au moins toute la hauteur
                // disponible (qui rétrécit quand le clavier s'ouvre, grâce à
                // `resizeToAvoidBottomInset`) : le contenu reste centré tant
                // qu'il tient, et devient scrollable dès qu'il ne tient plus
                // (plutôt que d'être coupé/masqué par le clavier).
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: context.wp(420)),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                                height: keyboardOpen ? context.hp(64) : context.hp(120),
                                alignment: Alignment.center,
                                child: SvgPicture.asset(
                                  'assets/EK.svg',
                                  fit: BoxFit.contain,
                                  // Le SVG est dessiné en noir par défaut :
                                  // on le force en blanc pour qu'il ressorte
                                  // sur le fond noir de cet écran (section
                                  // 1.1).
                                  colorFilter: const ColorFilter.mode(
                                    AppColors.white,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                              // Section 1.2 : phrase d'accroche supprimée.
                              SizedBox(height: context.hp(32)),
                              // Section 1.3 : libellé fixe au-dessus du
                              // champ, plus de label flottant à cheval
                              // entre le champ et le fond noir.
                              LabeledTextField(
                                label: 'Email',
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) => (v == null || !v.contains('@'))
                                    ? 'Email invalide'
                                    : null,
                              ),
                              SizedBox(height: context.hp(16)),
                              LabeledTextField(
                                label: 'Mot de passe',
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscurePassword = !_obscurePassword),
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Mot de passe requis'
                                    : null,
                              ),
                              // Section 1.4 : lien "Mot de passe oublié ?".
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => const ForgotPasswordScreen()),
                                  ),
                                  child: const UnderlinedLink(
                                    'Mot de passe oublié ?',
                                    color: AppColors.white,
                                  ),
                                ),
                              ),
                              if (_error != null) ...[
                                SizedBox(height: context.hp(4)),
                                Text(_error!, style: const TextStyle(color: AppColors.flashyRed)),
                              ],
                              SizedBox(height: context.hp(16)),
                              ElevatedButton(
                                onPressed: (_submitting || _settingUpBiometric) ? null : _submit,
                                child: _submitting
                                    ? SizedBox(
                                        height: context.hp(20),
                                        width: context.wp(20),
                                        child: const CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text('Se connecter'),
                              ),
                              // Section (profil adhérent), bouton ajouté le
                              // 27 juillet 2026, renommé "Utiliser la
                              // biométrie" et complété le 27 août 2026 : voir
                              // `_useBiometric` ci-dessus — fonctionne aussi
                              // mot de passe vide (repli sur les identifiants
                              // enregistrés lors d'une précédente activation).
                              Center(
                                child: TextButton(
                                  onPressed: (_submitting || _settingUpBiometric)
                                      ? null
                                      : _useBiometric,
                                  child: _settingUpBiometric
                                      ? SizedBox(
                                          height: context.hp(16),
                                          width: context.wp(16),
                                          child: const CircularProgressIndicator(
                                              strokeWidth: 2, color: AppColors.white),
                                        )
                                      : const UnderlinedLink(
                                          'Utiliser la biométrie',
                                          color: AppColors.white,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
