import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle correspondant à la collection Firestore `rekoveryClosures` — une
/// fermeture PONCTUELLE de l'espace Rekovery, ajoutée par un coach (bouton
/// "+" de `coach_rekovery_screen.dart`, écran
/// `add_rekovery_closure_screen.dart`) — 21 août 2026, demande de Margaux.
///
/// À bien distinguer de `ClosureModel` (`closure_model.dart`) : une
/// fermeture DE LA SALLE annule aussi tous les cours prévus sur sa période
/// (voir `PlanningRepository.addClosure`) — une fermeture Rekovery, elle, ne
/// touche QUE l'espace Rekovery, la salle reste ouverte pour le reste (cours
/// collectifs, duo, individuels...). Elle ne supprime donc aucun créneau, et
/// n'a pas besoin de `removedSlots`.
///
/// Une fermeture de la salle bloque déjà, de fait, l'accès à Rekovery ce
/// jour-là (voir `RekoveryReserveBar._isClosed`, qui vérifie les DEUX
/// collections) — les fermetures Rekovery servent à fermer L'ESPACE
/// REKOVERY seul, sans fermer toute la salle (ex. une heure de maintenance
/// du matériel).
///
/// Deux formes possibles (section "Ajouter au planning Rekovery",
/// `SegmentedButton` Temporaire/Prolongée) :
/// - [isTemporary] == true : une seule journée ([startDate] == [endDate]),
///   avec une plage horaire précise ([startTime]/[endTime], format "HH:mm")
///   — ex. "12h-16h le jeudi 10 août".
/// - [isTemporary] == false : une période de plusieurs jours entiers
///   ([startDate]..[endDate]), sans heure ([startTime]/[endTime] restent
///   `null`) — ex. "du jeudi 10 au mercredi 24 août".
///
/// [title] : par défaut "Rekovery temporairement inaccessible" (modifiable
/// par le coach, voir `add_rekovery_closure_screen.dart`) — sert À LA FOIS
/// de titre affiché sur les cartes "jour fermé" des écrans Rekovery (voir
/// `rekovery_closed_day_card.dart`) ET de titre de la notification envoyée
/// aux adhérents formule Rekovery (voir `functions/src/index.ts`,
/// `onRekoveryClosureCreated`).
///
/// [message] : texte libre FACULTATIF pour les adhérents (21 août 2026,
/// demande de Margaux — même principe que le message d'une fermeture de
/// salle, voir `ClosureModel.message`) — affiché sous l'heure sur la carte
/// "jour fermé" s'il est renseigné, et ajouté à la fin de la notification
/// envoyée. `null`/vide = rien de plus que le texte auto-généré habituel.
class RekoveryClosureModel {
  final String id;
  final DateTime startDate;
  final DateTime endDate;
  final String title;
  final bool isTemporary;
  final String? startTime;
  final String? endTime;
  final String? message;
  final DateTime createdAt;

  const RekoveryClosureModel({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.title,
    required this.isTemporary,
    required this.createdAt,
    this.startTime,
    this.endTime,
    this.message,
  });

  factory RekoveryClosureModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return RekoveryClosureModel(
      id: doc.id,
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      title: data['title'] as String? ?? 'Rekovery temporairement inaccessible',
      isTemporary: data['isTemporary'] as bool? ?? true,
      startTime: data['startTime'] as String?,
      endTime: data['endTime'] as String?,
      message: data['message'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'title': title,
        'isTemporary': isTemporary,
        'startTime': startTime,
        'endTime': endTime,
        'message': message,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
