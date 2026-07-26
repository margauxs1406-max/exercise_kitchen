import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/user_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import 'faq_screen.dart';
import 'notification_settings_screen.dart';
import 'privacy_policy_screen.dart';

/// Écran de profil adhérent (nouveau), ouvert depuis le bouton "profil" de
/// l'en-tête ([WeekHeader.onProfileTap]) à la place de l'ancienne
/// déconnexion directe — celle-ci se fait maintenant depuis cet écran
/// (bouton texte orange souligné, en bas de page).
///
/// Contient : les données personnelles (lecture seule, sauf mot de passe et
/// déverrouillage biométrique), et trois sous-menus (Notifications,
/// Confidentialité, FAQ).
class AdherentProfileScreen extends StatelessWidget {
  const AdherentProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserRepository>();
    final auth = context.read<AuthService>();
    final uid = context.watch<AuthService>().currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text('Profil'.toUpperCase())),
      body: StreamBuilder<UserModel?>(
        stream: repo.watchUser(uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = snapshot.data;
          if (user == null) {
            return const Center(child: Text('Profil introuvable.'));
          }
          return _ProfileBody(repo: repo, auth: auth, user: user);
        },
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final UserRepository repo;
  final AuthService auth;
  final UserModel user;
  const _ProfileBody({required this.repo, required this.auth, required this.user});

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: Text('Se déconnecter ?'.toUpperCase()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed == true) await auth.signOut();
  }

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe modifié.')),
      );
    }
  }

  /// Avant d'activer le switch, on vérifie que l'appareil supporte bien la
  /// biométrie ET qu'une authentification réussit réellement — sinon on
  /// n'active jamais le réglage, pour ne pas risquer de verrouiller
  /// définitivement la personne hors de l'app (`AppLockGate`) avec un
  /// capteur absent ou mal configuré. La désactivation, elle, ne nécessite
  /// aucune vérification.
  Future<void> _onBiometricSwitchChanged(BuildContext context, bool enabled) async {
    if (!enabled) {
      await repo.updateBiometricUnlockEnabled(user.uid, false);
      return;
    }
    final biometric = BiometricAuthService();
    final supported = await biometric.isSupported;
    if (!supported) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Ton appareil ne permet pas le déverrouillage biométrique "
              "(empreinte / Face ID non configuré(e) dans ses réglages).",
            ),
          ),
        );
      }
      return;
    }
    final ok = await biometric.authenticate();
    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Authentification annulée — le déverrouillage n'a pas été activé."),
          ),
        );
      }
      return;
    }
    await repo.updateBiometricUnlockEnabled(user.uid, true);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(16)),
      children: [
        Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Données personnelles', style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: context.hp(12)),
                _InfoLine(icon: Icons.person_outline, label: user.fullName),
                SizedBox(height: context.hp(10)),
                _InfoLine(icon: Icons.email_outlined, label: user.email),
                SizedBox(height: context.hp(10)),
                _InfoLine(
                  icon: Icons.phone_outlined,
                  label: (user.phone == null || user.phone!.isEmpty)
                      ? 'Téléphone non renseigné'
                      : user.phone!,
                ),
                SizedBox(height: context.hp(10)),
                Row(
                  children: [
                    Icon(Icons.lock_outline, size: _kIconSize(context), color: AppColors.orange),
                    SizedBox(width: context.wp(8)),
                    // Un mot de passe existant ne peut techniquement jamais
                    // être affiché en clair (Firebase ne le stocke ni ne le
                    // renvoie jamais) — seul un remplacement est possible,
                    // via le bouton "Modifier" ci-contre.
                    Expanded(child: Text('••••••••', style: TextStyle(fontSize: _kTextSize(context)))),
                    TextButton(
                      onPressed: () => _showChangePasswordDialog(context),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.orange,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const _UnderlinedOrangeText('Modifier'),
                    ),
                  ],
                ),
                Divider(height: context.hp(24)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.orange,
                  title: const Text('Déverrouillage biométrique'),
                  // Verrouille l'app (voir `AppLockGate`) à chaque lancement
                  // "à froid" (app fermée puis rouverte) — pas de nouvelle
                  // authentification requise pour un simple retour au
                  // premier plan depuis l'arrière-plan.
                  subtitle: const Text(
                    "Face ID / empreinte requis pour ouvrir l'application "
                    "après une fermeture complète.",
                  ),
                  value: user.biometricUnlockEnabled,
                  onChanged: (v) => _onBiometricSwitchChanged(context, v),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: context.hp(8)),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.notifications_outlined,
                    size: _kIconSize(context), color: AppColors.orange),
                title: Text('Notifications', style: TextStyle(fontSize: _kTextSize(context))),
                trailing: const Icon(Icons.chevron_right, color: AppColors.orange),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NotificationSettingsScreen(uid: user.uid),
                  ),
                ),
              ),
              Divider(height: context.hp(1)),
              ListTile(
                leading: Icon(Icons.privacy_tip_outlined,
                    size: _kIconSize(context), color: AppColors.orange),
                title: Text('Confidentialité', style: TextStyle(fontSize: _kTextSize(context))),
                trailing: const Icon(Icons.chevron_right, color: AppColors.orange),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                ),
              ),
              Divider(height: context.hp(1)),
              ListTile(
                leading: Icon(Icons.help_outline,
                    size: _kIconSize(context), color: AppColors.orange),
                title: Text('FAQ', style: TextStyle(fontSize: _kTextSize(context))),
                trailing: const Icon(Icons.chevron_right, color: AppColors.orange),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FaqScreen()),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: context.hp(32)),
        Center(
          child: GestureDetector(
            onTap: () => _signOut(context),
            behavior: HitTestBehavior.opaque,
            child: const _UnderlinedOrangeText(
              'Se déconnecter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(height: context.hp(16)),
      ],
    );
  }
}

// Tailles partagées entre les lignes "Données personnelles" et les
// sous-menus (Notifications / Confidentialité / FAQ) ci-dessus, pour que les
// icônes et le texte soient visuellement homogènes sur toute la page —
// _kIconSize correspond à la taille par défaut des icônes de ListTile (24),
// _kTextSize à la taille par défaut de leur titre (16).
double _kIconSize(BuildContext context) => context.wp(24);
double _kTextSize(BuildContext context) => context.sp(16);

/// Texte orange souligné (soulignement natif) utilisé pour les boutons
/// "Modifier" et "Se déconnecter".
class _UnderlinedOrangeText extends StatelessWidget {
  final String text;
  final FontWeight? fontWeight;
  const _UnderlinedOrangeText(this.text, {this.fontWeight});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: _kTextSize(context),
        color: AppColors.orange,
        fontWeight: fontWeight,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.orange,
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoLine({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: _kIconSize(context), color: AppColors.orange),
        SizedBox(width: context.wp(8)),
        Expanded(child: Text(label, style: TextStyle(fontSize: _kTextSize(context)))),
      ],
    );
  }
}

/// Pop-up de changement de mot de passe — demande le mot de passe actuel
/// (nécessaire pour ré-authentifier, voir `AuthService.changePassword`) en
/// plus du nouveau, avec un œil/œil barré indépendant sur chacun des trois
/// champs (même style que `change_password_screen.dart`).
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error =
          'Impossible de modifier le mot de passe : vérifie ton mot de passe actuel.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: Text('Modifier le mot de passe'.toUpperCase()),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _currentController,
              obscureText: _obscureCurrent,
              decoration: InputDecoration(
                labelText: 'Mot de passe actuel',
                suffixIcon: IconButton(
                  icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
            ),
            SizedBox(height: context.hp(12)),
            TextFormField(
              controller: _newController,
              obscureText: _obscureNew,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
                suffixIcon: IconButton(
                  icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
              validator: (v) =>
                  (v == null || v.length < 8) ? 'Au moins 8 caractères' : null,
            ),
            SizedBox(height: context.hp(12)),
            TextFormField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'Confirme le nouveau mot de passe',
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) =>
                  v != _newController.text ? 'Les mots de passe ne correspondent pas' : null,
            ),
            if (_error != null) ...[
              SizedBox(height: context.hp(12)),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? SizedBox(
                  height: context.hp(18),
                  width: context.wp(18),
                  child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Valider'),
        ),
      ],
    );
  }
}
