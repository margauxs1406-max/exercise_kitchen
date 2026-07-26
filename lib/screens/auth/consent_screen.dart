import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/responsive.dart';
import '../../widgets/week_header.dart';

/// Écran de consentement RGPD obligatoire avant tout accès à l'application
/// (section 2 des spécifications techniques).
///
/// ⚠️ Le texte ci-dessous est un texte PROVISOIRE. Les spécifications
/// indiquent explicitement que le texte définitif de la politique de
/// confidentialité et des mentions légales doit être relu par le gérant
/// (idéalement avec un avis juridique) avant publication sur les stores.
/// Ne pas publier l'application avec ce texte tel quel.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _accepted = false; // case non pré-cochée, comme l'exige la spécification
  bool _submitting = false;

  Future<void> _continue() async {
    if (!_accepted) return;
    setState(() => _submitting = true);
    await context.read<AuthService>().acceptConsent();
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Section 3.1/3.2 : même hauteur que l'en-tête du planning, titre
      // aligné à gauche (plutôt que centré, par défaut dans le thème).
      appBar: AppBar(
        title: Text('Politique de confidentialité'.toUpperCase()),
        centerTitle: false,
        toolbarHeight: kTallHeaderHeight,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: context.wp(24), vertical: context.hp(24)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _Section(
                      title: 'Finalités du traitement',
                      body:
                          'Gestion du planning des cours, suivi de ta progression '
                          '(photos) et suivi de ton hydratation.',
                    ),
                    _Section(
                      title: 'Données collectées',
                      body:
                          '• Identité et contact (nom, prénom, email)\n'
                          '• Photos de progression (face, dos, profils) — visibles '
                          'uniquement par toi et les coachs\n'
                          '• Réponses au questionnaire d\'hydratation et score calculé\n'
                          '• Historique de tes inscriptions aux cours',
                    ),
                    _Section(
                      title: 'Durée de conservation',
                      body:
                          'Tes données sont conservées tant que ton compte est actif, '
                          'puis pendant une durée limitée après clôture avant '
                          'suppression ou anonymisation (durée en cours de validation '
                          'par le gérant).',
                    ),
                    _Section(
                      title: 'Tes droits',
                      body:
                          'Tu disposes d\'un droit d\'accès, de rectification et '
                          'd\'effacement de tes données. Pour l\'exercer, contacte un '
                          'coach ou le responsable de traitement.',
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: context.hp(1)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
                    value: _accepted,
                    onChanged: (v) => setState(() => _accepted = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("J'ai lu et j'accepte la politique de confidentialité"),
                  ),
                  SizedBox(height: context.hp(8)),
                  ElevatedButton(
                    onPressed: (_accepted && !_submitting) ? _continue : null,
                    child: _submitting
                        ? SizedBox(
                            height: context.hp(20),
                            width: context.wp(20),
                            child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Continuer'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.hp(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: context.hp(6)),
          Text(body),
        ],
      ),
    );
  }
}
