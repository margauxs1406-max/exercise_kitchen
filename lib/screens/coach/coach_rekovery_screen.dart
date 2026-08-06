import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/rekovery_request_model.dart';
import '../../services/auth_service.dart';
import '../../services/rekovery_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../widgets/coach_rekovery_actions_sheet.dart';
import '../../widgets/day_header.dart';
import '../../widgets/rekovery_request_card.dart';
import '../../widgets/week_header.dart';

/// Onglet Rekovery côté coach — voit TOUTES les demandes de tous les
/// adhérents (avec leur nom), et peut accepter / refuser / proposer un
/// autre créneau (voir `coach_rekovery_actions_sheet.dart`).
///
/// Même logique de liste continue "à partir d'aujourd'hui" que côté
/// adhérent (`adherent_rekovery_screen.dart`) — pas de pagination par
/// semaine. Possède son propre en-tête ([WeekHeader], titre "Rekovery"),
/// comme `ManagePlanningScreen` pour le planning.
class CoachRekoveryScreen extends StatelessWidget {
  const CoachRekoveryScreen({super.key});

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final repo = context.read<RekoveryRepository>();
    final auth = context.read<AuthService>();

    return Scaffold(
      appBar: WeekHeader(
        onLogout: () => auth.signOut(),
        weekTypeContent: Text('REKOVERY', style: AppTheme.headerTitleStyle),
      ),
      body: StreamBuilder<List<RekoveryRequestModel>>(
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
          // légèrement passée.
          final visible = snapshot.data!
              .where((r) =>
                  !_dayOf(r.date).isBefore(today) ||
                  r.status == RekoveryRequestStatus.pending ||
                  r.status == RekoveryRequestStatus.proposed)
              .toList()
            ..sort((a, b) {
              final dateCompare = a.date.compareTo(b.date);
              return dateCompare != 0 ? dateCompare : a.startTime.compareTo(b.startTime);
            });

          if (visible.isEmpty) {
            return const Center(child: Text('Aucune demande Rekovery pour le moment.'));
          }

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
              final canAct = request.status == RekoveryRequestStatus.pending ||
                  request.status == RekoveryRequestStatus.proposed ||
                  request.status == RekoveryRequestStatus.accepted;
              return RekoveryRequestCard(
                request: request,
                showName: true,
                // Appui long uniquement (6 août 2026) : un simple tap ne
                // déclenche plus les actions, pour éviter une annulation
                // accidentelle.
                onLongPress: canAct ? () => showCoachRekoveryActionsSheet(context, request) : null,
              );
            },
          );
        },
      ),
    );
  }
}
