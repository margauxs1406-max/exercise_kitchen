import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/default_collective_schedule.dart';
import '../models/closure_model.dart';
import '../models/slot_model.dart';

/// Section 1.4 : les 6 types de semaine du cycle d'entraînement (2
/// basiques, 2 intermédiaires, 2 dynamiques), dans l'ordre où ils se
/// suivent. Utilisé à la fois pour l'affichage (voir les écrans coach/
/// adhérent, qui associent chaque valeur à un libellé du type "Basique
/// 1/2") et pour faire avancer le cycle automatiquement d'une semaine à
/// l'autre — voir [PlanningRepository.ensureWeekTypesAhead]/[PlanningRepository.setWeekType].
const List<String> kWeekTypeCycle = [
  'basique_1',
  'basique_2',
  'intermediaire_1',
  'intermediaire_2',
  'dynamique_1',
  'dynamique_2',
];

/// Le type suivant dans le cycle de 6 semaines, après [type] (boucle sur
/// [kWeekTypeCycle] une fois arrivé au bout). Une valeur inconnue (donnée
/// d'un ancien format, avant l'introduction du cycle) retombe sur le tout
/// premier type plutôt que de planter.
String _nextWeekType(String type) {
  final i = kWeekTypeCycle.indexOf(type);
  return kWeekTypeCycle[(i == -1 ? 0 : i + 1) % kWeekTypeCycle.length];
}

/// Type situé [weeksOffset] semaines après celui où [baseType] a cours,
/// dans le cycle de 6 (accepte un décalage négatif). Permet de retrouver
/// directement le type d'une semaine éloignée sans avoir à parcourir
/// semaine par semaine tout l'écart qui la sépare de la dernière semaine
/// connue (utile après une longue absence côté coach, voir
/// [PlanningRepository.ensureWeekTypesAhead]).
String _weekTypeAtOffset(String baseType, int weeksOffset) {
  final baseIndex = kWeekTypeCycle.indexOf(baseType);
  final start = baseIndex == -1 ? 0 : baseIndex;
  final n = kWeekTypeCycle.length;
  final idx = ((start + weeksOffset) % n + n) % n;
  return kWeekTypeCycle[idx];
}

/// Accès en lecture au planning (`slots`) et gestion des cours par le coach
/// (section 1.3/1.4).
///
/// Les cours collectifs n'ont plus d'écran de création : leurs horaires sont
/// fixes (voir `default_collective_schedule.dart`) et les créneaux de la
/// semaine sont générés automatiquement par [ensureCollectiveSlotsForWeek],
/// appelée depuis l'écran de planning du coach. Seuls les cours duo restent
/// ajoutés manuellement, ponctuellement, via [addDuoSlotForWeek].
class PlanningRepository {
  PlanningRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _slots => _firestore.collection('slots');
  CollectionReference<Map<String, dynamic>> get _weekTypes =>
      _firestore.collection('weekTypes');
  CollectionReference<Map<String, dynamic>> get _closures =>
      _firestore.collection('closures');

  /// Identifiant de document `weekTypes` : le lundi de la semaine, au format
  /// `AAAA-MM-JJ` (stable, lisible, sans dépendre de l'heure/fuseau).
  String _weekTypeDocId(DateTime weekStart) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${weekStart.year}-${pad2(weekStart.month)}-${pad2(weekStart.day)}';
  }

  /// Créneaux de la semaine dont le lundi est [weekStart] (inclus) jusqu'au
  /// dimanche suivant (inclus), triés par date puis heure de début.
  Stream<List<SlotModel>> watchWeekSlots(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 7));
    return _slots
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
        .where('date', isLessThan: Timestamp.fromDate(weekEnd))
        .orderBy('date')
        // Tri secondaire par heure de début : deux créneaux du même jour ont
        // le même `date` (l'heure n'y est pas stockée), donc sans ce second
        // tri, Firestore ne garantit aucun ordre stable entre eux — d'où
        // l'ordre qui semblait changer d'une semaine à l'autre.
        .orderBy('startTime')
        .snapshots()
        .map((snap) => snap.docs.map(SlotModel.fromFirestore).toList());
  }

  /// Coach : ajoute un cours duo ponctuel directement au planning d'une
  /// semaine donnée (section 1.3), en plus des créneaux collectifs fixes.
  /// Titre imposé à "Duo" et durée fixe d'1h (pas de saisie côté coach).
  ///
  /// Renvoie l'identifiant du créneau créé (7 août 2026) — nécessaire pour
  /// pouvoir y inscrire immédiatement les 2 adhérents prérenseignés, voir
  /// `add_course_screen.dart` et `RegistrationRepository.coachRegisterAdherentForSlot`.
  /// Auparavant la référence renvoyée par `_slots.add` était ignorée : il
  /// n'existait alors aucun moyen d'inscrire quelqu'un juste après création.
  Future<String> addDuoSlotForWeek({
    required DateTime date,
    required String startTime,
    int capacity = 2,
  }) async {
    final slot = SlotModel(
      id: '',
      courseId: 'duo-${date.toIso8601String()}-$startTime',
      courseTitle: 'Duo',
      type: 'duo',
      date: date,
      startTime: startTime,
      endTime: addOneHour(startTime),
      capacity: capacity,
      registeredCount: 0,
      waitlistCount: 0,
    );
    final ref = await _slots.add(slot.toFirestore());
    return ref.id;
  }

  /// Garantit que les créneaux collectifs fixes (voir
  /// [kDefaultCollectiveSchedule]) existent bien pour la semaine dont le
  /// lundi est [weekStart] — les crée s'ils manquent, ne fait rien sinon
  /// (idempotent, peut être appelée à chaque ouverture du planning).
  ///
  /// Un jour couvert par une fermeture (voir `ClosureModel`) est
  /// explicitement exclu : sans cette vérification, un créneau collectif
  /// supprimé par [addClosure]/[updateClosure] réapparaîtrait dès la
  /// prochaine ouverture du planning coach, puisque cette méthode le
  /// recréerait en le trouvant absent.
  Future<void> ensureCollectiveSlotsForWeek(DateTime weekStart) async {
    final weekEnd = weekStart.add(const Duration(days: 7));
    final closedDays = await _closedDaysInRange(weekStart, weekEnd);

    for (final def in kDefaultCollectiveSchedule) {
      final date = weekStart.add(Duration(days: def.dayOfWeek - 1));
      if (closedDays.contains(DateTime(date.year, date.month, date.day))) continue;

      final existing = await _slots
          .where('type', isEqualTo: 'collective')
          .where('date', isEqualTo: Timestamp.fromDate(date))
          .where('startTime', isEqualTo: def.startTime)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) continue;

      final slot = SlotModel(
        id: '',
        courseId: 'collectif-${def.dayOfWeek}-${def.startTime}',
        courseTitle: 'Collectif',
        type: 'collective',
        date: date,
        startTime: def.startTime,
        endTime: addOneHour(def.startTime),
        capacity: kDefaultCollectiveCapacity,
        registeredCount: 0,
        waitlistCount: 0,
      );
      await _slots.add(slot.toFirestore());
    }
  }

  /// Ensemble des jours (minuit, un `Set` pour une recherche `contains` en
  /// O(1)) compris dans `[rangeStart, rangeEnd)` et couverts par au moins
  /// une fermeture existante. Récupère toutes les fermetures (leur nombre
  /// reste faible pour une seule salle) plutôt qu'une requête Firestore
  /// filtrée : une fermeture chevauche une plage sur DEUX champs
  /// (`startDate`/`endDate`), ce que Firestore ne permet pas nativement en
  /// une seule requête sans index composite.
  Future<Set<DateTime>> _closedDaysInRange(DateTime rangeStart, DateTime rangeEnd) async {
    final closuresSnap = await _closures.get();
    final closedDays = <DateTime>{};
    for (final doc in closuresSnap.docs) {
      final c = ClosureModel.fromFirestore(doc);
      // Pas de chevauchement avec `[rangeStart, rangeEnd)` : rien à faire.
      if (!c.startDate.isBefore(rangeEnd) || c.endDate.isBefore(rangeStart)) continue;

      var day = c.startDate.isBefore(rangeStart)
          ? rangeStart
          : DateTime(c.startDate.year, c.startDate.month, c.startDate.day);
      final rangeLastDay = rangeEnd.subtract(const Duration(days: 1));
      final lastDay = c.endDate.isAfter(rangeLastDay)
          ? rangeLastDay
          : DateTime(c.endDate.year, c.endDate.month, c.endDate.day);
      while (!day.isAfter(lastDay)) {
        closedDays.add(DateTime(day.year, day.month, day.day));
        day = day.add(const Duration(days: 1));
      }
    }
    return closedDays;
  }

  /// Garantit les créneaux collectifs pour la semaine [weekStart] et les
  /// [aheadWeeks] semaines suivantes, pour que les adhérents puissent
  /// consulter/s'inscrire sur plusieurs semaines à l'avance sans attendre
  /// qu'un coach ait lui-même ouvert chacune d'elles.
  Future<void> ensureCollectiveSlotsAhead(DateTime weekStart, {int aheadWeeks = 6}) async {
    for (var i = 0; i <= aheadWeeks; i++) {
      await ensureCollectiveSlotsForWeek(weekStart.add(Duration(days: 7 * i)));
    }
  }

  /// Reconstitue le lundi (minuit) à partir d'un identifiant de document
  /// `weekTypes` (voir [_weekTypeDocId]) — l'inverse de cette méthode.
  DateTime _weekTypeIdToDate(String id) {
    final parts = id.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  /// Section 1.4 : type de la semaine dans le cycle d'entraînement de 6
  /// semaines (2 basiques, 2 intermédiaires, 2 dynamiques — voir
  /// [kWeekTypeCycle]). Retombe sur le premier type du cycle tant qu'aucune
  /// semaine n'a encore été initialisée (avant le tout premier appel de
  /// [ensureWeekTypesAhead]). Lu par les coachs (modifiable) et les
  /// adhérents (lecture seule).
  Stream<String> watchWeekType(DateTime weekStart) {
    return _weekTypes.doc(_weekTypeDocId(weekStart)).snapshots().map(
          (doc) => doc.data()?['type'] as String? ?? kWeekTypeCycle.first,
        );
  }

  /// Coach uniquement (voir `firestore.rules`) : définit le type de la
  /// semaine dont le lundi est [weekStart] — un changement manuel (ex. pour
  /// tenir compte d'une fermeture) répercute aussitôt le cycle sur TOUTES
  /// les semaines suivantes déjà connues (matérialisées au fil du temps par
  /// [ensureWeekTypesAhead]), pas seulement les 6 prochaines, pour que la
  /// suite du cycle reste cohérente avec ce nouveau point de départ. Les
  /// semaines précédentes ne sont jamais modifiées (historique figé).
  ///
  /// La recherche des semaines suivantes se fait via le champ [weekStart]
  /// (et non l'identifiant du document) : plus fiable pour une comparaison
  /// `>`/`<` côté Firestore, et cohérent avec le reste du dépôt (`slots`,
  /// `closures`...) qui filtre toujours sur un vrai champ `date`.
  ///
  /// Correctif du 7 août 2026 (bug signalé par Margaux : après "Dynamique
  /// 2/2", le planning affichait "Basique 2/2" au lieu de "Basique 1/2",
  /// soit un cycle qui avait sauté un pas). **Cause** : la version
  /// précédente recalculait le type de chaque semaine suivante en chaînant
  /// [_nextWeekType] pas à pas sur les documents renvoyés par la requête
  /// (`prevType = _nextWeekType(prevType)` une fois par document parcouru)
  /// — une hypothèse implicite que chaque document de la liste correspond à
  /// EXACTEMENT une semaine de plus que le précédent. Si un seul document
  /// s'écarte de cette hypothèse (semaine dupliquée, document orphelin d'un
  /// ancien format sans `weekStart` fiable, trou dans la séquence...), tout
  /// le reste de la chaîne se décale d'un pas, indéfiniment. **Correctif** :
  /// chaque semaine suivante reçoit désormais son type calculé directement
  /// depuis son ÉCART EN NOMBRE DE SEMAINES réel par rapport à [weekStart]
  /// (`_weekTypeAtOffset`), plutôt que par un chaînage pas-à-pas — un
  /// document en trop, dupliqué ou mal daté n'a alors aucune influence sur
  /// les autres, chacun étant recalculé indépendamment à partir de sa propre
  /// date.
  Future<void> setWeekType(DateTime weekStart, String type) async {
    final weekStartId = _weekTypeDocId(weekStart);
    final batch = _firestore.batch();
    batch.set(_weekTypes.doc(weekStartId), {
      'type': type,
      'weekStart': Timestamp.fromDate(weekStart),
    });

    final laterSnap = await _weekTypes
        .where('weekStart', isGreaterThan: Timestamp.fromDate(weekStart))
        .orderBy('weekStart')
        .get();
    for (final doc in laterSnap.docs) {
      // Recalculé depuis l'id si absent — semaine matérialisée avant
      // l'introduction de ce champ ; comble rétroactivement le champ
      // manquant plutôt que de laisser ce document devenir invisible aux
      // prochaines requêtes par plage.
      final docWeekStart =
          (doc.data()['weekStart'] as Timestamp?)?.toDate() ?? _weekTypeIdToDate(doc.id);
      final weeksOffset = docWeekStart.difference(weekStart).inDays ~/ 7;
      batch.set(doc.reference, {
        'type': _weekTypeAtOffset(type, weeksOffset),
        'weekStart': Timestamp.fromDate(docWeekStart),
      });
    }
    await batch.commit();
  }

  /// Garantit que le type de la semaine [weekStart] est défini, ainsi que
  /// celui des [aheadWeeks] semaines suivantes (par défaut 6, comme
  /// [ensureCollectiveSlotsAhead]) — à appeler à chaque ouverture du
  /// planning coach.
  ///
  /// Toute première utilisation (aucune semaine connue nulle part) :
  /// démarre le cycle à "Basique 1/2" sur la semaine affichée. Sinon,
  /// reprend le cycle là où il s'est arrêté — y compris après une longue
  /// absence côté coach, en retrouvant la semaine connue la plus récente
  /// avant/à [weekStart] et en calculant directement le bon décalage dans
  /// le cycle ([_weekTypeAtOffset]) plutôt qu'en reparcourant semaine par
  /// semaine tout l'écart. Une semaine déjà définie (y compris par un choix
  /// manuel du coach) n'est jamais réécrite ici (son `type` est conservé
  /// tel quel ; seul un éventuel champ `weekStart` manquant, sur une
  /// semaine matérialisée avant l'introduction de ce champ, est comblé).
  ///
  /// Les [aheadWeeks] + 1 semaines concernées (celle affichée + les
  /// suivantes) sont lues en PARALLÈLE (`Future.wait`, pas une lecture
  /// séquentielle par semaine) : réduit autant que possible la fenêtre
  /// pendant laquelle un changement manuel concurrent ([setWeekType], si le
  /// coach modifie le sélecteur juste après avoir ouvert l'écran) pourrait
  /// se faire écraser par cette initialisation. Lecture directe par
  /// identifiant de document (pas une requête par plage sur le champ
  /// [weekStart]) : fonctionne aussi pour une semaine déjà matérialisée par
  /// l'ancien format (avant l'introduction de ce champ), qu'une requête par
  /// plage ne verrait pas et écraserait donc à tort.
  Future<void> ensureWeekTypesAhead(DateTime weekStart, {int aheadWeeks = 6}) async {
    final weekIds = [
      for (var i = 0; i <= aheadWeeks; i++)
        _weekTypeDocId(weekStart.add(Duration(days: 7 * i))),
    ];
    final docs = await Future.wait(weekIds.map((id) => _weekTypes.doc(id).get()));

    final batch = _firestore.batch();
    var hasWrites = false;

    String currentType;
    final startDoc = docs[0];
    if (startDoc.exists) {
      final data = startDoc.data()!;
      currentType = data['type'] as String? ?? kWeekTypeCycle.first;
      if (data['weekStart'] == null) {
        batch.set(startDoc.reference, {'weekStart': Timestamp.fromDate(weekStart)},
            SetOptions(merge: true));
        hasWrites = true;
      }
    } else {
      final priorSnap = await _weekTypes
          .where('weekStart', isLessThan: Timestamp.fromDate(weekStart))
          .orderBy('weekStart', descending: true)
          .limit(1)
          .get();
      if (priorSnap.docs.isEmpty) {
        currentType = kWeekTypeCycle.first;
      } else {
        final priorData = priorSnap.docs.first.data();
        final priorDate = (priorData['weekStart'] as Timestamp).toDate();
        final priorType = priorData['type'] as String? ?? kWeekTypeCycle.first;
        final weeksOffset = weekStart.difference(priorDate).inDays ~/ 7;
        currentType = _weekTypeAtOffset(priorType, weeksOffset);
      }
      batch.set(_weekTypes.doc(weekIds[0]), {
        'type': currentType,
        'weekStart': Timestamp.fromDate(weekStart),
      });
      hasWrites = true;
    }

    var prevType = currentType;
    for (var i = 1; i <= aheadWeeks; i++) {
      final date = weekStart.add(Duration(days: 7 * i));
      final doc = docs[i];
      if (doc.exists) {
        final data = doc.data()!;
        prevType = data['type'] as String? ?? prevType;
        if (data['weekStart'] == null) {
          batch.set(doc.reference, {'weekStart': Timestamp.fromDate(date)},
              SetOptions(merge: true));
          hasWrites = true;
        }
        continue;
      }
      prevType = _nextWeekType(prevType);
      batch.set(_weekTypes.doc(weekIds[i]), {
        'type': prevType,
        'weekStart': Timestamp.fromDate(date),
      });
      hasWrites = true;
    }

    if (hasWrites) await batch.commit();
  }

  /// Coach : ajoute un cours individuel poussé pour un adhérent précis
  /// (section "ajouter un cours > individuel") — pas d'inscription libre,
  /// visible uniquement par l'adhérent concerné côté planning (section 4.2).
  /// [adherentLabel] (nom complet) est intégré au titre pour que le coach
  /// voie immédiatement qui est concerné, sans requête supplémentaire.
  Future<void> addIndividualSlot({
    required DateTime date,
    required String startTime,
    required String adherentUid,
    required String adherentLabel,
  }) async {
    final slot = SlotModel(
      id: '',
      courseId: 'individuel-${date.toIso8601String()}-$startTime-$adherentUid',
      courseTitle: 'Individuel — $adherentLabel',
      type: 'individual',
      date: date,
      startTime: startTime,
      endTime: addOneHour(startTime),
      capacity: 1,
      registeredCount: 0,
      waitlistCount: 0,
      adherentUid: adherentUid,
    );
    await _slots.add(slot.toFirestore());
  }

  /// Coach : modifie la date et l'heure de début d'un cours duo ou
  /// individuel déjà créé (appui long sur sa carte dans le planning, voir
  /// `slot_actions_sheet.dart`). L'heure de fin est recalculée
  /// automatiquement (`addOneHour`), comme à la création — ces créneaux
  /// durent toujours 1h, il n'y a pas de champ "heure de fin" à modifier.
  ///
  /// Écriture directe (pas de Cloud Function) : les règles Firestore
  /// autorisent déjà un coach à modifier un `slot` tant que
  /// `registeredCount`/`waitlistCount` ne changent pas (voir
  /// `firestore.rules`), ce qui est le cas ici.
  Future<void> updateSlotDateTime({
    required String slotId,
    required DateTime date,
    required String startTime,
  }) {
    return _slots.doc(slotId).update({
      'date': Timestamp.fromDate(date),
      'startTime': startTime,
      'endTime': addOneHour(startTime),
    });
  }

  /// Coach : supprime un cours duo ou individuel (appui long sur sa carte).
  ///
  /// MVP : ne supprime que le document `slot` lui-même — les éventuelles
  /// inscriptions (`registrations`) pointant vers ce créneau ne sont pas
  /// nettoyées automatiquement (hors MVP, priorité 2 ; elles deviennent
  /// simplement orphelines, sans impact visible puisque plus personne ne
  /// les requête une fois le créneau disparu).
  Future<void> deleteSlot(String slotId) {
    return _slots.doc(slotId).delete();
  }

  /// Coach : ajoute un workshop ponctuel (section "ajouter un évènement >
  /// workshop") — purement informatif dans le planning, sans inscription.
  Future<void> addWorkshop({
    required DateTime date,
    required String startTime,
    required String endTime,
    required String title,
    String? description,
  }) async {
    final slot = SlotModel(
      id: '',
      courseId: 'workshop-${date.toIso8601String()}-$startTime',
      courseTitle: title,
      type: 'workshop',
      date: date,
      startTime: startTime,
      endTime: endTime,
      capacity: 0,
      registeredCount: 0,
      waitlistCount: 0,
      description: description,
    );
    await _slots.add(slot.toFirestore());
  }

  /// Coach : modifie un workshop déjà créé (titre, description, date, heure
  /// de début et de fin) — appui long sur sa carte dans le planning (voir
  /// `slot_actions_sheet.dart`). Contrairement à [updateSlotDateTime] (duo/
  /// individuel, durée fixe d'1h), un workshop a ses propres heures de
  /// début et de fin, modifiables indépendamment l'une de l'autre.
  Future<void> updateWorkshop({
    required String slotId,
    required DateTime date,
    required String startTime,
    required String endTime,
    required String title,
    String? description,
  }) {
    return _slots.doc(slotId).update({
      'date': Timestamp.fromDate(date),
      'startTime': startTime,
      'endTime': endTime,
      'courseTitle': title,
      'description': description,
    });
  }

  /// Fermetures de la salle (section "ajouter un évènement > fermeture")
  /// chevauchant la semaine dont le lundi est [weekStart].
  ///
  /// Filtré côté client (comme [_closedDaysInRange]) plutôt que par une
  /// requête Firestore : une fermeture couvre désormais une période
  /// (`startDate`..`endDate`), et vérifier qu'elle chevauche la semaine
  /// affichée nécessite de comparer DEUX champs, ce que Firestore ne permet
  /// pas nativement en une seule requête sans index composite. Le nombre de
  /// fermetures reste de toute façon faible pour une seule salle.
  Stream<List<ClosureModel>> watchClosuresForWeek(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 7));
    return _closures.snapshots().map((snap) => snap.docs
        .map(ClosureModel.fromFirestore)
        .where((c) => c.startDate.isBefore(weekEnd) && !c.endDate.isBefore(weekStart))
        .toList());
  }

  /// Coach : ajoute une fermeture sur la période [startDate]–[endDate]
  /// (inclusifs ; égaux pour une fermeture d'un seul jour), et supprime
  /// dans la foulée tous les créneaux déjà programmés sur ces jours
  /// (collectifs, duo, individuels, workshops) — un jour fermé n'a plus
  /// lieu d'afficher de cours. Les créneaux supprimés sont sauvegardés dans
  /// `removedSlots` sur le document de fermeture, pour pouvoir être
  /// recréés si la période est ensuite réduite (voir [updateClosure]).
  ///
  /// Toutes les opérations passent par un même `WriteBatch` Firestore.
  ///
  /// MVP : comme pour [deleteSlot], les éventuelles inscriptions
  /// (`registrations`) pointant vers ces créneaux ne sont pas nettoyées
  /// automatiquement — elles deviennent orphelines, sans impact visible
  /// puisque plus personne ne les requête une fois le créneau disparu (et,
  /// si le créneau est recréé plus tard par [updateClosure], le nouveau
  /// document a un nouvel identifiant : les inscriptions existantes restent
  /// orphelines plutôt que de s'y raccrocher). Les demandes Rekovery (voir
  /// `rekovery_repository.dart`) ne sont volontairement pas touchées ici :
  /// ce ne sont pas des "cours" au sens du planning.
  Future<void> addClosure({
    required DateTime startDate,
    required DateTime endDate,
    required String message,
  }) async {
    final normStart = DateTime(startDate.year, startDate.month, startDate.day);
    final normEnd = DateTime(endDate.year, endDate.month, endDate.day);
    final rangeEndExclusive = normEnd.add(const Duration(days: 1));

    final slotsInRange = await _slots
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(normStart))
        .where('date', isLessThan: Timestamp.fromDate(rangeEndExclusive))
        .get();

    final batch = _firestore.batch();
    batch.set(
      _closures.doc(),
      ClosureModel(
        id: '',
        startDate: normStart,
        endDate: normEnd,
        message: message,
        removedSlots: slotsInRange.docs.map((d) => d.data()).toList(),
      ).toFirestore(),
    );
    for (final slotDoc in slotsInRange.docs) {
      batch.delete(slotDoc.reference);
    }
    await batch.commit();
  }

  /// Coach : modifie la période et/ou le message d'une fermeture déjà créée
  /// (appui long sur son bandeau dans le planning, voir
  /// `closure_actions_sheet.dart`) — et réconcilie les créneaux avec la
  /// nouvelle période [startDate]–[endDate] :
  /// - tout créneau actuellement programmé et désormais couvert par la
  ///   fermeture est supprimé, comme à la création (la période a pu
  ///   s'étendre à de nouveaux jours) ;
  /// - tout créneau précédemment supprimé par cette fermeture mais qui sort
  ///   de la nouvelle période (période réduite ou déplacée) est recréé ;
  /// - les créneaux précédemment supprimés qui restent dans la nouvelle
  ///   période ne sont pas touchés (déjà supprimés, rien à faire).
  Future<void> updateClosure({
    required String closureId,
    required DateTime startDate,
    required DateTime endDate,
    required String message,
  }) async {
    final normStart = DateTime(startDate.year, startDate.month, startDate.day);
    final normEnd = DateTime(endDate.year, endDate.month, endDate.day);
    final rangeEndExclusive = normEnd.add(const Duration(days: 1));

    final closureSnap = await _closures.doc(closureId).get();
    final existing = ClosureModel.fromFirestore(closureSnap);

    final slotsNowInRange = await _slots
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(normStart))
        .where('date', isLessThan: Timestamp.fromDate(rangeEndExclusive))
        .get();

    // Sépare les créneaux précédemment supprimés entre ceux qui restent
    // dans la nouvelle période (toujours supprimés, rien à faire) et ceux
    // qui en sortent (à recréer).
    final stillRemoved = <Map<String, dynamic>>[];
    final toRestore = <Map<String, dynamic>>[];
    for (final raw in existing.removedSlots) {
      final slotDate = (raw['date'] as Timestamp).toDate();
      final inNewRange = !slotDate.isBefore(normStart) && slotDate.isBefore(rangeEndExclusive);
      (inNewRange ? stillRemoved : toRestore).add(raw);
    }

    final batch = _firestore.batch();
    batch.update(_closures.doc(closureId), {
      'startDate': Timestamp.fromDate(normStart),
      'endDate': Timestamp.fromDate(normEnd),
      'message': message,
      'removedSlots': [...stillRemoved, ...slotsNowInRange.docs.map((d) => d.data())],
    });
    for (final slotDoc in slotsNowInRange.docs) {
      batch.delete(slotDoc.reference);
    }
    for (final raw in toRestore) {
      batch.set(_slots.doc(), raw);
    }
    await batch.commit();
  }

  /// Coach : supprime une fermeture ET recrée tous les créneaux
  /// (collectifs, duo, individuels, workshops) qui avaient été supprimés à
  /// cause d'elle (voir [addClosure]/[updateClosure]) — supprimer une
  /// fermeture signifie qu'elle ne s'applique plus, les cours annulés à
  /// cause d'elle doivent donc redevenir visibles. Les deux opérations
  /// passent par un même `WriteBatch` Firestore.
  Future<void> deleteClosure(String closureId) async {
    final closureSnap = await _closures.doc(closureId).get();
    final existing = ClosureModel.fromFirestore(closureSnap);

    final batch = _firestore.batch();
    for (final raw in existing.removedSlots) {
      batch.set(_slots.doc(), raw);
    }
    batch.delete(_closures.doc(closureId));
    await batch.commit();
  }

  /// Toutes les fermetures existantes, en une fois (pas un flux) — utilisé
  /// pour empêcher un adhérent de choisir un jour fermé lors d'une demande
  /// Rekovery (voir `rekovery_repository.dart`). Récupère tout plutôt que de
  /// filtrer côté Firestore, comme [_closedDaysInRange] /
  /// [watchClosuresForWeek] : une fermeture chevauche une plage sur deux
  /// champs, ce que Firestore ne permet pas nativement sans index composite,
  /// et le nombre de fermetures reste de toute façon faible pour une seule
  /// salle.
  Future<List<ClosureModel>> fetchAllClosures() async {
    final snap = await _closures.get();
    return snap.docs.map(ClosureModel.fromFirestore).toList();
  }
}