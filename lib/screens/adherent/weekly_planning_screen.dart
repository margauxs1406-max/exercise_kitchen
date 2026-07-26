import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/closure_model.dart';
import '../../models/registration_model.dart';
import '../../models/rekovery_session_model.dart';
import '../../models/slot_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/planning_repository.dart';
import '../../services/registration_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../utils/slot_grouping.dart';
import '../../utils/week_utils.dart';
import '../../widgets/add_rekovery_dialog.dart';
import '../../widgets/closure_banner.dart';
import '../../widgets/day_header.dart';
import '../../widgets/rekovery_actions_sheet.dart';
import '../../widgets/rekovery_line.dart';
import '../../widgets/slot_card.dart';
import '../../widgets/slot_roster_dialog.dart';
import '../../widgets/week_header.dart';
import '../../widgets/week_nav_bar.dart';
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
/// du document" en une seule requête. Un adhérent avec la formule
/// "Rekovery" voit en plus un bouton flottant qui ouvre
/// [showAddRekoveryDialog] pour indiquer sa date/heure d'arrivée.
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
                        return StreamBuilder<List<RekoverySessionModel>>(
                          // Un adhérent ne voit que ses propres sessions
                          // rekovery (voir `firestore.rules`).
                          stream: planningRepo.watchRekoveryForWeek(
                            _weekStart,
                            onlyAdherentUid: uid,
                          ),
                          builder: (context, rekoverySnapshot) {
                            final rekoverySessions =
                                rekoverySnapshot.data ?? const <RekoverySessionModel>[];

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
                            // l'historique complet des duos, individuels et
                            // sessions rekovery redevient visible, pour
                            // pouvoir le consulter après coup.
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
                            final visibleRekoverySessions = isPastWeek
                                ? rekoverySessions
                                : rekoverySessions
                                    .where((r) => !_dayOf(r.date).isBefore(today))
                                    .toList();

                            if (visibleSlots.isEmpty &&
                                visibleClosures.isEmpty &&
                                visibleRekoverySessions.isEmpty) {
                              return const Center(
                                child: Text('Aucun créneau cette semaine.'),
                              );
                            }

                            final items = groupSlotsByDay(
                              visibleSlots,
                              closures: visibleClosures,
                              rekoverySessions: visibleRekoverySessions,
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
                                if (item is RekoverySessionModel) {
                                  // `showName` reste false : l'adhérent ne
                                  // voit que ses propres sessions. `color`
                                  // en orange (au lieu du gris par défaut,
                                  // gardé côté coach) pour que sa session
                                  // ressorte davantage dans son planning.
                                  // `onTap` ouvre "Modifier"/"Supprimer"
                                  // (section 2.4bis) — chaque session vue ici
                                  // appartient forcément à l'adhérent courant
                                  // (voir `watchRekoveryForWeek(onlyAdherentUid:
                                  // uid)` plus haut).
                                  return RekoveryLine(
                                    session: item,
                                    color: AppColors.orange,
                                    onTap: () => showRekoveryActionsSheet(context, item),
                                  );
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

                                return SlotCard(
                                  slot: slot,
                                  countBelowTime: true,
                                  showCount: isRegisterable,
                                  // Même pop-up "inscrits / liste d'attente"
                                  // que côté coach (voir
                                  // `manage_planning_screen.dart`), réservée
                                  // ici aussi aux collectifs et duos — un
                                  // individuel n'a qu'un seul adhérent
                                  // concerné (lui-même) et un workshop n'a
                                  // pas d'inscription.
                                  onTap: isRegisterable
                                      ? () => showSlotRosterDialog(context, slot)
                                      : null,
                                  trailing: !showRegisterButton
                                      ? null
                                      : SizedBox(
                                          // Largeur variable selon le libellé
                                          // affiché : pendant le chargement
                                          // et une fois inscrit/en attente
                                          // ("Inscrit.e"/"En attente" + icône),
                                          // on garde 112 (jamais posé
                                          // problème) ; avant inscription,
                                          // "S'inscrire" (court) obtient une
                                          // largeur réduite et "File
                                          // d'attente" (plus long) une
                                          // largeur augmentée, plutôt qu'une
                                          // seule largeur fixe pour les deux.
                                          width: (!isPending && myReg == null)
                                              ? (slot.isFull ? context.wp(138) : context.wp(96))
                                              : context.wp(112),
                                          child: isPending
                                              ? Center(
                                                  child: SizedBox(
                                                    height: context.hp(20),
                                                    width: context.wp(20),
                                                    child: const CircularProgressIndicator(
                                                        strokeWidth: 2),
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
                                                ),
                                        ),
                                );
                              },
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
      // Section 2.4bis : uniquement pour les adhérents ayant la formule
      // "Rekovery" — ouvre la pop-up [showAddRekoveryDialog] (date pré-remplie
      // sur aujourd'hui, heure à choisir), pour que les coachs puissent
      // anticiper (ex. allumer le sauna avant l'arrivée).
      floatingActionButton: (user == null || !user.formulas.contains('rekovery'))
          ? null
          : Padding(
              padding: EdgeInsets.only(right: context.wp(20), bottom: context.hp(24)),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withValues(alpha: 0.24),
                      offset: const Offset(6, 3),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: FloatingActionButton(
                  backgroundColor: AppColors.black,
                  elevation: 0,
                  highlightElevation: 0,
                  shape: const CircleBorder(),
                  onPressed: () => showAddRekoveryDialog(
                    context,
                    adherentUid: user.uid,
                    adherentName: user.shortName,
                  ),
                  child: Icon(Icons.thermostat, color: AppColors.white, size: context.wp(28)),
                ),
              ),
            ),
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

      // Plus de contour ni de fond de bouton une fois inscrit / en attente :
      // juste le texte et l'icône (à droite du texte), dans la couleur
      // d'état correspondante. `onPressed` reste actif (permet toujours
      // d'annuler l'inscription).
      return InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(context.wp(20)),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: context.hp(6), horizontal: context.wp(4)),
          child: Row(
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
