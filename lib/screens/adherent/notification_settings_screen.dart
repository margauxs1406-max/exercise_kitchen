import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/user_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';

/// Description d'un type de notification poussée (voir
/// `functions/src/index.ts`) tel qu'exposé à l'adhérent dans son profil.
///
/// [key] doit correspondre EXACTEMENT à la clé lue côté Cloud Functions
/// (`notificationPrefs.<key>` sur le document `users/{uid}`) — voir les
/// appels à `getTokensForUids`/`getTokensForFormula`/`getAllActiveTokens`
/// dans `functions/src/index.ts`, qui passent chacun la clé correspondante.
///
/// [requiredFormulas] : le type n'est affiché que si l'adhérent souscrit à
/// au moins une de ces formules — vide = toujours affiché (concerne tout le
/// monde, comme les fermetures/workshops). Le rappel Rekovery (envoyé aux
/// coachs, pas aux adhérents) n'a volontairement pas d'entrée ici.
class NotificationTypeInfo {
  final String key;
  final String label;
  final String description;
  final Set<String> requiredFormulas;

  const NotificationTypeInfo({
    required this.key,
    required this.label,
    required this.description,
    this.requiredFormulas = const {},
  });

  bool availableFor(Set<String> formulas) =>
      requiredFormulas.isEmpty || requiredFormulas.any(formulas.contains);
}

const List<NotificationTypeInfo> kNotificationTypes = [
  NotificationTypeInfo(
    key: 'courseReminder',
    label: 'Rappel de cours',
    description: 'Un rappel 2h avant un cours auquel tu es inscrit.e.',
    requiredFormulas: {'collectif', 'duo', 'individuel'},
  ),
  NotificationTypeInfo(
    key: 'waitlistPromoted',
    label: "Promotion depuis la liste d'attente",
    description: "Une place se libère et tu passes de la liste d'attente à inscrit.e.",
    requiredFormulas: {'collectif', 'duo'},
  ),
  NotificationTypeInfo(
    key: 'singleRegistrantAlert',
    label: 'Un binôme te cherche',
    description: "Un créneau n'a plus qu'un seul inscrit et risque d'être annulé.",
    requiredFormulas: {'collectif', 'duo'},
  ),
  NotificationTypeInfo(
    key: 'sameDayDoubleBooking',
    label: 'Double inscription le même jour',
    description: 'Tu es inscrit.e à deux cours le même jour — évite les oublis.',
    requiredFormulas: {'collectif', 'duo'},
  ),
  NotificationTypeInfo(
    key: 'duoIndividualChanged',
    label: 'Modification de ton cours',
    description: 'Ton cours duo ou individuel est modifié ou annulé.',
    requiredFormulas: {'duo', 'individuel'},
  ),
  NotificationTypeInfo(
    key: 'rekoveryStatusChanged',
    label: 'Réponse à une demande Rekovery',
    description: 'Le coach accepte, refuse ou propose un autre créneau pour '
        'ta demande Rekovery.',
    requiredFormulas: {'rekovery'},
  ),
  NotificationTypeInfo(
    key: 'workshopClosureBroadcast',
    label: 'Workshops et fermetures',
    description: "Un nouveau workshop ou une fermeture de la salle est annoncé.e.",
    // Toujours affiché : concerne tout le monde, quelle que soit la formule.
  ),
  NotificationTypeInfo(
    key: 'rekoveryClosureBroadcast',
    label: 'Fermeture Rekovery',
    description: "L'espace Rekovery est temporairement inaccessible sur une période.",
    requiredFormulas: {'rekovery'},
  ),
];

/// Sous-menu "Notifications" du profil adhérent : liste uniquement les
/// types de notification concernés par les formules actuellement souscrites
/// (les autres n'apparaissent pas du tout), avec un switch par type. Se met
/// à jour automatiquement si un coach modifie les formules de l'adhérent
/// pendant qu'il/elle est sur cet écran (`watchUser`, en direct).
class NotificationSettingsScreen extends StatelessWidget {
  final String uid;
  const NotificationSettingsScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserRepository>();
    return Scaffold(
      appBar: AppBar(title: Text('Notifications'.toUpperCase())),
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
          final visible =
              kNotificationTypes.where((t) => t.availableFor(user.formulas)).toList();
          if (visible.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: context.wp(24), vertical: context.hp(24)),
                child: const Text(
                  "Aucune notification disponible avec ta formule actuelle.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.mediumGrey),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(16)),
            itemCount: visible.length,
            separatorBuilder: (ctx, __) => Divider(height: ctx.hp(1)),
            itemBuilder: (context, i) {
              final type = visible[i];
              // Absent = activée par défaut, pour ne couper les
              // notifications de personne tant qu'il/elle n'a pas
              // explicitement désactivé ce type précis.
              final enabled = user.notificationPrefs[type.key] ?? true;
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.orange,
                title: Text(type.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(type.description),
                value: enabled,
                onChanged: (v) => repo.updateNotificationPref(uid, type.key, v),
              );
            },
          );
        },
      ),
    );
  }
}
