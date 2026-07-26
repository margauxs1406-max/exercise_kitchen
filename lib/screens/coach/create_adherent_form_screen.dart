import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/user_repository.dart';
import '../../theme/responsive.dart';

/// Libellés affichés pour chaque formule (section 5) — les clés Firestore
/// restent en minuscules sans accent (`kAllFormulas`), seul l'affichage est
/// francisé/accentué ici.
const Map<String, String> _kFormulaLabels = {
  'collectif': 'Collectif',
  'duo': 'Duo',
  'individuel': 'Individuel',
  'rekovery': 'Rekovery',
};

/// Section 1.1 : formulaire de création d'un compte adhérent — page à part
/// entière (plutôt qu'un panneau repliable directement dans la liste), pour
/// ne pas surcharger l'écran principal du coach. Entièrement scrollable pour
/// s'adapter à n'importe quelle hauteur d'écran/clavier.
class CreateAdherentFormScreen extends StatefulWidget {
  const CreateAdherentFormScreen({super.key});

  @override
  State<CreateAdherentFormScreen> createState() => _CreateAdherentFormScreenState();
}

class _CreateAdherentFormScreenState extends State<CreateAdherentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final Set<String> _selectedFormulas = {};
  bool _submitting = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit(UserRepository repo) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await repo.createAdherentAccount(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        formulas: _selectedFormulas,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Compte créé. Un email avec un mot de passe temporaire a été envoyé.',
        )),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la création du compte : $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserRepository>();
    return Scaffold(
      appBar: AppBar(title: Text('Nouvel adhérent'.toUpperCase())),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(16)),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _firstNameController,
                decoration: const InputDecoration(labelText: 'Prénom'),
                validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
              ),
              SizedBox(height: context.hp(12)),
              TextFormField(
                controller: _lastNameController,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
              ),
              SizedBox(height: context.hp(12)),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Email invalide' : null,
              ),
              SizedBox(height: context.hp(12)),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone (facultatif)',
                  hintText: '+687 XX XX XX',
                ),
              ),
              SizedBox(height: context.hp(20)),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Formules', style: Theme.of(context).textTheme.titleMedium),
              ),
              ...kAllFormulas.map(
                (formula) => CheckboxListTile(
                  value: _selectedFormulas.contains(formula),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _selectedFormulas.add(formula);
                    } else {
                      _selectedFormulas.remove(formula);
                    }
                  }),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  // Réduit la hauteur de chaque ligne (56dp par défaut) et
                  // resserre encore l'espacement vertical intrinsèque du
                  // `ListTile` sous-jacent.
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -4),
                  title: Text(_kFormulaLabels[formula] ?? formula),
                ),
              ),
              SizedBox(height: context.hp(24)),
              ElevatedButton(
                onPressed: _submitting ? null : () => _submit(repo),
                child: _submitting
                    ? SizedBox(
                        height: context.hp(20),
                        width: context.wp(20),
                        child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Créer le compte'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
