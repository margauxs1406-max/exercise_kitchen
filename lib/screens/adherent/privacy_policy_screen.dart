import 'package:flutter/material.dart';

import '../../theme/responsive.dart';

/// Sous-menu "Confidentialité" du profil adhérent : relecture à tout moment
/// de la politique de confidentialité déjà acceptée à l'écran de
/// consentement obligatoire (voir `consent_screen.dart`).
///
/// ⚠️ Texte dupliqué depuis `consent_screen.dart` (lecture seule ici, sans
/// case à cocher ni bouton "Continuer") — à garder synchronisé si le texte
/// change. Comme pour l'écran de consentement, ce texte reste PROVISOIRE en
/// attendant la relecture définitive du gérant.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Confidentialité'.toUpperCase())),
      body: SingleChildScrollView(
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
