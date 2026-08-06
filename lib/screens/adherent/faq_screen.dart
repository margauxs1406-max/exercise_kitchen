import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';

class _FaqEntry {
  final String question;
  final String answer;
  const _FaqEntry(this.question, this.answer);
}

/// Contenu rédigé pour ce MVP (aucune liste de questions fournie) — à
/// ajuster librement selon les questions réellement posées par les
/// adhérents une fois l'app en usage.
const List<_FaqEntry> _kFaqEntries = [
  _FaqEntry(
    "Comment m'inscrire à un cours ?",
    "Depuis l'onglet Planning, appuie sur \"S'inscrire\" sur le créneau de ton choix. "
        "S'il affiche \"File d'attente\", le cours est complet mais tu peux quand même "
        "t'inscrire sur liste d'attente.",
  ),
  _FaqEntry(
    "Que se passe-t-il si un cours est complet ?",
    "Tu peux rejoindre la liste d'attente. Si une place se libère, tu es "
        "automatiquement inscrit.e à sa place et prévenu.e par notification.",
  ),
  _FaqEntry(
    "Comment annuler mon inscription ?",
    "Appuie sur le bouton \"Inscrit.e\"/\"En attente\" du créneau concerné, dans "
        "l'onglet Planning, pour te désinscrire.",
  ),
  _FaqEntry(
    "Jusqu'à quand puis-je m'inscrire à l'avance ?",
    "Les inscriptions sont ouvertes sur la semaine en cours, et sur la semaine "
        "suivante à partir du vendredi de la semaine en cours.",
  ),
  _FaqEntry(
    "Comment voir mes photos de progression ?",
    "Depuis l'onglet Photos : tes coachs y ajoutent régulièrement de nouvelles "
        "photos (face, dos, profils) pour suivre ton évolution.",
  ),
  _FaqEntry(
    "Comment fonctionne le Rekovery ?",
    "Si ta formule l'inclut, un bouton dédié dans le planning te permet d'indiquer "
        "ton heure d'arrivée, pour que les coachs préparent l'espace avant que tu "
        "n'arrives.",
  ),
  _FaqEntry(
    "J'ai oublié mon mot de passe.",
    "Utilise \"Mot de passe oublié\" depuis l'écran de connexion, ou change-le "
        "à tout moment depuis Profil > Données personnelles.",
  ),
];

/// Sous-menu "FAQ" du profil adhérent.
class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('FAQ'.toUpperCase())),
      body: ListView.separated(
        padding: EdgeInsets.symmetric(vertical: context.hp(8)),
        itemCount: _kFaqEntries.length,
        separatorBuilder: (ctx, __) => Divider(height: ctx.hp(1)),
        itemBuilder: (context, i) {
          final entry = _kFaqEntries[i];
          return ExpansionTile(
            title: Text(entry.question, style: const TextStyle(fontWeight: FontWeight.w600)),
            childrenPadding: EdgeInsets.fromLTRB(context.wp(16), 0, context.wp(16), context.hp(16)),
            expandedAlignment: Alignment.centerLeft,
            children: [
              Text(entry.answer, style: const TextStyle(color: AppColors.mediumGrey)),
            ],
          );
        },
      ),
    );
  }
}
