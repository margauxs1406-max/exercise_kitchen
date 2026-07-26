import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle correspondant à la collection Firestore `slots`.
///
/// Un `slot` est l'instance concrète d'un cours pour une semaine donnée
/// (date précise). Les créneaux des cours collectifs (fixes, voir
/// `default_collective_schedule.dart`) sont générés automatiquement par
/// `PlanningRepository.ensureCollectiveSlotsForWeek` ; les créneaux duo sont
/// créés ponctuellement par un coach (section 1.3).
///
/// [registeredCount] est maintenu par les Cloud Functions transactionnelles
/// (`registerForSlot` / `cancelRegistration`), jamais écrit directement par
/// le client, pour éviter les incohérences en cas d'inscriptions concurrentes.
class SlotModel {
  final String id;
  final String courseId;
  final String courseTitle;
  final String type; // 'collective' | 'duo' | 'individual' | 'workshop'
  final DateTime date;
  final String startTime;
  final String endTime;
  final int capacity;
  final int registeredCount;
  final int waitlistCount;
  // 'individual' uniquement : l'adhérent pour qui ce créneau a été poussé
  // par le coach (pas d'inscription libre, section 4.2).
  final String? adherentUid;
  // 'workshop' uniquement : description libre affichée sous l'heure.
  final String? description;

  const SlotModel({
    required this.id,
    required this.courseId,
    required this.courseTitle,
    required this.type,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.registeredCount,
    required this.waitlistCount,
    this.adherentUid,
    this.description,
  });

  bool get isFull => registeredCount >= capacity;

  /// Section 1.3bis / 2.2ter : un créneau avec un seul inscrit doit alerter
  /// le coach (et à terme être annulé). La logique d'alerte/notification
  /// elle-même est hors MVP (priorité 2), mais l'état est déjà exposé ici
  /// pour que l'UI puisse afficher un badge dès le MVP.
  bool get hasOnlyOneRegistered => registeredCount == 1;
  bool get isEmpty => registeredCount == 0;

  factory SlotModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return SlotModel(
      id: doc.id,
      courseId: data['courseId'] as String? ?? '',
      courseTitle: data['courseTitle'] as String? ?? '',
      type: data['type'] as String? ?? 'collective',
      date: (data['date'] as Timestamp).toDate(),
      startTime: data['startTime'] as String? ?? '00:00',
      endTime: data['endTime'] as String? ?? '00:00',
      capacity: data['capacity'] as int? ?? 1,
      registeredCount: data['registeredCount'] as int? ?? 0,
      waitlistCount: data['waitlistCount'] as int? ?? 0,
      adherentUid: data['adherentUid'] as String?,
      description: data['description'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'courseId': courseId,
        'courseTitle': courseTitle,
        'type': type,
        'date': Timestamp.fromDate(date),
        'startTime': startTime,
        'endTime': endTime,
        'capacity': capacity,
        'registeredCount': registeredCount,
        'waitlistCount': waitlistCount,
        'adherentUid': adherentUid,
        'description': description,
      };
}