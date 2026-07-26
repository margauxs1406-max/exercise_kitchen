import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/registration_model.dart';
import '../models/slot_model.dart';
import '../models/user_model.dart';
import '../services/registration_repository.dart';
import '../services/user_repository.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Section 1.3 : pop-up listant les inscrits et la liste d'attente d'un
/// créneau de cours collectif ou duo, ouverte en tapant sur sa carte dans le
/// planning coach (voir `manage_planning_screen.dart`). Les créneaux
/// individuels et les workshops n'ont pas d'inscription libre (voir
/// `SlotCard.showCount`) : cette pop-up ne les concerne pas et n'y est pas
/// branchée.
Future<void> showSlotRosterDialog(BuildContext context, SlotModel slot) {
  return showDialog<void>(
    context: context,
    builder: (_) => SlotRosterDialog(slot: slot),
  );
}

class SlotRosterDialog extends StatelessWidget {
  final SlotModel slot;
  const SlotRosterDialog({super.key, required this.slot});

  @override
  Widget build(BuildContext context) {
    final registrationRepo = context.read<RegistrationRepository>();
    final userRepo = context.read<UserRepository>();

    return AlertDialog(
      // Explicite (déjà la valeur par défaut du thème depuis
      // `app_theme.dart`) : évite le fond légèrement orange pâle que
      // Material 3 donne par défaut aux `Dialog` via le rôle
      // `surfaceContainerHigh` de `ColorScheme.fromSeed`.
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(slot.courseTitle.toUpperCase()),
      // `width: double.maxFinite` : sans ça, l'`AlertDialog` réduit son
      // contenu à sa largeur intrinsèque minimale (souvent trop étroit pour
      // des noms complets) plutôt que d'utiliser toute la largeur que
      // Material lui accorde par défaut.
      //
      // `ConstrainedBox(maxHeight: 360)` : la pop-up s'adapte maintenant à
      // la taille réelle de la liste (courte liste → pop-up courte), tout
      // en ne dépassant jamais 360 de haut — au-delà, c'est la liste
      // "Inscrits"/"Liste d'attente" (le `Flexible` + `ListView(shrinkWrap:
      // true)` ci-dessous) qui devient scrollable, pas la pop-up entière.
      // (`Flexible` et pas `Expanded` : `Expanded` forcerait la pop-up à
      // toujours faire 360 de haut, même pour 2 inscrits.)
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: context.hp(360)),
        child: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder<List<RegistrationModel>>(
            stream: registrationRepo.watchRegistrationsForSlot(slot.id),
            builder: (context, snapshot) {
              // Comme pour la liste des adhérents (voir
              // `create_adherent_screen.dart`) : sans ce test, une erreur de
              // requête laisserait la roue de chargement tourner indéfiniment.
              if (snapshot.hasError) {
                return SizedBox(
                  height: context.hp(80),
                  child: Center(
                    child: Text(
                      "Impossible de charger la liste pour l'instant.\n\n"
                      'Détail : ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.mediumGrey),
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return SizedBox(
                  height: context.hp(80),
                  child: const Center(child: CircularProgressIndicator()),
                );
              }

              final registrations = snapshot.data!;
              final confirmed = registrations
                  .where((r) => r.status == RegistrationStatus.confirmed)
                  .toList()
                ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
              final waitlisted = registrations
                  .where((r) => r.status == RegistrationStatus.waitlisted)
                  .toList()
                ..sort(
                  (a, b) => (a.waitlistPosition ?? 0).compareTo(b.waitlistPosition ?? 0),
                );

              return FutureBuilder<Map<String, UserModel>>(
                future: userRepo.getUsersByIds(registrations.map((r) => r.userId).toList()),
                builder: (context, usersSnapshot) {
                  if (!usersSnapshot.hasData) {
                    return SizedBox(
                      height: context.hp(80),
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  }
                  final users = usersSnapshot.data!;
                  String nameFor(String uid) {
                    final user = users[uid];
                    return user == null ? 'Adhérent inconnu' : user.shortName;
                  }

                  // En-tête (heure + compteur) toujours entièrement visible,
                  // hors de la zone de scroll : seule la liste ci-dessous
                  // défile, et seulement si elle dépasse les 360 max.
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${slot.startTime}–${slot.endTime} · '
                        '${slot.registeredCount}/${slot.capacity} inscrit(s)',
                        style: const TextStyle(color: AppColors.mediumGrey),
                      ),
                      SizedBox(height: context.hp(12)),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            Text('Inscrits', style: Theme.of(context).textTheme.titleMedium),
                            SizedBox(height: context.hp(4)),
                            if (confirmed.isEmpty)
                              const Text(
                                'Aucun inscrit pour ce créneau.',
                                style: TextStyle(color: AppColors.mediumGrey),
                              )
                            else
                              ...confirmed.map((r) => _RosterLine(name: nameFor(r.userId))),
                            SizedBox(height: context.hp(16)),
                            Text("Liste d'attente", style: Theme.of(context).textTheme.titleMedium),
                            SizedBox(height: context.hp(4)),
                            if (waitlisted.isEmpty)
                              const Text(
                                "Personne en liste d'attente.",
                                style: TextStyle(color: AppColors.mediumGrey),
                              )
                            else
                              ...waitlisted.asMap().entries.map(
                                    (entry) => _RosterLine(
                                      name: nameFor(entry.value.userId),
                                      position: entry.key + 1,
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

/// Une ligne "Prénom Nom" de la pop-up — coche verte pour un inscrit
/// confirmé, sablier jaune moutarde + numéro d'ordre pour la liste
/// d'attente (même palette que le reste de l'app pour ces deux statuts).
class _RosterLine extends StatelessWidget {
  final String name;
  final int? position;
  const _RosterLine({required this.name, this.position});

  @override
  Widget build(BuildContext context) {
    final inWaitlist = position != null;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.hp(4)),
      child: Row(
        children: [
          Icon(
            inWaitlist ? Icons.hourglass_top : Icons.check_circle,
            size: context.wp(18),
            color: inWaitlist ? AppColors.mustardYellow : AppColors.flashyGreen,
          ),
          SizedBox(width: context.wp(8)),
          Expanded(child: Text(inWaitlist ? '$position. $name' : name)),
        ],
      ),
    );
  }
}
