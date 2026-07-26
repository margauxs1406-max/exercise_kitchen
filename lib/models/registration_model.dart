import 'package:cloud_firestore/cloud_firestore.dart';

enum RegistrationStatus { confirmed, waitlisted }

RegistrationStatus registrationStatusFromString(String value) =>
    value == 'waitlisted' ? RegistrationStatus.waitlisted : RegistrationStatus.confirmed;

String registrationStatusToString(RegistrationStatus status) =>
    status == RegistrationStatus.waitlisted ? 'waitlisted' : 'confirmed';

/// Modèle correspondant à la collection Firestore `registrations`.
///
/// Ces documents ne sont jamais écrits directement par le client : ils sont
/// créés/supprimés exclusivement par les Cloud Functions `registerForSlot`
/// et `cancelRegistration`, afin de garantir l'atomicité de la gestion de
/// capacité et de la liste d'attente (section 2.2bis des spécifications).
class RegistrationModel {
  final String id;
  final String slotId;
  final String userId;
  final RegistrationStatus status;
  final int? waitlistPosition; // uniquement si status == waitlisted
  final DateTime createdAt;

  const RegistrationModel({
    required this.id,
    required this.slotId,
    required this.userId,
    required this.status,
    required this.createdAt,
    this.waitlistPosition,
  });

  factory RegistrationModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return RegistrationModel(
      id: doc.id,
      slotId: data['slotId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      status: registrationStatusFromString(data['status'] as String? ?? 'confirmed'),
      waitlistPosition: data['waitlistPosition'] as int?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
