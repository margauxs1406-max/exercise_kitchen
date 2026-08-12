import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../models/closure_model.dart';
import '../../models/rekovery_request_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/planning_repository.dart';
import '../../services/rekovery_repository.dart';
import '../../services/user_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../widgets/day_header.dart';
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
        weekTypeContent: Text('REKOVERY', style: AppTheme.headerTitleStyle),
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

              return Column(
                children: [
                  if (user.isRekoverySoloOnly) _CreditsBanner(user: user),
                  RekoveryReserveBar(closures: closures),
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

                        if (visible.isEmpty) {
                          return const Center(
                            child: Text('Aucune demande Rekovery pour le moment.'),
                          );
                        }

                        // Regroupement par jour (marqueur [DayHeader]), comme
                        // le planning des cours — sans mélange avec des
                        // créneaux ou fermetures ici.
                        final items = <Object>[];
                        DateTime? lastDay;
                        for (final r in visible) {
                          final day = _dayOf(r.date);
                          if (lastDay == null || day != lastDay) {
                            items.add(day);
                            lastDay = day;
                          }
                          items.add(r);
                        }

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
                            final request = item as RekoveryRequestModel;
                            final isOwn = request.adherentUid == uid;
                            final canAct = isOwn &&
                                (request.status == RekoveryRequestStatus.pending ||
                                    request.status == RekoveryRequestStatus.proposed ||
                                    request.status == RekoveryRequestStatus.accepted);
                            return RekoveryRequestCard(
                              request: request,
                              // Nom affiché sur toutes les cartes (y compris
                              // les siennes) depuis le 6 août 2026 — voir
                              // doc de classe ci-dessus.
                              showName: true,
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
                    ),
                  ),
                ],
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
