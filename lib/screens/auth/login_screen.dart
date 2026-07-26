import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../widgets/labeled_text_field.dart';
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
  bool _submitting = false;
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
    try {
      await context.read<AuthService>().signIn(
            email: email,
            password: _passwordController.text,
          );
      // Connexion réussie : on mémorise l'email pour la prochaine fois.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRememberedEmailKey, email);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
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
                                  child: const Text(
                                    'Mot de passe oublié ?',
                                    style: TextStyle(
                                      color: AppColors.white,
                                      decoration: TextDecoration.underline,
                                      decorationColor: AppColors.white,
                                    ),
                                  ),
                                ),
                              ),
                              if (_error != null) ...[
                                SizedBox(height: context.hp(4)),
                                Text(_error!, style: const TextStyle(color: Colors.red)),
                              ],
                              SizedBox(height: context.hp(16)),
                              ElevatedButton(
                                onPressed: _submitting ? null : _submit,
                                child: _submitting
                                    ? SizedBox(
                                        height: context.hp(20),
                                        width: context.wp(20),
                                        child: const CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text('Se connecter'),
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
