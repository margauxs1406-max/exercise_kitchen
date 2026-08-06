import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/rekovery_request_model.dart';
import '../../models/user_model.dart';
import '../../services/rekovery_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';

/// Historique complet des demandes Rekovery d'un adhérent, accessible
/// depuis sa fiche (`adherent_detail_screen.dart`) — demande du 6 août
/// 2026 : utile en cas de dégradation de l'espace de sauna/hydrothérapie ou
/// de réclamation sur le nombre de séances du carnet. Disponible pour TOUS
/// les adhérents (pas seulement "Rekovery seul"), même si la liste est
/// vide pour ceux qui n'ont jamais utilisé Rekovery.
///
/// Lecture seule : aucune action (accepter/refuser/annuler) n'est proposée
/// ici — celles-ci restent dans l'onglet Rekovery du coach
/// (`coach_rekovery_screen.dart`), qui ne montre que les demandes "à partir
/// d'aujourd'hui". Ici, TOUS les statuts et TOUTES les dates sont visibles,
/// triés du plus récent au plus ancien.
class AdherentRekoveryHistoryScreen extends StatelessWidget {
  final UserModel adherent;
  const AdherentRekoveryHistoryScreen({super.key, required this.adherent});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<RekoveryRepository>();
    return Scaffold(
      appBar: AppBar(title: Text('Historique Rekovery'.toUpperCase())),
      body: StreamBuilder<List<RekoveryRequestModel>>(
        stream: repo.watchRequestsForAdherent(adherent.uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final requests = List<RekoveryRequestModel>.from(snapshot.data!)
            ..sort((a, b) {
              final dateCompare = b.date.compareTo(a.date);
              return dateCompare != 0 ? dateCompare : b.startTime.compareTo(a.startTime);
            });

          if (requests.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: context.wp(24)),
                child: Text(
                  '${adherent.fullName} n\'a encore fait aucune demande Rekovery.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.mediumGrey),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: context.wp(12), vertical: context.hp(12)),
            itemCount: requests.length,
            separatorBuilder: (_, __) => SizedBox(height: context.hp(4)),
            itemBuilder: (context, i) => _HistoryTile(request: requests[i]),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final RekoveryRequestModel request;
  const _HistoryTile({required this.request});

  static (String, Color, IconData) _statusInfo(RekoveryRequestStatus status) {
    switch (status) {
      case RekoveryRequestStatus.pending:
        return ('En attente', AppColors.mustardYellow, Icons.hourglass_top);
      case RekoveryRequestStatus.accepted:
        return ('Confirmé', AppColors.flashyGreen, Icons.check_circle);
      case RekoveryRequestStatus.proposed:
        return ('Autre créneau proposé', AppColors.orange, Icons.swap_horiz);
      case RekoveryRequestStatus.refused:
        return ('Refusée', AppColors.darkGrey, Icons.close);
      case RekoveryRequestStatus.cancelled:
        return ('Annulée', AppColors.darkGrey, Icons.close);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _statusInfo(request.status);
    final dayMonth = DateFormat('dd/MM/yyyy', 'fr_FR').format(request.date);
    return Card(
      color: AppColors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.lightGrey,
          foregroundColor: AppColors.black,
          child: const Icon(Icons.thermostat),
        ),
        title: Text('$dayMonth à ${request.startTime.replaceFirst(':', 'h')}'),
        subtitle: request.coachNote != null && request.coachNote!.isNotEmpty
            ? Text('« ${request.coachNote} »', style: const TextStyle(color: AppColors.mediumGrey))
            : null,
        // Largeur fixe (6 août 2026, même correctif que `rekovery_request_card.dart`)
        // pour que l'icône reste au même endroit horizontalement quel que
        // soit le statut, une fois plusieurs lignes affichées les unes sous
        // les autres.
        trailing: SizedBox(
          width: context.wp(72),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: context.wp(20)),
              SizedBox(height: context.hp(2)),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: context.sp(12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
