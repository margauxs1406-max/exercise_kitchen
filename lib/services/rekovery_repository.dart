import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
}