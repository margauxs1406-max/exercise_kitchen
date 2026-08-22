import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/rekovery_closure_model.dart';
import '../models/rekovery_request_model.dart';

/// Demandes Rekovery (onglet dédié — voir `rekovery_request_model.dart` pour
/// le détail du cycle de vie pending → accepted/proposed/refused/cancelled).
///
/// Toutes les écritures passent par des Cloud Functions transactionnelles
/// (comme `RegistrationRepository`) : le décompte/recrédit du carnet de 10
/// séances d'un adhérent "Rekovery seul" (voir
/// `UserModel.rekoveryCreditsRemaining`) doit rester cohérent même en cas
/// d'actions concurrentes (ex. le coach accepte pile au moment où l'adhérent
/// annule sa demande).
class RekoveryRepository {
  RekoveryRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instanceFor(region: 'australia-southeast1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection('rekoveryRequests');

  CollectionReference<Map<String, dynamic>> get _closures =>
      _firestore.collection('rekoveryClosures');

  /// Adhérent : ses propres demandes, toutes confondues (pending, acceptées,
  /// proposées, refusées, annulées) — pas de flux ; le filtrage à
  /// l'affichage ("à venir" / "historique") se fait côté écran.
  Stream<List<RekoveryRequestModel>> watchMyRequests(String adherentUid) {
    return _requests
        .where('adherentUid', isEqualTo: adherentUid)
        .orderBy('date')
        .orderBy('startTime')
        .snapshots()
        .map((snap) => snap.docs.map(RekoveryRequestModel.fromFirestore).toList());
  }

  /// Coach : toutes les demandes de tous les adhérents, avec leur nom
  /// (dénormalisé sur le document, voir `RekoveryRequestModel.adherentName`).
  Stream<List<RekoveryRequestModel>> watchAllRequests() {
    return _requests
        .orderBy('date')
        .orderBy('startTime')
        .snapshots()
        .map((snap) => snap.docs.map(RekoveryRequestModel.fromFirestore).toList());
  }

  /// Coach : historique complet des demandes Rekovery d'un adhérent précis
  /// (fiche adhérent — section 5), tous statuts confondus, pour vérifier le
  /// nombre de séances en cas de réclamation ou de dégradation de l'espace.
  /// Même requête que [watchMyRequests] (les règles Firestore autorisent
  /// déjà un coach à lire les demandes de n'importe quel adhérent) — nom
  /// distinct uniquement pour la lisibilité côté appelant.
  Stream<List<RekoveryRequestModel>> watchRequestsForAdherent(String adherentUid) =>
      watchMyRequests(adherentUid);

  /// Adhérent : crée une nouvelle demande pour la date/heure choisies.
  /// N'échoue PAS si le carnet est déjà à 0 — voir
  /// `functions/src/index.ts` (`requestRekoverySlot`) : le crédit n'est
  /// vérifié/décompté qu'à l'acceptation par le coach, pas à la demande.
  ///
  /// `.toUtc()` avant `.toIso8601String()` (10 août 2026, corrige un bug de
  /// décalage de 11h signalé par Margaux — Nouméa est UTC+11) : [date] est
  /// une `DateTime` LOCALE (minuit du jour choisi, fuseau de l'appareil,
  /// donc Nouméa) — `toIso8601String()` sur une `DateTime` locale n'inclut
  /// AUCUN indicateur de fuseau (pas de "Z", pas de "+11:00"), contrairement
  /// à son équivalent JavaScript. Côté Cloud Functions, `new Date(...)` sur
  /// une telle chaîne SANS fuseau est interprétée comme un instant UTC
  /// (l'environnement d'exécution tourne en UTC) — l'heure demandée se
  /// retrouvait donc décalée de 11h. `.toUtc()` convertit d'abord en le bon
  /// instant absolu ; la chaîne obtenue se termine par "Z" et est alors
  /// interprétée sans ambiguïté, quel que soit le fuseau du serveur.
  Future<void> requestSlot({required DateTime date, required String startTime}) {
    final callable = _functions.httpsCallable('requestRekoverySlot');
    return callable.call<void>({
      'date': date.toUtc().toIso8601String(),
      'startTime': startTime,
    });
  }

  /// Coach : accepte une demande telle quelle (date/heure inchangées). Pour
  /// un adhérent "Rekovery seul", décompte une séance du carnet — échoue si
  /// le carnet est déjà à 0 (voir `functions/src/index.ts`).
  Future<void> acceptRequest(String requestId) {
    final callable = _functions.httpsCallable('coachAcceptRekoveryRequest');
    return callable.call<void>({'requestId': requestId});
  }

  /// Coach : refuse une demande — aucun crédit décompté.
  Future<void> refuseRequest(String requestId, {String? note}) {
    final callable = _functions.httpsCallable('coachRefuseRekoveryRequest');
    return callable.call<void>({'requestId': requestId, 'note': note});
  }

  /// Coach : propose une autre date/heure plutôt que d'accepter/refuser
  /// directement. La demande passe à `proposed`, en attente de la réponse
  /// de l'adhérent (voir [respondToProposal]). Pas de message libre pour le
  /// coach ici (retiré le 6 août 2026) — seul [refuseRequest] garde un motif
  /// facultatif.
  ///
  /// `.toUtc()` : voir [requestSlot], même correctif du 10 août 2026.
  Future<void> proposeAlternative(
    String requestId, {
    required DateTime proposedDate,
    required String proposedStartTime,
  }) {
    final callable = _functions.httpsCallable('proposeRekoveryAlternative');
    return callable.call<void>({
      'requestId': requestId,
      'proposedDate': proposedDate.toUtc().toIso8601String(),
      'proposedStartTime': proposedStartTime,
    });
  }

  /// Adhérent : répond à une contre-proposition du coach. [accept] à `true`
  /// confirme le créneau proposé (décompte le carnet, comme une acceptation
  /// directe) ; à `false`, la demande est annulée d'office — pas de nouvelle
  /// contre-proposition possible (voir `RekoveryRequestModel`, statut
  /// `proposed`).
  Future<void> respondToProposal(String requestId, {required bool accept}) {
    final callable = _functions.httpsCallable('respondToRekoveryProposal');
    return callable.call<void>({'requestId': requestId, 'accept': accept});
  }

  /// Adhérent ou coach : annule une demande — quel que soit son statut
  /// actuel. Si elle était acceptée (crédit déjà décompté), le carnet de
  /// l'adhérent est recrédité automatiquement côté serveur.
  Future<void> cancelRequest(String requestId) {
    final callable = _functions.httpsCallable('cancelRekoveryRequest');
    return callable.call<void>({'requestId': requestId});
  }

  /// Adhérent : modifie SA PROPRE demande (nouvelle date/heure), qu'elle
  /// soit [pending], [proposed] ou [accepted] — dans tous les cas elle
  /// repasse à [pending], car le coach doit de nouveau la valider (demande
  /// du 6 août 2026, action "Modifier" du menu à appui long). Si elle était
  /// [accepted] (crédit déjà décompté), le carnet est recrédité
  /// automatiquement côté serveur, comme pour [cancelRequest].
  ///
  /// `.toUtc()` : voir [requestSlot], même correctif du 10 août 2026.
  Future<void> modifyRequest(
    String requestId, {
    required DateTime date,
    required String startTime,
  }) {
    final callable = _functions.httpsCallable('modifyRekoveryRequest');
    return callable.call<void>({
      'requestId': requestId,
      'date': date.toUtc().toIso8601String(),
      'startTime': startTime,
    });
  }

  // -----------------------------------------------------------------
  // Fermetures Rekovery (bouton "+" côté coach — 21 août 2026)
  // -----------------------------------------------------------------

  /// Coach ET adhérent : toutes les fermetures Rekovery existantes, triées
  /// par date de début — flux en direct (contrairement à
  /// `PlanningRepository.fetchAllClosures`, un simple aller-retour) pour que
  /// le blocage de réservation ([RekoveryReserveBar]) et les cartes "jour
  /// fermé" ([RekoveryClosedDayCard]) se mettent à jour immédiatement dès
  /// qu'un coach ajoute une fermeture ("se mettre à jour si le coach
  /// rajoute une fermeture rekovery", demande du 21 août 2026). Écriture
  /// directe côté coach (pas de Cloud Function, contrairement aux
  /// `rekoveryRequests` ci-dessus) : aucun décompte de carnet à protéger
  /// ici, même principe que `closures` (fermetures de salle) — voir
  /// `firestore.rules`.
  Stream<List<RekoveryClosureModel>> watchAllClosures() {
    return _closures
        .orderBy('startDate')
        .snapshots()
        .map((snap) => snap.docs.map(RekoveryClosureModel.fromFirestore).toList());
  }

  /// Coach : ferme l'espace Rekovery pour quelques heures un jour précis
  /// (option "Fermeture temporaire" de `add_rekovery_closure_screen.dart`).
  /// [message] : facultatif (21 août 2026), voir `RekoveryClosureModel.message`.
  Future<void> addTemporaryClosure({
    required DateTime date,
    required String startTime,
    required String endTime,
    required String title,
    String? message,
  }) {
    final day = DateTime(date.year, date.month, date.day);
    return _closures.add(
      RekoveryClosureModel(
        id: '',
        startDate: day,
        endDate: day,
        title: title,
        isTemporary: true,
        startTime: startTime,
        endTime: endTime,
        message: message,
        createdAt: DateTime.now(),
      ).toFirestore(),
    );
  }

  /// Coach : ferme l'espace Rekovery sur plusieurs jours entiers (option
  /// "Fermeture prolongée" de `add_rekovery_closure_screen.dart`).
  /// [message] : facultatif (21 août 2026), voir `RekoveryClosureModel.message`.
  Future<void> addExtendedClosure({
    required DateTime startDate,
    required DateTime endDate,
    required String title,
    String? message,
  }) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return _closures.add(
      RekoveryClosureModel(
        id: '',
        startDate: start,
        endDate: end,
        title: title,
        isTemporary: false,
        message: message,
        createdAt: DateTime.now(),
      ).toFirestore(),
    );
  }

  /// Coach : modifie une fermeture Rekovery déjà créée (appui long sur sa
  /// carte, action "Modifier" — 21 août 2026, demande de Margaux, voir
  /// `rekovery_closure_actions_sheet.dart`). La forme ([isTemporary]) n'est
  /// pas modifiable ici (recréer via le bouton "+" reste plus simple que de
  /// faire basculer un formulaire d'édition entre les deux formes très
  /// différentes) — seuls le créneau (date+heures ou période), le titre et
  /// le message le sont. [startTime]/[endTime] sont ignorés pour une
  /// fermeture prolongée (jamais écrits, restent `null` en base).
  Future<void> updateClosure({
    required String closureId,
    required bool isTemporary,
    required DateTime startDate,
    required DateTime endDate,
    String? startTime,
    String? endTime,
    required String title,
    String? message,
  }) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return _closures.doc(closureId).update({
      'startDate': Timestamp.fromDate(start),
      'endDate': Timestamp.fromDate(isTemporary ? start : end),
      'title': title,
      'startTime': isTemporary ? startTime : null,
      'endTime': isTemporary ? endTime : null,
      'message': message,
    });
  }

  /// Coach : supprime une fermeture Rekovery (appui long sur sa carte, voir
  /// `rekovery_closure_actions_sheet.dart`).
  Future<void> deleteClosure(String closureId) => _closures.doc(closureId).delete();
}