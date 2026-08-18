import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/closure_model.dart';
import '../../models/registration_model.dart';
import '../../models/rekovery_request_model.dart';
import '../../models/slot_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/planning_repository.dart';
import '../../services/registration_repository.dart';
import '../../services/rekovery_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../utils/slot_grouping.dart';
import '../../utils/week_utils.dart';
import '../../widgets/closure_banner.dart';
import '../../widgets/day_header.dart';
import '../../widgets/slot_card.dart';
import '../../widgets/slot_roster_dialog.dart';
import '../../widgets/week_header.dart';
import '../../widgets/week_nav_bar.dart';
import '../../widgets/week_recap_row.dart';
import 'adherent_profile_screen.dart';

/// Section 2.2 / 2.2bis / 2.2ter : planning de la semaine avec inscription
/// directe ou mise en liste d'attente automatique si le créneau est
/// complet. Le type de semaine (section 1.4) est affiché en lecture seule
/// (défini par les coachs).
///
/// Section 4.2 : les créneaux affichés dépendent désormais des formules
/// souscrites par l'adhérent (cochées par un coach depuis sa fiche) —
/// [_visibleForUser] filtre côté client, puisque Firestore ne permet pas
/// facilement ce genre de filtre "un champ du user courant contre le type
/// du document" en une seule requête. Rekovery n'apparaît plus ici : c'est
/// désormais un onglet dédié (voir `adherent_rekovery_screen.dart`).
///
/// Possède son propre [Scaffold]/en-tête ([WeekHeader]), au même titre que
/// `ManagePlanningScreen` côté coach — voir `adherent_home_screen.dart`.
class WeeklyPlanningScreen extends StatefulWidget {
  const WeeklyPlanningScreen({super.key});

  @override
  State<WeeklyPlanningScreen> createState() => _WeeklyPlanningScreenState();
}

class _WeeklyPlanningScreenState extends State<WeeklyPlanningScreen> {
  late DateTime _weekStart = mondayOf(DateTime.now());
  final Set<String> _pendingSlotIds = {};

  // Section 1.4 : libellés affichés pour chaque valeur de `kWeekTypeCycle`
  // (voir `planning_repository.dart`) — lecture seule ici, le choix se fait
  // côté coach (`manage_planning_screen.dart`).
  static const _weekTypeLabels = {
    'basique_1': 'Basique 1/2',
    'basique_2': 'Basique 2/2',
    'intermediaire_1': 'Intermédiaire 1/2',
    'intermediaire_2': 'Intermédiaire 2/2',
    'dynamique_1': 'Dynamique 1/2',
    'dynamique_2': 'Dynamique 2/2',
  };

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  // Un créneau est considéré "passé" dès que son heure de début est dépassée
  // (pas seulement son jour) : un cours de 8h du jour même doit perdre son
  // bouton d'inscription dès 8h, pas seulement le lendemain.
  static DateTime _slotStart(SlotModel slot) {
    final parts = slot.startTime.split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return DateTime(slot.date.year, slot.date.month, slot.date.day, hour, minute);
  }

  static bool _isSlotPast(SlotModel slot) => _slotStart(slot).isBefore(DateTime.now());

  void _changeWeek(int deltaDays) {
    setState(() => _weekStart = _weekStart.add(Duration(days: deltaDays)));
  }

  /// Section 4.2 : un créneau n'est visible que si sa formule correspondante
  /// a été cochée par un coach pour cet adhérent ; un créneau individuel
  /// n'est en plus visible que s'il a été poussé pour CET adhérent
  /// précisément (le coach le pousse pour une personne à la fois). Les
  /// workshops restent visibles pour tout le monde (purement informatifs).
  bool _visibleForUser(SlotModel slot, UserModel user) {
    switch (slot.type) {
      case 'collective':
        return user.formulas.contains('collectif');
      case 'duo':
        return user.formulas.contains('duo');
      case 'individual':
        return user.formulas.contains('individuel') && slot.adherentUid == user.uid;
      case 'workshop':
        return true;
      default:
        return true;
    }
  }


  Future<void> _toggleRegistration({
    required RegistrationRepository regRepo,
    required SlotModel slot,
    required RegistrationModel? myRegistration,
  }) async {
    setState(() => _pendingSlotIds.add(slot.id));
    try {
      if (myRegistration != null) {
        await regRepo.cancelRegistration(myRegistration.id);
      } else {
        final outcome = await regRepo.registerForSlot(slot.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(outcome == RegisterOutcome.waitlisted
                ? "Créneau complet : tu es en liste d'attente."
                : 'Inscription confirmée !'),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Une erreur est survenue : $e")));
      }
    } finally {
      if (mounted) setState(() => _pendingSlotIds.remove(slot.id));
    }
  }

  /// Pop-up de confirmation avant désinscription (12 août 2026, demande de
  /// Margaux) : jusqu'ici, un simple tap sur le libellé "Inscrit.e"/"En
  /// attente" désinscrivait IMMÉDIATEMENT, sans confirmation — trop
  /// dangereux (désinscription accidentelle facile). Un tap simple sur ce
  /// libellé (comme sur le reste de la carte) ouvre désormais la pop-up
  /// "inscrits/liste d'attente" (voir [SlotCard.onTap] plus bas) ; seul un
  /// appui LONG sur la carte déclenche cette confirmation, même style que
  /// [_confirmAndDelete] (`slot_actions_sheet.dart`, côté coach) pour rester
  /// cohérent avec le reste de l'app.
  Future<void> _confirmUnregister({
    required RegistrationRepository regRepo,
    required SlotModel slot,
    required RegistrationModel myRegistration,
  }) async {
    final isWaitlisted = myRegistration.status == RegistrationStatus.waitlisted;
    // Avertissement renforcé (18 août 2026, demande de Margaux) : si cette
    // désinscription fait tomber le nombre d'inscrits CONFIRMÉS de 2 à 1
    // (le cours risque alors l'annulation — mêmes seuils que l'alerte
    // serveur, voir `checkSingleRegistrantSlots` dans
    // `functions/src/index.ts`), le titre/texte de la pop-up change pour le
    // signaler explicitement. Ne s'applique qu'à une place CONFIRMÉE
    // (`registeredCount` ne bouge pas quand quelqu'un quitte la liste
    // d'attente) et seulement quand il reste exactement 2 inscrits
    // confirmés avant cette désinscription. Mêmes boutons
    // "Annuler"/"Se désinscrire" que la pop-up habituelle — ce texte la
    // REMPLACE, il ne s'ajoute pas en plus.
    final risksCancellation = !isWaitlisted && slot.registeredCount == 2;

    final title = risksCancellation ? 'ATTENTION' : 'SE DÉSINSCRIRE ?';
    final message = risksCancellation
        ? "Le cours n'aura plus qu'un seul inscrit et risque d'être annulé, "
            "es-tu sûre de vouloir te désinscrire ?"
        : (isWaitlisted
            ? 'Tu quitteras la liste d\'attente de « ${slot.courseTitle} » '
                '(${slot.startTime}–${slot.endTime}).'
            : 'Ta place pour « ${slot.courseTitle} » (${slot.startTime}–${slot.endTime}) '
                'sera libérée.');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Se désinscrire'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _toggleRegistration(regRepo: regRepo, slot: slot, myRegistration: myRegistration);
  }

  @override
  Widget build(BuildContext context) {
    final planningRepo = context.read<PlanningRepository>();
    final regRepo = context.read<RegistrationRepository>();
    final user = context.watch<AuthService>().currentUser;
    final uid = user?.uid;

    return Scaffold(
      appBar: WeekHeader(
        // Section (nouvelle) : bouton "profil" à la place de la
        // déconnexion directe — la déconnexion se fait maintenant depuis
        // `AdherentProfileScreen` (bouton texte orange souligné).
        onProfileTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdherentProfileScreen()),
        ),
        weekTypeContent: StreamBuilder<String>(
          stream: planningRepo.watchWeekType(_weekStart),
          builder: (context, snapshot) {
            final current = snapshot.data ?? kWeekTypeCycle.first;
            return Text(
              (_weekTypeLabels[current] ?? 'Basique 1/2').toUpperCase(),
              style: AppTheme.headerTitleStyle,
            );
          },
        ),
      ),
      body: Column(
        children: [
          WeekNavBar(
            weekStart: _weekStart,
            onPreviousWeek: () => _changeWeek(-7),
            onNextWeek: () => _changeWeek(7),
            // Récap de la semaine (7 août 2026) — voir `_WeekRecapLoader`
            // plus bas, qui a ses propres flux indépendants de ceux de la
            // liste de créneaux ci-dessous (simple et découplé, quitte à
            // dupliquer l'abonnement Firestore — sans coût réel, ce sont
            // déjà des flux temps réel ouverts par ailleurs).
            recap: uid == null ? null : _WeekRecapLoader(weekStart: _weekStart, uid: uid),
          ),
          Expanded(
            child: GestureDetector(
              // Section 4.1 : permet aussi de changer de semaine en balayant
              // à gauche/droite, en plus des flèches du bandeau ci-dessus.
              // L'axe horizontal ne gêne pas le défilement vertical
              // (ListView) du planning, géré séparément par Flutter.
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -200) {
                  _changeWeek(7);
                } else if (velocity > 200) {
                  _changeWeek(-7);
                }
              },
              child: user == null
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<SlotModel>>(
              stream: planningRepo.watchWeekSlots(_weekStart),
              builder: (context, slotsSnapshot) {
                if (!slotsSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                // Section 4.2 : ne garde que les créneaux correspondant aux
                // formules cochées par un coach pour cet adhérent.
                final slots = slotsSnapshot.data!
                    .where((s) => _visibleForUser(s, user))
                    .toList();
                return StreamBuilder<List<RegistrationModel>>(
                  stream: uid == null
                      ? Stream<List<RegistrationModel>>.empty()
                      : regRepo.watchMyRegistrations(uid),
                  builder: (context, regSnapshot) {
                    final myRegistrations = {
                      for (final r in regSnapshot.data ?? const <RegistrationModel>[])
                        r.slotId: r,
                    };

                    return StreamBuilder<List<ClosureModel>>(
                      // Les fermetures restent visibles pour tous, quelles
                      // que soient les formules souscrites (informatif).
                      stream: planningRepo.watchClosuresForWeek(_weekStart),
                      builder: (context, closuresSnapshot) {
                        final closures = closuresSnapshot.data ?? const <ClosureModel>[];

                            // Un jour entièrement passé disparaît du planning,
                            // MAIS uniquement pour la semaine en cours (celle
                            // qui contient aujourd'hui) ou une semaine future :
                            // plus besoin de scroller les jours déjà passés
                            // pour retrouver aujourd'hui/demain (un vendredi,
                            // seuls vendredi/samedi/dimanche restent, par
                            // exemple). Le jour courant reste affiché même
                            // partiellement passé — seuls ses créneaux déjà
                            // passés perdent leur bouton d'inscription (voir
                            // `showRegisterButton` plus bas).
                            //
                            // Dès qu'on navigue vers une semaine ENTIÈREMENT
                            // passée (flèche précédente), plus aucun filtre :
                            // l'historique complet des duos et individuels
                            // redevient visible, pour pouvoir le consulter
                            // après coup.
                            final today = _dayOf(DateTime.now());
                            final isPastWeek = _dayOf(_weekStart)
                                .add(const Duration(days: 6))
                                .isBefore(today);
                            // Section (nouvelle) : la semaine en cours est
                            // toujours ouverte aux inscriptions ; la semaine
                            // suivante ne s'ouvre qu'à partir du vendredi de
                            // la semaine en cours (3 jours d'avance), pas dès
                            // le lundi — sans quoi les deux semaines
                            // seraient ouvertes en permanence, ce qui n'est
                            // plus vraiment "glissant". Recalculé à chaque
                            // ouverture de l'écran, sans action manuelle.
                            final currentWeekStart = _dayOf(mondayOf(DateTime.now()));
                            final fridayOfCurrentWeek =
                                currentWeekStart.add(const Duration(days: 4));
                            final nextWeekUnlocked = !today.isBefore(fridayOfCurrentWeek);
                            final currentWeekEnd = currentWeekStart
                                .add(Duration(days: nextWeekUnlocked ? 13 : 6));
                            final visibleSlots = isPastWeek
                                ? slots
                                : slots
                                    .where((s) => !_dayOf(s.date).isBefore(today))
                                    .toList();
                            final visibleClosures = isPastWeek
                                ? closures
                                : closures
                                    .where((c) => !_dayOf(c.endDate).isBefore(today))
                                    .toList();

                            if (visibleSlots.isEmpty && visibleClosures.isEmpty) {
                              return const Center(
                                child: Text('Aucun créneau cette semaine.'),
                              );
                            }

                            final items = groupSlotsByDay(
                              visibleSlots,
                              closures: visibleClosures,
                            );
                            return ListView.builder(
                              padding: EdgeInsets.symmetric(horizontal: context.wp(12)),
                              itemCount: items.length,
                              itemBuilder: (context, i) {
                                final item = items[i];
                                if (item is DateTime) {
                                  return DayHeader(date: item, isFirst: i == 0);
                                }
                                if (item is ClosureModel) {
                                  return ClosureBanner(closure: item);
                                }
                                final slot = item as SlotModel;
                                // Individuel / workshop : pas d'inscription
                                // libre, le coach gère directement.
                                final isRegisterable =
                                    slot.type == 'collective' || slot.type == 'duo';
                                // Le compteur d'inscrits et l'ouverture de la
                                // liste des inscrits (onTap) restent utiles
                                // même une fois le créneau passé, ou pour une
                                // semaine encore plus lointaine pas encore
                                // ouverte ; seul le bouton d'inscription
                                // lui-même disparaît : ni pour un créneau
                                // déjà passé (confusion), ni pour un créneau
                                // au-delà des deux semaines glissantes
                                // ouvertes (pas encore déverrouillé).
                                final showRegisterButton = isRegisterable &&
                                    !_isSlotPast(slot) &&
                                    !_dayOf(slot.date).isAfter(currentWeekEnd);
                                final myReg = myRegistrations[slot.id];
                                final isPending = _pendingSlotIds.contains(slot.id);
                                // Couleur par statut d'inscription (10 août
                                // 2026, demande de Margaux — voir
                                // `SlotCard.colorMode`) : un individuel est
                                // toujours "confirmé" pour l'adhérent à qui
                                // il est poussé (pas d'inscription à
                                // proprement parler, voir `_visibleForUser`
                                // plus haut) ; un collectif/duo suit le
                                // statut réel de l'inscription, `null` si
                                // l'adhérent n'y est pas inscrit (couleurs
                                // neutres).
                                final registrationStatus = slot.type == 'individual'
                                    ? RegistrationStatus.confirmed
                                    : myReg?.status;

                                return SlotCard(
                                  slot: slot,
                                  countBelowTime: true,
                                  showCount: isRegisterable,
                                  colorMode: SlotCardColorMode.byRegistrationStatus,
                                  registrationStatus: registrationStatus,
                                  // Même pop-up "inscrits / liste d'attente"
                                  // que côté coach (voir
                                  // `manage_planning_screen.dart`), réservée
                                  // ici aussi aux collectifs et duos — un
                                  // individuel n'a qu'un seul adhérent
                                  // concerné (lui-même) et un workshop n'a
                                  // pas d'inscription. Un tap simple ouvre
                                  // TOUJOURS cette pop-up (12 août 2026, y
                                  // compris en tapant sur le libellé
                                  // "Inscrit.e"/"En attente" lui-même — voir
                                  // `_RegistrationButton` plus bas, qui ne
                                  // capte plus le tap dans ce cas).
                                  onTap: isRegisterable
                                      ? () => showSlotRosterDialog(context, slot)
                                      : null,
                                  // Appui long : demande de confirmation
                                  // avant désinscription (12 août 2026,
                                  // demande de Margaux — remplace l'ancienne
                                  // désinscription immédiate au tap simple,
                                  // trop facile à déclencher par accident).
                                  // Même condition que l'ancien bouton
                                  // "Inscrit.e"/"En attente" cliquable qu'il
                                  // remplace : il faut à la fois une
                                  // inscription à annuler (`myReg != null`)
                                  // ET que le créneau soit encore dans la
                                  // fenêtre où une action d'inscription a
                                  // seulement du sens (`showRegisterButton`
                                  // — pas un créneau déjà passé, ni au-delà
                                  // des 2 semaines glissantes ouvertes).
                                  onLongPress: (myReg == null || !showRegisterButton)
                                      ? null
                                      : () => _confirmUnregister(
                                            regRepo: regRepo,
                                            slot: slot,
                                            myRegistration: myReg,
                                          ),
                                  trailing: !showRegisterButton
                                      ? null
                                      // Plus de largeur FIXE en dur ici (17
                                      // août 2026, bug corrigé, demande de
                                      // Margaux) : sur les petits téléphones,
                                      // `context.wp(...)` rétrécit
                                      // proportionnellement à la largeur
                                      // d'écran SANS plancher, alors que
                                      // `context.sp(...)` (taille de police,
                                      // voir `responsive.dart`) a un plancher
                                      // à 85 % — le texte du bouton
                                      // rétrécissait donc moins vite que la
                                      // largeur qui le contenait, et finissait
                                      // tronqué ("S'inscr..."). En laissant
                                      // `ListTile.trailing` dimensionner
                                      // lui-même sur la largeur intrinsèque du
                                      // contenu (spinner de chargement à
                                      // largeur fixe, réduite mais toujours
                                      // suffisante ; bouton/libellé
                                      // dimensionné à son propre texte), le
                                      // libellé ne peut plus jamais être
                                      // coupé, quelle que soit la taille de
                                      // l'écran.
                                      : (isPending
                                          ? SizedBox(
                                              width: context.wp(28),
                                              child: Center(
                                                child: SizedBox(
                                                  height: context.hp(20),
                                                  width: context.wp(20),
                                                  child: const CircularProgressIndicator(
                                                      strokeWidth: 2),
                                                ),
                                              ),
                                            )
                                          : _RegistrationButton(
                                              registration: myReg,
                                              full: slot.isFull,
                                              onPressed: () => _toggleRegistration(
                                                regRepo: regRepo,
                                                slot: slot,
                                                myRegistration: myReg,
                                              ),
                                            )),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Calcule et affiche le récap de la semaine (section 2.2ter — refonte du 9
/// août 2026, voir la doc de classe de `WeekRecapRow` : un carré par jour,
/// du lundi au vendredi, pas une pastille par formule comme dans la
/// première version). Affiché comme `recap` de `WeekNavBar`, sous la ligne
/// "Semaine du XX/XX" — un aller-retour le 10 août 2026 a brièvement testé
/// une mise en page sans cette ligne, revenue à l'identique le même jour à
/// la demande de Margaux.
///
/// Pour chaque jour (lundi → vendredi), la ou les formules "présentes" ce
/// jour précis pour l'adhérent sont :
/// - collectif/duo : une inscription (confirmée OU en liste d'attente — les
///   deux signifient "concerné.e par ce créneau ce jour-là") sur un créneau
///   de ce type CE jour précis.
/// - individuel : un créneau individuel poussé par le coach pour cet
///   adhérent précisément CE jour-là (`SlotModel.adherentUid`, pas
///   d'inscription à part — donc toujours "confirmé", jamais de liste
///   d'attente possible sur ce type).
/// - Rekovery : une demande dont la date effective (celle proposée par le
///   coach si le statut est [RekoveryRequestStatus.proposed], sinon la date
///   demandée) tombe CE jour-là, et dont le statut n'est ni refusé ni
///   annulé.
///
/// **Couleur du carré (refonte du 10 août 2026, demande de Margaux)** : le
/// statut (`DayRecapStatus`, `week_recap_row.dart` — `confirmed`/vert
/// flashy ou `waitlisted`/moutarde) est désormais calculé PAR FORMULE, pas
/// globalement pour le jour entier — ce qui permet au carré d'afficher 2
/// couleurs différentes le même jour (ex. un cours confirmé ET un Rekovery
/// en attente, voir la doc de classe de `WeekRecapRow` pour le rendu en 2
/// triangles). Pour une formule donnée : `confirmed` si son inscription
/// collective/duo est confirmée, si c'est un créneau individuel (toujours
/// confirmé), ou si sa demande Rekovery est `accepted` ; `waitlisted`
/// sinon (liste d'attente collective/duo, ou demande Rekovery
/// `pending`/`proposed`). Si plusieurs occurrences de la MÊME formule le
/// même jour ont des statuts différents (ex. 2 créneaux collectifs), la
/// confirmation prime pour cette formule. Un jour sans aucune occurrence
/// reste gris (`dayFormulas[i].isEmpty`, pas un statut).
///
/// **Nombre d'occurrences (18 août 2026, demande de Margaux)** : un carré
/// affiche toujours UNE seule icône par formule (pas une par cours — sinon
/// `_DaySquare` ne saurait plus les distinguer visuellement d'une formule
/// différente), mais un petit badge numéroté apparaît désormais sur
/// l'icône dès que 2 occurrences ou plus de la même formule tombent le même
/// jour (ex. 2 séances "Collectif"), pour que ce cas reste visuellement
/// différent d'une seule inscription (voir `dayFormulaCounts`,
/// `_MiniIconWithBadge` dans `week_recap_row.dart`).
///
/// Flux Firestore propres, indépendants de ceux utilisés par la liste de
/// créneaux plus bas dans l'écran — plus simple à isoler ainsi (le récap
/// vit dans le bandeau, hors de l'arbre des `StreamBuilder` imbriqués de la
/// liste) que d'essayer de faire remonter des données depuis un widget
/// enfant profondément imbriqué.
class _WeekRecapLoader extends StatelessWidget {
  final DateTime weekStart;
  final String uid;
  const _WeekRecapLoader({required this.weekStart, required this.uid});

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Date "effective" d'une demande Rekovery : celle proposée par le coach
  /// si la demande est encore en attente de réponse sur cette proposition,
  /// sinon la date initialement demandée.
  static DateTime _effectiveDate(RekoveryRequestModel r) =>
      (r.status == RekoveryRequestStatus.proposed && r.proposedDate != null)
          ? r.proposedDate!
          : r.date;

  @override
  Widget build(BuildContext context) {
    final planningRepo = context.read<PlanningRepository>();
    final regRepo = context.read<RegistrationRepository>();
    final rekoveryRepo = context.read<RekoveryRepository>();
    // Lundi → vendredi uniquement (la salle est fermée le week-end,
    // confirmé par Margaux le 9 août 2026) — donc toujours 5 jours, quel
    // que soit `weekStart` (qui tombe déjà un lundi, voir `mondayOf`).
    final weekDays = List.generate(5, (i) => _dayOf(weekStart).add(Duration(days: i)));

    return StreamBuilder<List<SlotModel>>(
      stream: planningRepo.watchWeekSlots(weekStart),
      builder: (context, slotsSnapshot) {
        final weekSlots = slotsSnapshot.data ?? const <SlotModel>[];
        return StreamBuilder<List<RegistrationModel>>(
          stream: regRepo.watchMyRegistrations(uid),
          builder: (context, regSnapshot) {
            // Statut par créneau (confirmée/liste d'attente), et non plus
            // seulement l'identifiant du créneau — nécessaire depuis le 10
            // août 2026 pour distinguer les deux états visuellement.
            final myRegistrationsBySlotId = {
              for (final r in regSnapshot.data ?? const <RegistrationModel>[]) r.slotId: r,
            };
            return StreamBuilder<List<RekoveryRequestModel>>(
              stream: rekoveryRepo.watchMyRequests(uid),
              builder: (context, rekoverySnapshot) {
                final requests = rekoverySnapshot.data ?? const <RekoveryRequestModel>[];
                final liveRequests = requests.where((r) =>
                    r.status != RekoveryRequestStatus.refused &&
                    r.status != RekoveryRequestStatus.cancelled);

                final dayFormulas = <Set<String>>[];
                final dayFormulaStatuses = <Map<String, DayRecapStatus>>[];
                // Nombre d'occurrences PAR FORMULE et par jour (18 août
                // 2026, demande de Margaux) — un carré reste 1 icône par
                // formule (pas 1 par cours, voir doc de classe), mais
                // affiche désormais un petit badge avec ce nombre dès qu'il
                // y en a 2 ou plus (ex. 2 séances "Collectif" le même jour),
                // pour que 2 inscriptions à la même formule restent
                // visuellement distinguables d'une seule. Voir
                // `_DaySquare`/`_MiniIconWithBadge` dans `week_recap_row.dart`.
                final dayFormulaCounts = <Map<String, int>>[];
                // "À risque" par formule et par jour (18 août 2026, demande
                // de Margaux) — vrai dès que l'adhérent est l'unique
                // inscrit(e) confirmé(e) d'AU MOINS UN créneau collectif/duo
                // de cette formule ce jour-là (même logique que
                // `SlotCard._isAtRiskOfCancellation`, voir `slot_card.dart`),
                // pour que le carré du récap passe rouge en plus de la carte
                // du créneau elle-même. Voir `_DaySquare` dans
                // `week_recap_row.dart`.
                final dayFormulaAtRisk = <Map<String, bool>>[];
                for (final day in weekDays) {
                  final formulas = <String>{};
                  final statuses = <String, DayRecapStatus>{};
                  final counts = <String, int>{};
                  final risks = <String, bool>{};
                  // Statut PAR FORMULE (10 août 2026, remplace l'agrégat
                  // par jour) — la confirmation prime si plusieurs
                  // occurrences de la même formule le même jour ont des
                  // statuts différents (ex. 2 créneaux collectifs, un
                  // confirmé et un en liste d'attente). [occurrences] (18
                  // août 2026) : nombre d'occurrences à ajouter au compteur
                  // de cette formule pour ce jour — 1 par défaut (un appel =
                  // une occurrence), sauf pour Rekovery où toutes les
                  // demandes du jour sont comptées en un seul appel groupé
                  // (voir plus bas). [atRisk] (18 août 2026) : une fois vrai
                  // pour une formule ce jour-là, reste vrai même si un appel
                  // ultérieur pour la même formule passe `false` (une seule
                  // occurrence à risque suffit à alerter sur toute la
                  // formule ce jour-là).
                  void markStatus(String formula, bool confirmed,
                      {int occurrences = 1, bool atRisk = false}) {
                    formulas.add(formula);
                    counts[formula] = (counts[formula] ?? 0) + occurrences;
                    risks[formula] = (risks[formula] ?? false) || atRisk;
                    final current = statuses[formula];
                    statuses[formula] = current == DayRecapStatus.confirmed
                        ? current!
                        : (confirmed ? DayRecapStatus.confirmed : DayRecapStatus.waitlisted);
                  }

                  for (final s in weekSlots) {
                    if (!_dayOf(s.date).isAtSameMomentAs(day)) continue;
                    if (s.type == 'collective' || s.type == 'duo') {
                      final reg = myRegistrationsBySlotId[s.id];
                      if (reg == null) continue;
                      final confirmed = reg.status == RegistrationStatus.confirmed;
                      markStatus(
                        s.type == 'collective' ? 'collectif' : 'duo',
                        confirmed,
                        atRisk: confirmed && s.registeredCount < 2,
                      );
                    } else if (s.type == 'individual' && s.adherentUid == uid) {
                      // Jamais de liste d'attente pour un individuel (créneau
                      // poussé directement par le coach) — toujours confirmé.
                      markStatus('individuel', true);
                    }
                  }
                  final rekoveryToday = liveRequests
                      .where((r) => _dayOf(_effectiveDate(r)).isAtSameMomentAs(day))
                      .toList();
                  if (rekoveryToday.isNotEmpty) {
                    // `pending`/`proposed` : en attente d'une réponse,
                    // affiché "En attente" ailleurs dans l'app (voir
                    // `rekovery_request_card.dart`). `occurrences` = nombre
                    // réel de demandes ce jour-là (rare, mais possible en
                    // liste d'attente/appui long sur plusieurs créneaux).
                    markStatus(
                      'rekovery',
                      rekoveryToday.any((r) => r.status == RekoveryRequestStatus.accepted),
                      occurrences: rekoveryToday.length,
                    );
                  }
                  dayFormulas.add(formulas);
                  dayFormulaStatuses.add(statuses);
                  dayFormulaCounts.add(counts);
                  dayFormulaAtRisk.add(risks);
                }

                return WeekRecapRow(
                  dayFormulas: dayFormulas,
                  dayFormulaStatuses: dayFormulaStatuses,
                  dayFormulaCounts: dayFormulaCounts,
                  dayFormulaAtRisk: dayFormulaAtRisk,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _RegistrationButton extends StatelessWidget {
  final RegistrationModel? registration;
  final bool full;
  final VoidCallback onPressed;

  const _RegistrationButton({
    required this.registration,
    required this.full,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (registration != null) {
      final isWaitlisted = registration!.status == RegistrationStatus.waitlisted;
      final color = isWaitlisted ? AppColors.mustardYellow : AppColors.flashyGreen;
      final icon = isWaitlisted ? Icons.hourglass_empty : Icons.check_circle;
      final label = isWaitlisted ? 'En attente' : 'Inscrit.e';

      // Plus de tap dédié ici depuis le 12 août 2026 (demande de Margaux —
      // avant, taper ce libellé désinscrivait IMMÉDIATEMENT, sans
      // confirmation : trop dangereux). `onPressed` n'est donc plus branché
      // sur ce libellé : un simple `Padding` (pas d'`InkWell`) laisse le tap
      // remonter jusqu'à la carte elle-même, qui ouvre la pop-up
      // "inscrits/liste d'attente" comme partout ailleurs sur la carte (voir
      // `SlotCard.onTap`) — la désinscription se fait maintenant par appui
      // long SUR LA CARTE, avec confirmation (voir
      // `_WeeklyPlanningScreenState._confirmUnregister`).
      return Padding(
        padding: EdgeInsets.symmetric(vertical: context.hp(6), horizontal: context.wp(4)),
        // `mainAxisSize: MainAxisSize.min` AJOUTÉ le 18 août 2026 (bug
        // critique corrigé, remonté par Margaux juste après le lot de
        // correctifs précédent) : un `Row` sans cette précision réclame par
        // défaut TOUTE la largeur disponible (`MainAxisSize.max`). Tant que
        // ce `Row` restait enfermé dans le `SizedBox` à largeur fixe retiré
        // la veille (voir `trailing:` plus haut), ce comportement par défaut
        // ne se voyait pas — une fois cette largeur fixe supprimée pour
        // corriger la troncature du bouton "S'inscrire" (créneau non
        // encore inscrit), ce `Row`-ci (créneau déjà inscrit/en attente) en
        // a hérité : `ListTile` lui réservait alors TOUTE la largeur
        // disponible dans `trailing`, ne laissant presque plus de place au
        // titre du créneau (nom du cours/heure/nombre d'inscrits, réduit à
        // 1 caractère de large).
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: context.sp(12)),
            ),
            SizedBox(width: context.wp(4)),
            Icon(icon, color: color, size: context.wp(20)),
          ],
        ),
      );
    }
    // Bouton "S'inscrire" / "File d'attente" : plus long (padding
    // horizontal généreux), légèrement plus haut que la première version
    // (vertical: 11) et plus arrondi (forme pilule).
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: context.wp(18), vertical: context.hp(11)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.wp(22))),
        textStyle: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.w600),
      ),
      // `maxLines`/`overflow` : garantit que le texte reste sur une seule
      // ligne (donc que le bouton garde toujours la même hauteur) même si
      // jamais la largeur ci-dessus s'avérait un peu trop juste.
      child: Text(
        full ? "File d'attente" : "S'inscrire",
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
