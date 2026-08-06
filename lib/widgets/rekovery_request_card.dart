import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/rekovery_request_model.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// "12/08 à 18h00" — utilisé pour la date/heure demandée ET, si présente,
/// la contre-proposition du coach.
String _fmtDateTime(DateTime date, String startTime) {
  final dayMonth = DateFormat('dd/MM', 'fr_FR').format(date);
  return '$dayMonth à ${startTime.replaceFirst(':', 'h')}';
}

/// Libellé + icône + couleur du statut d'une demande Rekovery (voir
/// `RekoveryRequestStatus`), affichés dans le [trailing] de
/// [RekoveryRequestCard] — sablier pour "En attente", coche pour "Confirmé"
/// (demande du 6 août 2026 : libellés raccourcis, icônes, alignement à
/// droite comme le bouton "S'inscrire" des créneaux de cours, voir
/// `slot_card.dart`).
(String, Color, IconData) _statusBadge(RekoveryRequestStatus status) {
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

/// Carte d'affichage d'une demande Rekovery, utilisée par les écrans coach
/// et adhérent (même rôle que [SlotCard] pour un cours). [showName] affiche
/// le nom de l'adhérent en titre.
///
/// [isOwn] (par défaut `true`, comportement inchangé côté coach — qui n'a
/// pas de notion de "propre" demande) grise l'icône/le libellé du statut
/// quand la carte représente la demande d'UN AUTRE adhérent — depuis le 6
/// août 2026, l'écran adhérent affiche aussi les créneaux Rekovery réservés
/// par les autres (utile pour choisir un créneau tranquille), avec leur nom,
/// mais seul le statut de l'utilisateur courant reste en couleur.
///
/// Un appui simple (tap) ne fait rien : seul un appui long ([onLongPress])
/// ouvre les actions disponibles pour ce statut et ce rôle — voir
/// `rekovery_request_actions_sheet.dart` (adhérent) et
/// `coach_rekovery_actions_sheet.dart` (coach). Ce changement (6 août 2026)
/// évite qu'un simple tap déclenche accidentellement une annulation.
class RekoveryRequestCard extends StatelessWidget {
  final RekoveryRequestModel request;
  final bool showName;
  final bool isOwn;
  final VoidCallback? onLongPress;

  const RekoveryRequestCard({
    super.key,
    required this.request,
    this.showName = false,
    this.isOwn = true,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final (statusLabel, badgeColor, statusIcon) = _statusBadge(request.status);
    final statusColor = isOwn ? badgeColor : AppColors.mediumGrey;

    final subtitleLines = <Widget>[
      Text(_fmtDateTime(request.date, request.startTime)),
    ];

    if (request.status == RekoveryRequestStatus.proposed &&
        request.proposedDate != null &&
        request.proposedStartTime != null) {
      subtitleLines.addAll([
        SizedBox(height: context.hp(2)),
        Text(
          'Proposition du coach : ${_fmtDateTime(request.proposedDate!, request.proposedStartTime!)}',
          style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w600),
        ),
      ]);
    }

    if (request.status == RekoveryRequestStatus.refused &&
        request.coachNote != null &&
        request.coachNote!.isNotEmpty) {
      subtitleLines.addAll([
        SizedBox(height: context.hp(2)),
        Text('« ${request.coachNote} »', style: const TextStyle(color: AppColors.mediumGrey)),
      ]);
    }

    return Card(
      color: AppColors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.lightGrey,
          foregroundColor: AppColors.black,
          child: const Icon(Icons.thermostat),
        ),
        title: Text(showName ? request.adherentName : 'Rekovery'),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: subtitleLines),
        isThreeLine: subtitleLines.length > 2,
        // Largeur FIXE (6 août 2026) : sans elle, la largeur du `Column`
        // s'ajuste au libellé ("En attente"/"Confirmé"/"Annulée"/...), donc
        // l'icône (centrée dans cette largeur variable) se retrouvait
        // décalée d'une carte à l'autre une fois plusieurs demandes
        // affichées les unes sous les autres. Avec une largeur commune à
        // toutes les cartes, l'icône reste toujours au même endroit
        // horizontalement, quel que soit le statut — les 3 icônes
        // (sablier/coche/croix) s'alignent donc sur le même axe vertical.
        trailing: SizedBox(
          width: context.wp(72),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(statusIcon, color: statusColor, size: context.wp(20)),
              SizedBox(height: context.hp(2)),
              Text(
                statusLabel,
                textAlign: TextAlign.center,
                style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: context.sp(12)),
              ),
            ],
          ),
        ),
        onLongPress: onLongPress,
      ),
    );
  }
}
