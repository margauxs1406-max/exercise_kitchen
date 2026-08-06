import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/user_model.dart';

/// Résultat renvoyé par la Cloud Function `createAdherentAccount`.
class CreateAdherentResult {
  final String uid;
  final bool emailSent;
  const CreateAdherentResult({required this.uid, required this.emailSent});
}

/// Gestion des comptes — réservée aux coachs (section 3).
///
/// La création d'un compte adhérent passe obligatoirement par une Cloud
/// Function (Admin SDK) : créer un utilisateur Firebase Auth depuis le
/// client déconnecterait le coach en cours de session (le SDK client bascule
/// automatiquement la session sur le nouvel utilisateur créé), ce qui est
/// inacceptable en usage courant pour un coach qui enchaîne les créations.
class UserRepository {
  // La région doit correspondre à celle des Cloud Functions déployées
  // (voir functions/src/index.ts) — sinon les appels callable échouent.
  UserRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instanceFor(region: 'australia-southeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  /// Coach : crée un compte adhérent (prénom, nom, email, téléphone
  /// optionnel, formules souscrites). Un mot de passe temporaire est généré
  /// côté serveur et envoyé par email automatiquement.
  Future<CreateAdherentResult> createAdherentAccount({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    Set<String> formulas = const {},
  }) async {
    final callable = _functions.httpsCallable('createAdherentAccount');
    final result = await callable.call<Map<String, dynamic>>({
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'formulas': formulas.toList(),
    });
    return CreateAdherentResult(
      uid: result.data['uid'] as String,
      emailSent: result.data['emailSent'] as bool? ?? false,
    );
  }

  /// Coach : clôture un compte adhérent — la connexion est immédiatement
  /// bloquée (les règles Firestore + AuthService.refreshCurrentUser
  /// déconnectent l'utilisateur dès que `status` passe à `closed`).
  Future<void> closeAccount(String uid) {
    return _firestore.collection('users').doc(uid).update({'status': 'closed'});
  }

  Future<void> reopenAccount(String uid) {
    return _firestore.collection('users').doc(uid).update({'status': 'active'});
  }

  /// Coach : liste de tous les adhérents (actifs et clôturés), triée par
  /// prénom — l'ordre affiché à l'écran est "Prénom Nom" (`fullName`), donc
  /// le tri doit porter sur le même champ pour rester cohérent.
  Stream<List<UserModel>> watchAdherents() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'adherent')
        .orderBy('firstName')
        .snapshots()
        .map((snap) => snap.docs.map(UserModel.fromFirestore).toList());
  }

  /// Fiche d'un adhérent (section 5) — mise à jour en direct : permet à la
  /// page de détail de refléter tout changement (statut, formules...) sans
  /// avoir à revenir en arrière.
  Stream<UserModel?> watchUser(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? UserModel.fromFirestore(doc) : null);
  }

  /// Coach : modifie les formules souscrites par un adhérent — modifiables
  /// à tout moment depuis sa fiche (section 5).
  Future<void> updateFormulas(String uid, Set<String> formulas) {
    return _firestore.collection('users').doc(uid).update({
      'formulas': formulas.toList(),
    });
  }

  /// Coach : modifie le numéro de téléphone d'un adhérent, modifiable à tout
  /// moment depuis sa fiche (section 5) — `null`/vide efface le numéro
  /// (redevient "Téléphone non renseigné").
  Future<void> updatePhone(String uid, String? phone) {
    return _firestore.collection('users').doc(uid).update({
      'phone': (phone == null || phone.isEmpty) ? null : phone,
    });
  }

  /// Coach : ajuste manuellement le carnet Rekovery d'un adhérent "Rekovery
  /// seul" (renouvellement, correction...) — voir
  /// `UserModel.rekoveryCreditsRemaining`/`isRekoverySoloOnly`. Écriture
  /// directe (pas une Cloud Function) : contrairement au
  /// décompte/recrédit automatique à l'acceptation/l'annulation d'une
  /// demande (voir `functions/src/index.ts`), qui doit être transactionnel
  /// pour rester cohérent en cas d'actions concurrentes, cet ajustement
  /// manuel par un coach de confiance n'a pas ce besoin d'atomicité.
  Future<void> updateRekoveryCredits(String uid, int credits) {
    return _firestore.collection('users').doc(uid).update({
      'rekoveryCreditsRemaining': credits < 0 ? 0 : credits,
    });
  }

  /// Adhérent : active/désactive le déverrouillage biométrique depuis son
  /// écran de profil — pour l'instant un simple réglage enregistré (ne
  /// bloque pas encore réellement l'accès à l'app, voir
  /// `adherent_profile_screen.dart`).
  Future<void> updateBiometricUnlockEnabled(String uid, bool enabled) {
    return _firestore.collection('users').doc(uid).update({
      'biometricUnlockEnabled': enabled,
    });
  }

  /// Adhérent : active/désactive un type de notification précis depuis son
  /// écran de profil (voir `kNotificationTypes` dans
  /// `notification_settings_screen.dart`) — lu côté Cloud Functions avant
  /// l'envoi de chaque notification concernée.
  Future<void> updateNotificationPref(String uid, String key, bool enabled) {
    return _firestore.collection('users').doc(uid).update({
      'notificationPrefs.$key': enabled,
    });
  }

  /// Récupère en une fois les fiches (prénom/nom...) de plusieurs adhérents
  /// à partir de leurs identifiants — utilisé pour afficher un nom lisible
  /// dans la pop-up "inscrits / liste d'attente" d'un créneau (section 1.3),
  /// où l'on ne connaît au départ que les `userId` des inscriptions.
  Future<Map<String, UserModel>> getUsersByIds(List<String> uids) async {
    if (uids.isEmpty) return {};
    // Firestore limite `whereIn` à 30 valeurs : on découpe en lots au
    // besoin — largement suffisant pour la capacité d'un créneau, mais on
    // reste robuste si elle venait à augmenter.
    final chunks = <List<String>>[];
    for (var i = 0; i < uids.length; i += 30) {
      chunks.add(uids.sublist(i, i + 30 > uids.length ? uids.length : i + 30));
    }
    final result = <String, UserModel>{};
    for (final chunk in chunks) {
      final snap = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        final user = UserModel.fromFirestore(doc);
        result[user.uid] = user;
      }
    }
    return result;
  }
}