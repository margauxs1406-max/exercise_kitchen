import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../widgets/labeled_text_field.dart';

/// Étape obligatoire à la toute première connexion (section 3) : l'adhérent
/// (ou le coach) doit définir un mot de passe personnel avant de pouvoir
/// continuer — impossible de conserver le mot de passe temporaire envoyé
/// par email.
///
/// Section 2.1 : même habillage (fond noir) que l'écran de connexion.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;
  String? _error;
  // Masqués par défaut, avec un œil/œil barré pour basculer l'affichage
  // (indépendamment l'un de l'autre) sur chacun des deux champs.
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().completePasswordChange(_newPasswordController.text);
    } catch (e) {
      setState(() => _error = "Impossible de mettre à jour le mot de passe : $e");
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(title: Text('Première connexion'.toUpperCase())),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: context.wp(24), vertical: context.hp(24)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.wp(420)),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Pour des raisons de sécurité, choisis un mot de passe '
                    'personnel avant de continuer.',
                    style: TextStyle(color: AppColors.white),
                  ),
                  SizedBox(height: context.hp(24)),
                  LabeledTextField(
                    label: 'Nouveau mot de passe',
                    controller: _newPasswordController,
                    obscureText: _obscureNew,
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                    validator: (v) => (v == null || v.length < 8)
                        ? 'Au moins 8 caractères'
                        : null,
                  ),
                  SizedBox(height: context.hp(16)),
                  LabeledTextField(
                    label: 'Confirme le mot de passe',
                    controller: _confirmController,
                    obscureText: _obscureConfirm,
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    validator: (v) => v != _newPasswordController.text
                        ? 'Les mots de passe ne correspondent pas'
                        : null,
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
                        : const Text('Valider'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
