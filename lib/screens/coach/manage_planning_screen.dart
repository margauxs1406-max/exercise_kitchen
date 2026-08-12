import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/closure_model.dart';
import '../../models/slot_model.dart';
import '../../services/auth_service.dart';
import '../../services/planning_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../utils/slot_grouping.dart';
import '../../utils/week_utils.dart';
import '../../widgets/closure_actions_sheet.dart';
import '../../widgets/closure_banner.dart';
import '../../widgets/day_header.dart';
import '../../widgets/slot_actions_sheet.dart';
import '../../widgets/slot_card.dart';
import '../../widgets/slot_roster_dialog.dart';
import '../../widgets/week_header.dart';
import '../../widgets/week_nav_bar.dart';
import 'add_course_screen.dart';

/// Section 1.3 / 1.3bis / 1.4 : vue du planning de la semaine côté coach,
/// avec sélection du type de semaine (cycle de 6 semaines).
///
/// Les cours collectifs sont fixes (voir `default_collective_schedule.dart`)
/// et n'ont plus besoin d'être créés à la main : `ensureCollectiveSlotsAhead`
/// les génère automatiquement dès l'ouverture de cet écran, pour la semaine
/// affichée et plusieurs semaines à l'avance.
///
/// Le bouton "+" ouvre désormais [AddCourseScreen], qui couvre à la fois les
/// cours ponctuels (individuel / duo) et les évènements (workshop /
/// fermeture) — voir la section "ajouter au planning" des spécifications.
/// Le planning affiché mélange créneaux et fermetures (bandeau) via
/// [groupSlotsByDay]. Rekovery a son propre onglet dédié côté coach (voir
/// `coach_rekovery_screen.dart`), il n'apparaît plus ici.
///
/// Cet écran possède son propre [Scaffold]/en-tête ([WeekHeader]) plutôt que
/// de dépendre de l'AppBar partagée de `CoachHomeScreen` — voir
/// `coach_home_screen.dart`.
class ManagePlanningScreen extends StatefulWidget {
  const ManagePlanningScreen({super.key});

  @override
  State<ManagePlanningScreen> createState() => _ManagePlanningScreenState();
}

class _ManagePlanningScreenState extends State<ManagePlanningScreen> {
  late DateTime _weekStart = mondayOf(DateTime.now());

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  // Section 1.4 : libellés affichés pour chaque valeur de `kWeekTypeCycle`
  // (déclarés dans le même ordre, pour que le menu déroulant liste les 6
  // types dans l'ordre où ils se suivent dans le cycle).
  static const _weekTypeLabels = {
    'basique_1': 'Basique 1/2',
    'basique_2': 'Basique 2/2',
    'intermediaire_1': 'Intermédiaire 1/2',
    'intermediaire_2': 'Intermédiaire 2/2',
    'dynamique_1': 'Dynamique 1/2',
    'dynamique_2': 'Dynamique 2/2',
  };

  @override
  void initState() {
    super.initState();
    // Génère les créneaux collectifs de la semaine courante et des
    // semaines suivantes, pour que les adhérents puissent consulter et
    // s'inscrire à l'avance sans attendre qu'un coach ait ouvert chacune
    // de ces semaines individuellement.
    //
    // Enveloppé dans un try/catch : un aléa transitoire (droits Firestore
    // pas encore à jour pour ce compte, jeton d'authentification pas
    // encore propagé juste après une connexion...) ne doit pas faire
    // planter tout l'écran avec une erreur non gérée — le planning
    // s'affiche quand même, quitte à être vide tant que les créneaux ne
    // sont pas générés.
    _ensureSlotsAhead();
    _ensureWeekTypesAhead();
  }

  Future<void> _ensureSlotsAhead() async {
    try {
      await context.read<PlanningRepository>().ensureCollectiveSlotsAhead(_weekStart);
    } catch (e) {
      debugPrint('ensureCollectiveSlotsAhead a échoué : $e');
    }
  }

  // Section 1.4 : initialise (toute première connexion d'un coach) ou
  // poursuit le cycle de 6 semaines d'entraînement — voir
  // `PlanningRepository.ensureWeekTypesAhead`.
  Future<void> _ensureWeekTypesAhead() async {
    try {
      await context.read<PlanningRepository>().ensureWeekTypesAhead(_weekStart);
    } catch (e) {
      debugPrint('ensureWeekTypesAhead a échoué : $e');
    }
  }

  void _changeWeek(int deltaDays) {
    setState(() => _weekStart = _weekStart.add(Duration(days: deltaDays)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<PlanningRepository>();
    return Scaffold(
      appBar: WeekHeader(
        onLogout: () => context.read<AuthService>().signOut(),
        weekTypeContent: StreamBuilder<String>(
          stream: repo.watchWeekType(_weekStart),
          builder: (context, snapshot) {
            final current = snapshot.data ?? kWeekTypeCycle.first;
            return DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: current,
                isDense: true,
                dropdownColor: AppColors.black,
                iconEnabledColor: AppColors.white,
                // Taille de police : +2pt le 9 août 2026, ramenée à +1pt le
                // 10 août 2026 (demande de Margaux) par rapport au reste de
                // l'en-tête ([AppTheme.headerTitleStyle], qui hérite de
                // `context.sp(20)`).
                style: AppTheme.headerTitleStyle.copyWith(fontSize: context.sp(21)),
                // `selectedItemBuilder` + `alignment` (10 août 2026 : 2e
                // correctif, le 1er du même jour — envelopper le texte dans
                // un `Center` à l'intérieur de `selectedItemBuilder` — n'a
                // pas suffi). `DropdownButton` dimensionne le bouton FERMÉ
                // sur la largeur du plus long des libellés du cycle
                // (`INTERMÉDIAIRE 1/2`), pour ne jamais changer de largeur
                // selon la semaine affichée (`IndexedStack` interne, qui
                // dimensionne sur le plus grand de TOUS les libellés
                // possibles). Le libellé COURANT, lui, est ensuite
                // positionné DANS cette largeur réservée selon
                // `DropdownButton.alignment` — dont la valeur par défaut,
                // `AlignmentDirectional.centerStart` (= à GAUCHE), est la
                // vraie cause du problème : un `Center` posé À L'INTÉRIEUR
                // de `selectedItemBuilder` n'a aucun effet, car ce `Center`
                // se contente d'envelopper le texte à sa taille naturelle
                // (sans l'étirer) — c'est la position de ce bloc DANS la
                // largeur réservée, gérée par `alignment`, qui compte.
                // `alignment: Alignment.center` ci-dessous corrige ça pour
                // de vrai.
                alignment: Alignment.center,
                selectedItemBuilder: (context) => _weekTypeLabels.entries
                    .map(
                      (e) => Text(
                        e.value.toUpperCase(),
                        style: AppTheme.headerTitleStyle.copyWith(fontSize: context.sp(21)),
                      ),
                    )
                    .toList(),
                // Section 1.4 : cycle de 6 semaines (2 basiques, 2
                // intermédiaires, 2 dynamiques) — voir `kWeekTypeCycle`.
                // Choisir manuellement une valeur ici répercute le cycle
                // sur toutes les semaines suivantes (voir
                // `PlanningRepository.setWeekType`). La flèche par défaut
                // du framework (teintée en blanc via `iconEnabledColor`
                // ci-dessus) reste visible — demande du 10 août 2026,
                // annule la suppression du 9 août.
                items: _weekTypeLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.toUpperCase())))
                    .toList(),
                onChanged: (value) {
                  if (value != null) repo.setWeekType(_weekStart, value);
                },
              ),
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
              // Même logique que côté adhérent : balayer à gauche/droite
              // change de semaine, en plus des flèches du bandeau. L'axe
              // horizontal ne gêne pas le défilement vertical (ListView).
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -200) {
                  _changeWeek(7);
                } else if (velocity > 200) {
                  _changeWeek(-7);
                }
              },
              child: StreamBuilder<List<SlotModel>>(
              stream: repo.watchWeekSlots(_weekStart),
              builder: (context, slotsSnapshot) {
                if (!slotsSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final slots = slotsSnapshot.data!;
                return StreamBuilder<List<ClosureModel>>(
                  stream: repo.watchClosuresForWeek(_weekStart),
                  builder: (context, closuresSnapshot) {
                    final closures = closuresSnapshot.data ?? const <ClosureModel>[];
                    // Même logique que côté adhérent
                    // (`weekly_planning_screen.dart`) : un jour entièrement
                    // passé disparaît, mais uniquement pour la semaine en
                    // cours ou une semaine future — dès qu'on navigue vers
                    // une semaine entièrement passée, plus aucun filtre,
                    // pour garder l'historique complet consultable.
                    final today = _dayOf(DateTime.now());
                    final isPastWeek = _dayOf(_weekStart)
                        .add(const Duration(days: 6))
                        .isBefore(today);
                    final visibleSlots = isPastWeek
                        ? slots
                        : slots.where((s) => !_dayOf(s.date).isBefore(today)).toList();
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
                          return ClosureBanner(
                            closure: item,
                            onLongPress: () => showClosureActionsSheet(context, item),
                          );
                        }
                        final slot = item as SlotModel;
                        // Individuel / workshop : pas d'inscription libre,
                        // donc pas de compteur d'inscrits pertinent — ni
                        // de pop-up "inscrits / liste d'attente" (même
                        // condition que `showCount`, voir plus bas).
                        final showCount = slot.type != 'individual' && slot.type != 'workshop';
                        // Appui long "Modifier / Supprimer" pour les
                        // cours duo, individuel et workshop (pas les
                        // collectifs, fixes et régénérés chaque
                        // semaine). Les fermetures ont leur propre appui
                        // long sur `ClosureBanner`, voir plus haut.
                        final canEditOrDelete = slot.type == 'duo' ||
                            slot.type == 'individual' ||
                            slot.type == 'workshop';
                        return SlotCard(
                          slot: slot,
                          highlightAlert: true,
                          showCount: showCount,
                          onTap: showCount ? () => showSlotRosterDialog(context, slot) : null,
                          onLongPress:
                              canEditOrDelete ? () => showSlotActionsSheet(context, slot) : null,
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
      floatingActionButton: Padding(
        // Décale le bouton vers la gauche (padding à droite) et vers le
        // haut (padding en bas) par rapport à sa position par défaut
        // (bas-droite).
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
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AddCourseScreen(weekStart: _weekStart),
              ),
            ),
            child: Icon(Icons.add, color: AppColors.white, size: context.wp(32)),
          ),
        ),
      ),
    );
  }
}
