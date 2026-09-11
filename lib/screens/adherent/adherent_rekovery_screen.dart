import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../models/closure_model.dart';
import '../../models/rekovery_closure_model.dart';
import '../../models/rekovery_request_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/planning_repository.dart';
import '../../services/rekovery_repository.dart';
import '../../services/user_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../widgets/closure_banner.dart';
import '../../widgets/day_header.dart';
import '../../widgets/rekovery_closed_day_card.dart';
import '../../widgets/rekovery_request_actions_sheet.dart';
import '../../widgets/rekovery_request_card.dart';
import '../../widgets/rekovery_reserve_bar.dart';
import '../../widgets/week_header.dart';
import 'adherent_profile_screen.dart';

/// Onglet Rekovery côté adhérent (section "Rekovery", remplace l'ancienne
/// ligne "thermomètre" mêlée au planning des cours).
///
/// Contrairement au planning (semaine par semaine, avec flèches
/// précédent/suivant), Rekovery affiche une liste continue "à partir
/// d'aujourd'hui" — pas de découpage ni de pagination par semaine, à la
/// demande de Margaux : les demandes Rekovery ne suivent pas de logique
/// hebdomadaire.
///
/// Un adhérent "Rekovery seul" (voir [UserModel.isRekoverySoloOnly]) voit en
/// plus, en tête d'écran, le compteur de son carnet de 10 séances — mis à
/// jour en temps réel (`UserRepository.watchUser`, pas un simple champ figé
/// au moment de la connexion) puisqu'il peut changer à tout moment (coach
/// qui accepte une demande, annulation qui recrédite...).
///
/// Depuis le 6 août 2026, un adhérent voit aussi les créneaux Rekovery
/// réservés par LES AUTRES adhérents (utile pour choisir un créneau
/// tranquille) — nom (prénom + initiale) affiché sur toutes les cartes,
/// mais seules les demandes `pending`/`accepted` d'autrui sont visibles
/// (jamais `refused`/`cancelled`/`proposed`, qui n'ont pas encore ou plus de
/// créneau "réservé" au sens propre), grisées, sans action possible (appui
/// long réservé aux propres demandes de l'adhérent — voir [_isOwn] dans
/// `itemBuilder` ci-dessous).
class AdherentRekoveryScreen extends StatelessWidget {
  const AdherentRekoveryScreen({super.key});

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthService>().currentUser?.uid;
    final userRepo = context.read<UserRepository>();
    final rekoveryRepo = context.read<RekoveryRepository>();
    final planningRepo = context.read<PlanningRepository>();

    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: WeekHeader(
        onProfileTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdherentProfileScreen()),
        ),
        weekTypeContent: const Text('REKOVERY', style: AppTheme.headerTitleStyle),
      ),
      body: StreamBuilder<UserModel?>(
        stream: userRepo.watchUser(uid),
        builder: (context, userSnapshot) {
          final user = userSnapshot.data;
          if (user == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return FutureBuilder<List<ClosureModel>>(
            future: planningRepo.fetchAllClosures(),
            builder: (context, closuresSnapshot) {
              final closures = closuresSnapshot.data ?? const <ClosureModel>[];

              // Fermetures Rekovery (21 août 2026, distinctes des fermetures
              // de salle ci-dessus) — flux en direct (voir doc de
              // `RekoveryRepository.watchAllClosures`), pour que le bandeau
              // de réservation et les cartes "jour fermé" se mettent à jour
              // dès qu'un coach en ajoute une.
              return StreamBuilder<List<RekoveryClosureModel>>(
                stream: rekoveryRepo.watchAllClosures(),
                builder: (context, rekoveryClosuresSnapshot) {
                  final rekoveryClosures =
                      rekoveryClosuresSnapshot.data ?? const <RekoveryClosureModel>[];

                  return Column(
                    children: [
                      if (user.isRekoverySoloOnly) _CreditsBanner(user: user),
                      RekoveryReserveBar(closures: closures, rekoveryClosures: rekoveryClosures),
                      Expanded(
                        child: StreamBuilder<List<RekoveryRequestModel>>(
                          // `watchAllRequests` (pas `watchMyRequests`) depuis le
                          // 6 août 2026 : l'écran doit aussi montrer les
                          // réservations des autres adhérents (voir doc de
                          // classe ci-dessus) — le filtrage "propre demande vs
                          // demande d'autrui" se fait ci-dessous, côté client.
                          stream: rekoveryRepo.watchAllRequests(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final today = _dayOf(DateTime.now());
                            final visible = snapshot.data!
                                .where((r) {
                                  final isOwn = r.adherentUid == uid;
                                  if (isOwn) {
                                    // Liste continue "à partir d'aujourd'hui" :
                                    // une demande passée disparaît, sauf si
                                    // elle est encore active (pending/proposed)
                                    // — ne devrait normalement pas arriver, mais
                                    // évite qu'une demande en attente de réponse
                                    // disparaisse par un simple décalage
                                    // d'horloge.
                                    return !_dayOf(r.date).isBefore(today) ||
                                        r.status == RekoveryRequestStatus.pending ||
                                        r.status == RekoveryRequestStatus.proposed;
                                  }
                                  // Demande d'un AUTRE adhérent : seulement si
                                  // "réservée" au sens propre (en attente ou
                                  // confirmée) et pas déjà passée — jamais les
                                  // refusées/annulées, ni les contre-
                                  // propositions en cours (pas encore un vrai
                                  // créneau retenu).
                                  return !_dayOf(r.date).isBefore(today) &&
                                      (r.status == RekoveryRequestStatus.pending ||
                                          r.status == RekoveryRequestStatus.accepted);
                                })
                                .toList()
                              ..sort((a, b) {
                                final dateCompare = a.date.compareTo(b.date);
                                return dateCompare != 0
                                    ? dateCompare
                                    : a.startTime.compareTo(b.startTime);
                              });

                            // Fermetures Rekovery à partir d'aujourd'hui, une
                            // entrée par jour couvert — pour afficher une
                            // carte "jour fermé" (voir doc de classe) sur
                            // chacun, mélangée aux demandes du même jour.
                            final closedByDay = <DateTime, List<RekoveryClosureModel>>{};
                            for (final c in rekoveryClosures) {
                              if (_dayOf(c.endDate).isBefore(today)) continue;
                              var day =
                                  _dayOf(c.startDate).isBefore(today) ? today : _dayOf(c.startDate);
                              final lastDay = _dayOf(c.endDate);
                              while (!day.isAfter(lastDay)) {
                                closedByDay.putIfAbsent(day, () => []).add(c);
                                day = day.add(const Duration(days: 1));
                              }
                            }

                            // Fermetures DE LA SALLE (21 août 2026, demande
                            // de Margaux : "les slots de fermetures de la
                            // salle doivent apparaitre dans le planning
                            // rekovery également") — même principe, un
                            // `ClosureBanner` par jour couvert, affiché
                            // au-dessus des éventuelles fermetures Rekovery
                            // du même jour.
                            final roomClosedByDay = <DateTime, List<ClosureModel>>{};
                            for (final c in closures) {
                              if (_dayOf(c.endDate).isBefore(today)) continue;
                              var day =
                                  _dayOf(c.startDate).isBefore(today) ? today : _dayOf(c.startDate);
                              final lastDay = _dayOf(c.endDate);
                              while (!day.isAfter(lastDay)) {
                                roomClosedByDay.putIfAbsent(day, () => []).add(c);
                                day = day.add(const Duration(days: 1));
                              }
                            }

                            if (visible.isEmpty && closedByDay.isEmpty && roomClosedByDay.isEmpty) {
                              return const Center(
                                child: Text('Aucune demande Rekovery pour le moment.'),
                              );
                            }

                            // Regroupement par jour (marqueur [DayHeader]), comme
                            // le planning des cours — fermeture de salle en tête
                            // de chaque jour concerné, puis fermetures Rekovery,
                            // puis demandes.
                            final allDays = <DateTime>{
                              ...visible.map((r) => _dayOf(r.date)),
                              ...closedByDay.keys,
                              ...roomClosedByDay.keys,
                            }.toList()
                              ..sort();

                            final items = <Object>[];
                            for (final day in allDays) {
                              items.add(day);
                              items.addAll(roomClosedByDay[day] ?? const []);
                              items.addAll(closedByDay[day] ?? const []);
                              items.addAll(visible.where((r) => _dayOf(r.date) == day));
                            }

                            // Anonymisation (11 septembre 2026, demande de
                            // Margaux : "anonymiser les gens qui ne se
                            // connaissent pas") : il faut connaître les
                            // formules des AUTRES adhérents apparaissant
                            // dans `visible` pour savoir si leur vrai nom
                            // peut être montré (voir la règle complète plus
                            // bas, à l'endroit où `displayName` est calculé).
                            final otherUids = visible
                                .where((r) => r.adherentUid != uid)
                                .map((r) => r.adherentUid)
                                .toSet()
                                .toList();

                            return FutureBuilder<Map<String, UserModel>>(
                              future: userRepo.getUsersByIds(otherUids),
                              builder: (context, othersSnapshot) {
                                final others =
                                    othersSnapshot.data ?? const <String, UserModel>{};

                                return ListView.builder(
                                  padding: EdgeInsets.symmetric(horizontal: context.wp(12)),
                                  itemCount: items.length,
                                  itemBuilder: (context, i) {
                                    final item = items[i];
                                    if (item is DateTime) {
                                      return DayHeader(
                                        date: item,
                                        isFirst: i == 0,
                                        firstTopPadding: context.hp(12),
                                      );
                                    }
                                    if (item is ClosureModel) {
                                      // Fermeture de salle — lecture seule ici
                                      // (l'édition reste dans le planning
                                      // principal, voir `weekly_planning_screen.dart`).
                                      return ClosureBanner(closure: item);
                                    }
                                    if (item is RekoveryClosureModel) {
                                      // Lecture seule côté adhérent (pas
                                      // d'`onLongPress`) — seul le coach peut
                                      // supprimer une fermeture Rekovery, voir
                                      // `coach_rekovery_screen.dart`.
                                      return RekoveryClosedDayCard(closure: item);
                                    }
                                    final request = item as RekoveryRequestModel;
                                    final isOwn = request.adherentUid == uid;
                                    final canAct = isOwn &&
                                        (request.status == RekoveryRequestStatus.pending ||
                                            request.status == RekoveryRequestStatus.proposed ||
                                            request.status == RekoveryRequestStatus.accepted);
                                    // Règle d'anonymisation (11 septembre
                                    // 2026) : le vrai nom d'un(e) AUTRE
                                    // adhérent(e) n'est visible que si LES
                                    // DEUX (la personne qui regarde ET celle
                                    // qui a réservé) ont la formule
                                    // "collectif" — elles se croisent déjà
                                    // réellement en cours collectif. Dans
                                    // tous les autres cas (l'une des deux —
                                    // ou les deux — n'a que duo+rekovery,
                                    // individuel+rekovery, ou rekovery seul),
                                    // le nom est remplacé par "Adhérent EK".
                                    // Ne s'applique jamais à sa propre
                                    // demande (`displayName` reste `null`,
                                    // `RekoveryRequestCard` retombe alors sur
                                    // `request.adherentName`, le vrai nom).
                                    String? displayName;
                                    if (!isOwn) {
                                      final requester = others[request.adherentUid];
                                      final bothCollectif = user.hasCollectifFormula &&
                                          (requester?.hasCollectifFormula ?? false);
                                      displayName = bothCollectif ? null : 'Adhérent EK';
                                    }
                                    return RekoveryRequestCard(
                                      request: request,
                                      // Nom affiché sur toutes les cartes (y compris
                                      // les siennes) depuis le 6 août 2026 — voir
                                      // doc de classe ci-dessus ; anonymisé ou non
                                      // selon `displayName` ci-dessus.
                                      showName: true,
                                      displayName: displayName,
                                      isOwn: isOwn,
                                      // Couleurs par statut (10 août 2026, voir
                                      // `RekoveryRequestCard.colorByStatus`) : sans
                                      // effet sur les demandes des autres, `isOwn`
                                      // filtrant déjà en interne.
                                      colorByStatus: true,
                                      // Appui long uniquement (6 août 2026), et
                                      // seulement sur SA PROPRE demande : un simple
                                      // tap ne déclenche plus les actions (annulation
                                      // trop facile par accident), et personne ne
                                      // peut agir sur la réservation d'un(e) autre.
                                      onLongPress: canAct
                                          ? () => showRekoveryRequestActionsSheet(context, request)
                                          : null,
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Bandeau du carnet Rekovery, affiché uniquement pour un adhérent
/// "Rekovery seul" — celui avec un accès illimité (formule Rekovery EN PLUS
/// d'une formule sportive) n'a pas de compteur à afficher.
///
/// Texte volontairement minimal (demande du 6 août 2026) : juste "X séances
/// restantes" avec l'icône, sans phrase supplémentaire. Icône + texte
/// CENTRÉS dans le bandeau (10 août 2026, demande de Margaux — auparavant
/// alignés à gauche).
class _CreditsBanner extends StatelessWidget {
  final UserModel user;
  const _CreditsBanner({required this.user});

  @override
  Widget build(BuildContext context) {
    final remaining = user.rekoveryCreditsRemaining ?? 0;
    final isLow = remaining <= 2;
    return Container(
      width: double.infinity,
      color: AppColors.black,
      padding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icône Rekovery : SVG dédié (7 août 2026, remplace l'icône
          // Material `Icons.thermostat`) — voir aussi
          // `rekovery_request_card.dart`/`adherent_rekovery_history_screen.dart`/
          // `adherent_detail_screen.dart`, mêmes emplacements.
          SvgPicture.asset(
            'assets/thermometer.svg',
            width: context.wp(24),
            height: context.wp(24),
            colorFilter: const ColorFilter.mode(AppColors.orange, BlendMode.srcIn),
          ),
          SizedBox(width: context.wp(10)),
          Text(
            '$remaining séance${remaining > 1 ? 's' : ''} restante${remaining > 1 ? 's' : ''}',
            style: TextStyle(
              color: isLow ? AppColors.orange : AppColors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
