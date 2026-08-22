import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/user_repository.dart';
import '../../theme/app_theme.dart';
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
  // Carnet Rekovery initial (section 5, 7 août 2026) — pré-rempli à 10 par
  // défaut, uniquement pertinent pour un adhérent "Rekovery seul" (voir
  // `UserModel.isRekoverySoloOnly`) : un adhérent qui combine Rekovery avec
  // une formule sportive a un accès illimité, sans carnet à gérer (même
  // logique que la fiche adhérent, voir `adherent_detail_screen.dart`).
  final _rekoveryCreditsController = TextEditingController(text: '10');
  final Set<String> _selectedFormulas = {};
  bool _submitting = false;

  bool get _isRekoverySoloOnly =>
      _selectedFormulas.length == 1 && _selectedFormulas.contains('rekovery');

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _rekoveryCreditsController.dispose();
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
        rekoveryCreditsRemaining:
            _isRekoverySoloOnly ? int.tryParse(_rekoveryCreditsController.text.trim()) ?? 10 : null,
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
              // Style aligné sur la fiche adhérent (7 août 2026, demande de
              // Margaux) — fond blanc (carte), case à cocher à contour
              // orange, police agrandie : mêmes réglages que
              // `adherent_detail_screen.dart` pour que les deux écrans soient
              // visuellement identiques.
              Card(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: context.hp(4)),
                  child: Column(
                    children: kAllFormulas
                        .map(
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
                            contentPadding: EdgeInsets.symmetric(horizontal: context.wp(12)),
                            dense: true,
                            visualDensity: const VisualDensity(vertical: -4),
                            horizontalTitleGap: context.wp(4),
                            side: const BorderSide(color: AppColors.orange, width: 1.5),
                            title: Text(
                              _kFormulaLabels[formula] ?? formula,
                              style: TextStyle(fontSize: context.sp(16)),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              // Carnet Rekovery initial : uniquement affiché pour un futur
              // adhérent "Rekovery seul" (voir `_isRekoverySoloOnly`) — un
              // adhérent qui combine Rekovery avec une formule sportive a un
              // accès illimité, sans carnet à préremplir.
              if (_isRekoverySoloOnly) ...[
                SizedBox(height: context.hp(20)),
                // Titre au-dessus du champ plutôt que `labelText` flottant
                // (9 août 2026, demande de Margaux) : avec le style de champ
                // actuel (bordure pleine), le libellé flottant se
                // superposait visuellement au contour du champ une fois
                // celui-ci non focus — même principe que le titre
                // "Formules" ci-dessus.
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Carnet Rekovery',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SizedBox(height: context.hp(8)),
                TextFormField(
                  controller: _rekoveryCreditsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '10 séances par défaut'),
                  validator: (v) {
                    if (!_isRekoverySoloOnly) return null;
                    final n = int.tryParse((v ?? '').trim());
                    return (n == null || n < 0) ? 'Nombre invalide' : null;
                  },
                ),
              ],
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
