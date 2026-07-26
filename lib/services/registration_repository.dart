import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/registration_model.dart';

enum RegisterOutcome { confirmed, waitlisted }

/// Inscriptions aux cours (section 2.2 / 2.2bis des spécifications).
///
/// Toutes les écritures passent par des Cloud Functions transactionnelles
/// (`registerForSlot` / `cancelRegistration`) plutôt que par des écritures
/// client directes : la capacité d'un créneau et la position en liste
/// d'attente doivent rester cohérentes même en cas d'inscriptions
/// concurrentes (deux adhérents qui s'inscrivent au même instant sur le
/// dernier créneau disponible, par exemple).
class RegistrationRepository {
  // La région doit correspondre à celle des Cloud Functions déployées
  // (voir functions/src/index.ts) — sinon les appels callable échouent.
  RegistrationRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instanceFor(region: 'australia-southeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  /// Inscrit l'adhérent courant à un créneau. Si le créneau est complet,
  /// l'adhérent est automatiquement placé en liste d'attente (2.2bis).
  Future<RegisterOutcome> registerForSlot(String slotId) async {
    final callable = _functions.httpsCallable('registerForSlot');
    final result = await callable.call<Map<String, dynamic>>({'slotId': slotId});
    final status = result.data['status'] as String;
    return status == 'waitlisted' ? RegisterOutcome.waitlisted : RegisterOutcome.confirmed;
  }

  /// Désinscrit l'adhérent courant. Si sa place était confirmée et qu'une
  /// liste d'attente existe, le premier inscrit en attente est promu
  /// automatiquement côté serveur.
  Future<void> cancelRegistration(String registrationId) {
    final callable = _functions.httpsCallable('cancelRegistration');
    return callable.call<void>({'registrationId': registrationId});
  }

  /// Inscriptions de l'adhérent courant pour la semaine affichée (utile pour
  /// savoir quels créneaux afficher comme "inscrit" / "en liste d'attente").
  Stream<List<RegistrationModel>> watchMyRegistrations(String uid) {
    return _firestore
        .collection('registrations')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map(RegistrationModel.fromFirestore).toList());
  }

  /// Coach : inscrits (confirmés et en liste d'attente) d'un créneau donné —
  /// utilisé par la pop-up ouverte en tapant sur une carte de cours
  /// collectif ou duo (section 1.3), pour afficher qui est inscrit et qui
  /// est en liste d'attente.
  Stream<List<RegistrationModel>> watchRegistrationsForSlot(String slotId) {
    return _firestore
        .collection('registrations')
        .where('slotId', isEqualTo: slotId)
        .snapshots()
        .map((snap) => snap.docs.map(RegistrationModel.fromFirestore).toList());
  }
}