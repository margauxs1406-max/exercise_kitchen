import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle correspondant à la collection Firestore `closures` — une
/// fermeture de la salle sur une période (section "ajouter un évènement" du
/// planning coach), affichée en bandeau dans le planning coach ET adhérent,
/// un jour à la fois pour chaque jour couvert (voir `slot_grouping.dart`).
///
/// [startDate]/[endDate] : une fermeture peut s'étendre sur plusieurs jours
/// (`endDate` égale `startDate` pour une fermeture d'un seul jour). Les
/// fermetures créées avant l'ajout de ce champ n'ont qu'un ancien champ
/// `date` en base : [fromFirestore] retombe dessus si `startDate` est
/// absent, pour ne pas les casser.
///
/// [removedSlots] : copie brute (au format `SlotModel.toFirestore()`) des
/// créneaux supprimés à cause de cette fermeture (voir
/// `PlanningRepository.addClosure`/`updateClosure`), afin de pouvoir les
/// recréer si la période de fermeture est ensuite réduite ou déplacée —
/// sans cette copie, un cours duo/individuel/workshop supprimé serait perdu
/// définitivement (contrairement à un cours collectif, régénéré
/// automatiquement par son horaire fixe, voir
/// `PlanningRepository.ensureCollectiveSlotsForWeek`).
///
/// MVP : information affichée dans le planning uniquement, pas d'envoi
/// d'email/notification automatique pour l'instant.
class ClosureModel {
  final String id;
  final DateTime startDate;
  final DateTime endDate;
  final String message;
  final List<Map<String, dynamic>> removedSlots;

  const ClosureModel({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.message,
    this.removedSlots = const [],
  });

  factory ClosureModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final startTimestamp = (data['startDate'] ?? data['date']) as Timestamp;
    final startDate = startTimestamp.toDate();
    final endTimestamp = data['endDate'] as Timestamp?;
    return ClosureModel(
      id: doc.id,
      startDate: startDate,
      endDate: endTimestamp?.toDate() ?? startDate,
      message: data['message'] as String? ?? '',
      removedSlots: (data['removedSlots'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'message': message,
        'removedSlots': removedSlots,
      };
}