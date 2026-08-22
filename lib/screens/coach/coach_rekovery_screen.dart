import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/closure_model.dart';
import '../../models/rekovery_closure_model.dart';
import '../../models/rekovery_request_model.dart';
import '../../services/auth_service.dart';
import '../../services/planning_repository.dart';
import '../../services/rekovery_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../widgets/closure_actions_sheet.dart';
import '../../widgets/closure_banner.dart';
import '../../widgets/coach_rekovery_actions_sheet.dart';
import '../../widgets/day_header.dart';
import '../../widgets/rekovery_closed_day_card.dart';
import '../../widgets/rekovery_closure_actions_sheet.dart';
import '../../widgets/rekovery_request_card.dart';
import '../../widgets/week_header.dart';
import 'add_rekovery_closure_screen.dart';

/// Onglet Rekovery côté coach — voit TOUTES les demandes de tous les
/// adhérents (avec leur nom), et peut accepter / refuser / proposer un
/// autre créneau (voir `coach_rekovery_actions_sheet.dart`).
///
/// Même logique de liste continue "à partir d'aujourd'hui" que côté
/// adhérent (`adherent_rekovery_screen.dart`) — pas de pagination par
/// semaine. Possède son propre en-tête ([WeekHeader], titre "Rekovery"),
/// comme `ManagePlanningScreen` pour le planning.
///
/// Les demandes [RekoveryRequestStatus.cancelled] sont toujours masquées
/// (10 août 2026, demande de Margaux) — inutile d'encombrer le planning du
/// coach avec des séances que l'adhérent a lui-même annulées.
///
/// Depuis le 21 août 2026, un bouton flottant "+" (même style que celui du
/// planning, voir `manage_planning_screen.dart`) ouvre
/// [AddRekoveryClosureScreen] pour fermer temporairement ou de façon
/// prolongée l'espace Rekovery (indépendamment d'une fermeture de toute la
/// salle, voir `RekoveryClosureModel`) — les jours concernés affichent une
/// carte "Rekovery temporairement inaccessible" ([RekoveryClosedDayCard]) à
/// la place des créneaux habituels, en plus des demandes du jour s'il y en
/// a. Les fermetures DE LA SALLE (`ClosureModel`) apparaissent aussi ici
/// (même jour par jour, [ClosureBanner]) — avec le même appui long
/// Modifier/Supprimer que dans le planning principal (21 août 2026, demande
/// de Margaux — "où qu'il soit", voir `closure_actions_sheet.dart`), pour
/// ne pas avoir à retourner sur `manage_planning_screen.dart` juste pour
/// gérer une fermeture repérée depuis l'onglet Rekovery.
class CoachRekoveryScreen extends StatelessWidget {
  const CoachRekoveryScreen({super.key});

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final repo = context.read<RekoveryRepository>();
    final planningRepo = context.read<PlanningRepository>();
    final auth = context.read<AuthService>();

    return Scaffold(
      appBar: WeekHeader(
        onLogout: () => auth.signOut(),
        weekTypeContent: Text('REKOVERY', style: AppTheme.headerTitleStyle),
      ),
      body: FutureBuilder<List<ClosureModel>>(
        future: planningRepo.fetchAllClosures(),
        builder: (context, roomClosuresSnapshot) {
          final roomClosures = roomClosuresSnapshot.data ?? const <ClosureModel>[];

          return StreamBuilder<List<RekoveryClosureModel>>(
            stream: repo.watchAllClosures(),
            builder: (context, closuresSnapshot) {
              final closures = closuresSnapshot.data ?? const <RekoveryClosureModel>[];

              return StreamBuilder<List<RekoveryRequestModel>>(
                stream: repo.watchAllRequests(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final today = _dayOf(DateTime.now());
                  // Même filtre "à partir d'aujourd'hui" que côté adhérent, sauf
                  // pour les demandes [pending] : un coach doit voir et pouvoir
                  // traiter une demande en attente même si, par accident (fuseau
                  // horaire, adhérent qui a shifté sa demande), sa date est déjà
                  // légèrement passée. Les demandes [cancelled] sont en plus
                  // toujours masquées (10 août 2026, demande de Margaux) : une
                  // fois annulée par l'adhérent, une demande n'a plus d'intérêt à
                  // apparaître dans le planning Rekovery du coach.
                  final visible = snapshot.data!
                      .where((r) =>
                          r.status != RekoveryRequestStatus.cancelled &&
                          (!_dayOf(r.date).isBefore(today) ||
                              r.status == RekoveryRequestStatus.pending ||
                              r.status == RekoveryRequestStatus.proposed))
                      .toList()
                    ..sort((a, b) {
                      final dateCompare = a.date.compareTo(b.date);
                      return dateCompare != 0 ? dateCompare : a.startTime.compareTo(b.startTime);
                    });

                  // Fermetures Rekovery à partir d'aujourd'hui, une entrée par
                  // jour couvert (comme [groupSlotsByDay] pour les fermetures de
                  // salle) — pour afficher une carte "jour fermé" sur chacun.
                  final closedByDay = <DateTime, List<RekoveryClosureModel>>{};
                  for (final c in closures) {
                    if (_dayOf(c.endDate).isBefore(today)) continue;
                    var day = _dayOf(c.startDate).isBefore(today) ? today : _dayOf(c.startDate);
                    final lastDay = _dayOf(c.endDate);
                    while (!day.isAfter(lastDay)) {
                      closedByDay.putIfAbsent(day, () => []).add(c);
                      day = day.add(const Duration(days: 1));
                    }
                  }

                  // Fermetures DE LA SALLE (21 août 2026, demande de Margaux)
                  // — même principe, affichées au-dessus des éventuelles
                  // fermetures Rekovery du même jour.
                  final roomClosedByDay = <DateTime, List<ClosureModel>>{};
                  for (final c in roomClosures) {
                    if (_dayOf(c.endDate).isBefore(today)) continue;
                    var day = _dayOf(c.startDate).isBefore(today) ? today : _dayOf(c.startDate);
                    final lastDay = _dayOf(c.endDate);
                    while (!day.isAfter(lastDay)) {
                      roomClosedByDay.putIfAbsent(day, () => []).add(c);
                      day = day.add(const Duration(days: 1));
                    }
                  }

                  if (visible.isEmpty && closedByDay.isEmpty && roomClosedByDay.isEmpty) {
                    return const Center(child: Text('Aucune demande Rekovery pour le moment.'));
                  }

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
                        return ClosureBanner(
                          closure: item,
                          onLongPress: () => showClosureActionsSheet(context, item),
                        );
                      }
                      if (item is RekoveryClosureModel) {
                        return RekoveryClosedDayCard(
                          closure: item,
                          onLongPress: () => showRekoveryClosureActionsSheet(context, item),
                        );
                      }
                      final request = item as RekoveryRequestModel;
                      final canAct = request.status == RekoveryRequestStatus.pending ||
                          request.status == RekoveryRequestStatus.proposed ||
                          request.status == RekoveryRequestStatus.accepted;
                      return RekoveryRequestCard(
                        request: request,
                        showName: true,
                        // Tap simple (12 août 2026, demande de Margaux — remplace
                        // l'appui long du 6 août 2026, pas assez découvrable) :
                        // ouvre directement le choix accepter/refuser/proposer.
                        onTap:
                            canAct ? () => showCoachRekoveryActionsSheet(context, request) : null,
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: Padding(
        // Décale le bouton vers la gauche (padding à droite) et vers le
        // haut (padding en bas) par rapport à sa position par défaut
        // (bas-droite) — mêmes valeurs que `manage_planning_screen.dart`.
        padding: EdgeInsets.only(right: context.wp(20), bottom: context.hp(24)),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.black.withValues(alpha: 0.24),
                offset: const Offset(6, 3),
                blurRadius: 12,
              ),
            ],
          ),
          child: FloatingActionButton(
            backgroundColor: AppColors.black,
            elevation: 0,
            highlightElevation: 0,
            shape: const CircleBorder(),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddRekoveryClosureScreen()),
            ),
            child: Icon(Icons.add, color: AppColors.white, size: context.wp(32)),
          ),
        ),
      ),
    );
  }
}
