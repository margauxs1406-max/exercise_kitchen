import 'package:cloud_firestore/cloud_firestore.dart';

/// Cycle de vie d'une demande Rekovery (onglet dédié, section "Rekovery" des
/// spécifications) :
/// - [pending] : demande créée par l'adhérent, en attente d'une réponse du
///   coach — aucune séance n'est encore décomptée du carnet (voir
///   `UserModel.rekoveryCreditsRemaining`).
/// - [accepted] : le coach a validé la date/heure demandée telle quelle. Le
///   crédit est décompté à CE moment précis (pas à la création de la
///   demande) — voir `functions/src/index.ts` (`coachAcceptRekoveryRequest`).
/// - [proposed] : le coach propose une autre date/heure (voir
///   [proposedDate]/[proposedStartTime]) plutôt que d'accepter ou de
///   refuser directement — l'adhérent doit ensuite accepter (la demande
///   passe à [accepted], sur le créneau PROPOSÉ, et le crédit est décompté
///   à ce moment-là) ou refuser (la demande passe directement à [cancelled],
///   pas de nouvelle contre-proposition possible).
/// - [refused] : le coach refuse la demande — aucun crédit décompté.
/// - [cancelled] : la demande a été annulée, soit par l'adhérent avant la
///   réponse du coach, soit après acceptation (dans ce cas le crédit déjà
///   décompté est recrédité), soit après un refus de contre-proposition.
enum RekoveryRequestStatus { pending, accepted, proposed, refused, cancelled }

RekoveryRequestStatus rekoveryRequestStatusFromString(String value) {
  switch (value) {
    case 'accepted':
      return RekoveryRequestStatus.accepted;
    case 'proposed':
      return RekoveryRequestStatus.proposed;
    case 'refused':
      return RekoveryRequestStatus.refused;
    case 'cancelled':
      return RekoveryRequestStatus.cancelled;
    default:
      return RekoveryRequestStatus.pending;
  }
}

String rekoveryRequestStatusToString(RekoveryRequestStatus status) {
  switch (status) {
    case RekoveryRequestStatus.accepted:
      return 'accepted';
    case RekoveryRequestStatus.proposed:
      return 'proposed';
    case RekoveryRequestStatus.refused:
      return 'refused';
    case RekoveryRequestStatus.cancelled:
      return 'cancelled';
    case RekoveryRequestStatus.pending:
      return 'pending';
  }
}

/// Modèle correspondant à la collection Firestore `rekoveryRequests`.
///
/// Ces documents ne sont jamais écrits directement par le client : toutes
/// les écritures (création, acceptation, refus, contre-proposition, réponse
/// à une contre-proposition, annulation) passent par des Cloud Functions
/// (voir `functions/src/index.ts`), pour garantir l'atomicité du
/// décompte/recrédit du carnet Rekovery — même logique que `registrations`
/// pour la capacité des créneaux (voir `registration_model.dart`).
class RekoveryRequestModel {
  final String id;
  final String adherentUid;
  // Dénormalisé (comme sur l'ancien `RekoverySessionModel`) : le coach voit
  // la liste de toutes les demandes, pas seulement les siennes — évite une
  // jointure/requête supplémentaire pour afficher le nom.
  final String adherentName;
  final DateTime date;
  final String startTime;
  final RekoveryRequestStatus status;
  // Uniquement si status == proposed : date/heure suggérée par le coach en
  // remplacement de [date]/[startTime] initialement demandés.
  final DateTime? proposedDate;
  final String? proposedStartTime;
  // Note libre du coach, affichée à l'adhérent : motif de refus, ou message
  // accompagnant une contre-proposition (ex. "Salle prise à cette heure-là").
  final String? coachNote;
  final DateTime createdAt;

  const RekoveryRequestModel({
    required this.id,
    required this.adherentUid,
    required this.adherentName,
    required this.date,
    required this.startTime,
    required this.status,
    required this.createdAt,
    this.proposedDate,
    this.proposedStartTime,
    this.coachNote,
  });

  factory RekoveryRequestModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return RekoveryRequestModel(
      id: doc.id,
      adherentUid: data['adherentUid'] as String? ?? '',
      adherentName: data['adherentName'] as String? ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      startTime: data['startTime'] as String? ?? '',
      status: rekoveryRequestStatusFromString(data['status'] as String? ?? 'pending'),
      proposedDate: (data['proposedDate'] as Timestamp?)?.toDate(),
      proposedStartTime: data['proposedStartTime'] as String?,
      coachNote: data['coachNote'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'adherentUid': adherentUid,
        'adherentName': adherentName,
        'date': Timestamp.fromDate(date),
        'startTime': startTime,
        'status': rekoveryRequestStatusToString(status),
        'proposedDate': proposedDate != null ? Timestamp.fromDate(proposedDate!) : null,
        'proposedStartTime': proposedStartTime,
        'coachNote': coachNote,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
