import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle correspondant à la collection Firestore `rekoverySessions` —
/// section 2.4bis (formule "Rekovery") : un adhérent indique l'heure à
/// laquelle il compte utiliser l'espace rekovery (sauna...) pour que les
/// coachs puissent anticiper et l'allumer avant son arrivée.
///
/// [adherentName] est dupliqué ici (dénormalisé) au moment de la création
/// pour que le planning coach puisse afficher "qui vient" sans avoir à
/// recharger la fiche adhérent correspondante à chaque affichage.
class RekoverySessionModel {
  final String id;
  final DateTime date;
  final String startTime;
  final String adherentUid;
  final String adherentName;

  const RekoverySessionModel({
    required this.id,
    required this.date,
    required this.startTime,
    required this.adherentUid,
    required this.adherentName,
  });

  factory RekoverySessionModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return RekoverySessionModel(
      id: doc.id,
      date: (data['date'] as Timestamp).toDate(),
      startTime: data['startTime'] as String? ?? '00:00',
      adherentUid: data['adherentUid'] as String? ?? '',
      adherentName: data['adherentName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'date': Timestamp.fromDate(date),
        'startTime': startTime,
        'adherentUid': adherentUid,
        'adherentName': adherentName,
      };
}