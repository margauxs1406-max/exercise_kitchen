import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../widgets/labeled_text_field.dart';

/// Réinitialisation de mot de passe demandée depuis l'écran de connexion
/// (section 1.4). Même habillage visuel (fond noir) que l'écran de
/// première connexion (`change_password_screen.dart`).
///
/// Techniquement, on ne peut pas laisser saisir directement un nouveau mot
/// de passe ici : l'utilisateur n'est pas encore authentifié à ce stade.
/// Firebase envoie donc un email contenant un lien sécurisé, qui ouvre une
/// page (hébergée par Firebase) où le nouveau mot de passe est saisi et
/// confirmé — même principe que l'écran "Première connexion", juste
/// hébergé par Firebase plutôt que par l'app elle-même.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _submitting = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _friendlyMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return "Aucun compte n'est associé à cet email.";
      case 'invalid-email':
        return 'Email invalide.';
      default:
        return "Impossible d'envoyer l'email (${e.code}).";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(title: Text('Mot de passe oublié'.toUpperCase())),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: context.wp(24), vertical: context.hp(24)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.wp(420)),
            child: _sent ? _buildSentState(context) : _buildFormState(context),
          ),
        ),
      ),
    );
  }

  Widget _buildSentState(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mark_email_read, color: AppColors.white, size: context.wp(48)),
        SizedBox(height: context.hp(16)),
        Text(
          'Un email a été envoyé à ${_emailController.text.trim()} avec un '
          'lien pour choisir un nouveau mot de passe.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.white),
        ),
        SizedBox(height: context.hp(24)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Retour à la connexion',
            style: TextStyle(
              color: AppColors.white,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormState(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Indique ton email : nous t'enverrons un lien pour choisir un "
            'nouveau mot de passe.',
            style: TextStyle(color: AppColors.white),
          ),
          SizedBox(height: context.hp(24)),
          LabeledTextField(
            label: 'Email',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v == null || !v.contains('@')) ? 'Email invalide' : null,
          ),
          if (_error != null) ...[
            SizedBox(height: context.hp(12)),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          SizedBox(height: context.hp(24)),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? SizedBox(
                    height: context.hp(20),
                    width: context.wp(20),
                    child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Envoyer le lien'),
          ),
        ],
      ),
    );
  }
}
