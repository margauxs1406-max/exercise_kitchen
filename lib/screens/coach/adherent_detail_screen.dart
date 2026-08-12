import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/user_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import 'adherent_photos_screen.dart';
import 'adherent_rekovery_history_screen.dart';

const Map<String, String> _kFormulaLabels = {
  'collectif': 'Collectif',
  'duo': 'Duo',
  'individuel': 'Individuel',
  'rekovery': 'Rekovery',
};

/// Fiche détaillée d'un adhérent (section 5) : informations saisies à la
/// création, et formules souscrites — celles-ci restent des cases à cocher
/// ici (contrairement au reste de la fiche) car elles doivent pouvoir être
/// modifiées à tout moment par un coach, pas seulement à la création.
///
/// Écouté en direct (`watchUser`) : si un autre coach modifie la fiche en
/// parallèle, cet écran se met à jour tout seul.
class AdherentDetailScreen extends StatelessWidget {
  final String uid;
  const AdherentDetailScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserRepository>();
    return Scaffold(
      appBar: AppBar(title: Text('Fiche adhérent'.toUpperCase())),
      body: StreamBuilder<UserModel?>(
        stream: repo.watchUser(uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final adherent = snapshot.data;
          if (adherent == null) {
            return const Center(child: Text('Cet adhérent est introuvable.'));
          }
          return _AdherentDetailBody(repo: repo, adherent: adherent);
        },
      ),
    );
  }
}

class _AdherentDetailBody extends StatelessWidget {
  final UserRepository repo;
  final UserModel adherent;
  const _AdherentDetailBody({required this.repo, required this.adherent});

  Future<void> _toggleFormula(String formula, bool checked) async {
    final updated = Set<String>.from(adherent.formulas);
    if (checked) {
      updated.add(formula);
    } else {
      updated.remove(formula);
    }
    await repo.updateFormulas(adherent.uid, updated);
  }

  /// Coach : modifie le numéro de téléphone de l'adhérent — champ vide
  /// enregistré comme `null` (redevient "Téléphone non renseigné").
  Future<void> _editPhone(BuildContext context) async {
    final controller = TextEditingController(text: adherent.phone ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Modifier le numéro de téléphone'.toUpperCase()),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: 'Numéro de téléphone'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (result != null) {
      await repo.updatePhone(adherent.uid, result);
    }
  }

  /// Coach : ajuste manuellement le carnet Rekovery — voir
  /// `UserRepository.updateRekoveryCredits`. Plus de bouton "Renouveler
  /// (10)" (retiré le 6 août 2026, faisait doublon avec le champ libre) : il
  /// suffit d'écrire le nombre voulu, ce qui permet aussi de faire évoluer
  /// la taille standard d'un carnet sans mise à jour de l'application.
  Future<void> _editRekoveryCredits(BuildContext context) async {
    final controller = TextEditingController(
      text: (adherent.rekoveryCreditsRemaining ?? 0).toString(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('CARNET REKOVERY'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Séances restantes'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text.trim())),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (result != null) {
      await repo.updateRekoveryCredits(adherent.uid, result);
    }
  }

  Future<void> _toggleAccountStatus(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          (adherent.isActive ? 'Clôturer ce compte ?' : 'Réactiver ce compte ?').toUpperCase(),
        ),
        content: Text(adherent.isActive
            ? "${adherent.fullName} ne pourra plus se connecter à l'application."
            : "${adherent.fullName} pourra à nouveau se connecter à l'application."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await (adherent.isActive
          ? repo.closeAccount(adherent.uid)
          : repo.reopenAccount(adherent.uid));
    }
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // `Expanded` : évite que le nom pousse le badge "Actif"
                    // hors de l'écran si le nom est long.
                    Expanded(
                      child: Text(adherent.fullName, style: Theme.of(context).textTheme.titleLarge),
                    ),
                    // Le statut "Clôturé" n'a plus de badge ici (supprimé —
                    // il était affiché même pour un compte actif à cause
                    // d'un résidu de l'ancien `Chip`) : le statut se lit
                    // désormais uniquement sur le libellé du bouton en bas
                    // ("Clôturer" / "Réactiver"). Seul "Actif" garde son
                    // repère visuel ici, quand c'est le cas.
                    if (adherent.isActive)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, color: AppColors.flashyGreen, size: context.wp(18)),
                          SizedBox(width: context.wp(4)),
                          const Text(
                            'Actif',
                            style: TextStyle(
                                color: AppColors.flashyGreen, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                  ],
                ),
                SizedBox(height: context.hp(12)),
                _InfoLine(icon: Icons.email, label: adherent.email),
                SizedBox(height: context.hp(6)),
                Row(
                  children: [
                    Expanded(
                      child: _InfoLine(
                        icon: Icons.phone,
                        label: (adherent.phone == null || adherent.phone!.isEmpty)
                            ? 'Téléphone non renseigné'
                            : adherent.phone!,
                      ),
                    ),
                    // Modifiable à tout moment par un coach (contrairement à
                    // l'email, saisi une seule fois à la création).
                    IconButton(
                      onPressed: () => _editPhone(context),
                      tooltip: 'Modifier le numéro',
                      icon: Icon(Icons.edit, size: context.wp(18), color: AppColors.mediumGrey),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                SizedBox(height: context.hp(12)),
                // Déplacé ici, sous le numéro de téléphone, dans la rubrique
                // des données personnelles — texte cliquable orange souligné,
                // aligné à gauche (plus de bouton à bordure séparé en bas de
                // fiche).
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => _toggleAccountStatus(context),
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      adherent.isActive ? 'Clôturer ce compte' : 'Réactiver ce compte',
                      style: const TextStyle(
                        color: AppColors.orange,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.orange,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: context.hp(8)),
        Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Formules', style: Theme.of(context).textTheme.titleMedium),
                const Text(
                  "Déterminent ce que l'adhérent voit et peut faire dans son planning.",
                  style: TextStyle(color: AppColors.mediumGrey),
                ),
                ...kAllFormulas.map(
                  (formula) => CheckboxListTile(
                    value: adherent.formulas.contains(formula),
                    onChanged: (checked) => _toggleFormula(formula, checked ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    // Réduit la hauteur de chaque ligne (56dp par défaut) et
                    // resserre encore l'espacement vertical intrinsèque du
                    // `ListTile` sous-jacent.
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -4),
                    // Resserre l'espace entre la case et le texte (16 par
                    // défaut).
                    horizontalTitleGap: context.wp(4),
                    // Contour orange — surtout visible quand la case n'est
                    // PAS cochée : une fois cochée, le remplissage orange
                    // (couleur "primary" du thème) masque le contour.
                    side: const BorderSide(color: AppColors.orange, width: 1.5),
                    title: Text(
                      _kFormulaLabels[formula] ?? formula,
                      style: TextStyle(fontSize: context.sp(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Historique Rekovery : disponible pour TOUS les adhérents (pas
        // seulement "Rekovery seul"), utile en cas de réclamation sur le
        // nombre de séances ou de dégradation de l'espace (demande du 6
        // août 2026).
        SizedBox(height: context.hp(8)),
        Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Historique Rekovery', style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: context.hp(12)),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AdherentRekoveryHistoryScreen(adherent: adherent),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.orange),
                  ),
                  // Icône Rekovery : SVG dédié (7 août 2026, remplace
                  // l'icône Material `Icons.thermostat`) — voir aussi
                  // `rekovery_request_card.dart`/`adherent_rekovery_history_screen.dart`/
                  // `adherent_rekovery_screen.dart`, mêmes emplacements.
                  icon: SvgPicture.asset(
                    'assets/thermometer.svg',
                    width: context.wp(18),
                    height: context.wp(18),
                    colorFilter: const ColorFilter.mode(AppColors.orange, BlendMode.srcIn),
                  ),
                  label: const Text("Voir l'historique des séances"),
                ),
              ],
            ),
          ),
        ),
        // Carnet Rekovery : uniquement pour un adhérent "Rekovery seul"
        // (aucune formule sportive) — celui avec un accès illimité (Rekovery
        // en plus d'une formule sportive) n'a pas de carnet à gérer.
        if (adherent.isRekoverySoloOnly) ...[
          SizedBox(height: context.hp(8)),
          Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(16)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Carnet Rekovery', style: Theme.of(context).textTheme.titleMedium),
                        SizedBox(height: context.hp(4)),
                        Text(
                          '${adherent.rekoveryCreditsRemaining ?? 0} séance'
                          '${(adherent.rekoveryCreditsRemaining ?? 0) > 1 ? 's' : ''} restante'
                          '${(adherent.rekoveryCreditsRemaining ?? 0) > 1 ? 's' : ''}',
                          style: const TextStyle(color: AppColors.mediumGrey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _editRekoveryCredits(context),
                    tooltip: 'Modifier le carnet',
                    icon: const Icon(Icons.edit, color: AppColors.mediumGrey),
                  ),
                ],
              ),
            ),
          ),
        ],
        SizedBox(height: context.hp(8)),
        Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Photos de progression', style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: context.hp(12)),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AdherentPhotosScreen(adherent: adherent)),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.orange),
                  ),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Voir / importer les photos'),
                ),
              ],
            ),
          ),
        ),
      ],
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
        Icon(icon, size: context.wp(18), color: AppColors.mediumGrey),
        SizedBox(width: context.wp(8)),
        Expanded(child: Text(label)),
      ],
    );
  }
}
