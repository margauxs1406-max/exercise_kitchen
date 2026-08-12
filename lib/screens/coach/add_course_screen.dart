import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/planning_repository.dart';
import '../../services/registration_repository.dart';
import '../../services/user_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../utils/adaptive_pickers.dart';
import '../../widgets/picker_tile.dart';

/// Ajout au planning côté coach, en deux parties (remplace l'ancien
/// `AddDuoCourseScreen`, devenu trop limité) :
/// - "Ajouter un cours" : individuel (adhérent précis, poussé par le coach,
///   pas d'inscription) ou duo (comme avant : date + heure, 1h, 2 places) ;
/// - "Ajouter un évènement" : workshop (date, heures, description,
///   purement informatif dans le planning) ou fermeture (date + message,
///   également informatif — pas d'email/notification pour ce MVP).
class AddCourseScreen extends StatefulWidget {
  final DateTime weekStart;
  const AddCourseScreen({super.key, required this.weekStart});

  @override
  State<AddCourseScreen> createState() => _AddCourseScreenState();
}

class _AddCourseScreenState extends State<AddCourseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Explicite (déjà la valeur par défaut de Flutter) : le corps de
      // l'écran doit se réduire quand le clavier apparaît, pour que la zone
      // de scroll de l'onglet "Ajouter un évènement" puisse remonter le
      // bouton "Ajouter au planning" au-dessus du clavier plutôt que de le
      // laisser recouvert. Si ça ne suffit pas malgré ce réglage, le
      // problème vient très probablement du fichier natif Android
      // `android/app/src/main/AndroidManifest.xml`, qui doit contenir
      // `android:windowSoftInputMode="adjustResize"` sur la balise
      // `<activity android:name=".MainActivity" ...>` — sans ce réglage,
      // Android ne redimensionne jamais la vue Flutter et le clavier
      // recouvre systématiquement le bas de l'écran, quoi que fasse le code
      // Dart.
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text('Ajouter au planning'.toUpperCase()),
        bottom: TabBar(
          controller: _tabController,
          // Onglet sélectionné en blanc plein, non sélectionné en blanc
          // transparent, et la barre indicatrice en blanc — plutôt que le
          // orange par défaut du thème, qui se lisait mal sur le fond noir
          // de l'AppBar.
          labelColor: AppColors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.white,
          tabs: const [
            Tab(text: 'Ajouter un cours'),
            Tab(text: 'Ajouter un évènement'),
          ],
        ),
      ),
      // Tapoter n'importe où en dehors d'un champ de texte referme le
      // clavier et retire le focus (donc le contour orange de saisie) — par
      // défaut, Flutter garde le focus tant qu'on ne tape pas explicitement
      // dans un autre champ ou qu'on n'appuie pas sur "Terminé".
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: TabBarView(
          controller: _tabController,
          children: [
            _AddCourseTab(weekStart: widget.weekStart),
            _AddEventTab(weekStart: widget.weekStart),
          ],
        ),
      ),
    );
  }
}

/// Style commun aux deux `SegmentedButton` de cet écran (Individuel/Duo et
/// Workshop/Fermeture) : le segment sélectionné apparaît en noir avec texte
/// blanc, celui non sélectionné en blanc avec texte noir — plutôt que la
/// teinte orange claire par défaut du thème Material 3.
final ButtonStyle _kSegmentedButtonStyle = SegmentedButton.styleFrom(
  backgroundColor: AppColors.white,
  foregroundColor: AppColors.black,
  selectedBackgroundColor: AppColors.black,
  selectedForegroundColor: AppColors.white,
  side: BorderSide(color: AppColors.mediumGrey.withValues(alpha: 0.35)),
);

/// Libellé fixe au-dessus d'un champ (au lieu d'un `labelText` flottant qui,
/// une fois posé sur le contour du champ, se retrouve à moitié sur le fond
/// blanc du champ et à moitié sur le fond gris de la page).
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.hp(6)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.black,
            fontWeight: FontWeight.w600,
            fontSize: context.sp(14),
          ),
        ),
      ),
    );
  }
}

/// Format de date unique pour tout l'écran : "Le JJ/MM/AAAA", avec jour ET
/// mois toujours sur 2 chiffres (avant, "7" au lieu de "07" pouvait
/// apparaître pour les jours/mois à un seul chiffre).
String _fmtDate(DateTime d) {
  return 'Le ${_fmtDateRaw(d)}';
}

/// Même format que [_fmtDate] mais sans le "Le " devant — utilisé pour
/// composer "Du JJ/MM/AAAA au JJ/MM/AAAA" (période de fermeture), où "Le"
/// ne doit apparaître qu'une fois via "Du".
String _fmtDateRaw(DateTime d) {
  String pad2(int n) => n.toString().padLeft(2, '0');
  return '${pad2(d.day)}/${pad2(d.month)}/${d.year}';
}

// ---------------------------------------------------------------------
// Onglet 1 : "Ajouter un cours" (individuel / duo)
// ---------------------------------------------------------------------

class _AddCourseTab extends StatefulWidget {
  final DateTime weekStart;
  const _AddCourseTab({required this.weekStart});

  @override
  State<_AddCourseTab> createState() => _AddCourseTabState();
}

class _AddCourseTabState extends State<_AddCourseTab> {
  String _kind = 'individuel'; // 'individuel' | 'duo'

  DateTime? _selectedDate;
  // Plus de valeur par défaut : l'heure doit être choisie explicitement,
  // comme la date (voir "Choisir une heure" ci-dessous).
  TimeOfDay? _startTime;
  String? _selectedAdherentUid;
  String? _selectedAdherentLabel;
  // Duo : préremplissage facultatif des 2 places (section 1.3, 7 août 2026)
  // — quand le coach connaît déjà les 2 adhérents concernés. Margaux a
  // confirmé que ceci doit être une VRAIE inscription (compte dans la
  // capacité), pas une simple note — voir `coachRegisterAdherentForSlot`.
  // Les deux restent facultatifs : le coach peut aussi créer un duo "vide",
  // ouvert aux inscriptions libres, comme avant.
  String? _duoAdherent1Uid;
  String? _duoAdherent1Label;
  String? _duoAdherent2Uid;
  String? _duoAdherent2Label;
  bool _submitting = false;

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: widget.weekStart,
      firstDate: widget.weekStart,
      lastDate: widget.weekStart.add(const Duration(days: 6)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showAdaptiveTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _submit() async {
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Choisis une date dans la semaine.')));
      return;
    }
    if (_startTime == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Choisis une heure.')));
      return;
    }
    if (_kind == 'individuel' && _selectedAdherentUid == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Choisis un adhérent.')));
      return;
    }
    if (_kind == 'duo' &&
        _duoAdherent1Uid != null &&
        _duoAdherent2Uid != null &&
        _duoAdherent1Uid == _duoAdherent2Uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Les 2 adhérents doivent être différents.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final repo = context.read<PlanningRepository>();
      if (_kind == 'individuel') {
        await repo.addIndividualSlot(
          date: _selectedDate!,
          startTime: _fmt(_startTime!),
          adherentUid: _selectedAdherentUid!,
          adherentLabel: _selectedAdherentLabel!,
        );
      } else {
        final slotId =
            await repo.addDuoSlotForWeek(date: _selectedDate!, startTime: _fmt(_startTime!));
        final registrationRepo = context.read<RegistrationRepository>();
        for (final uid in [_duoAdherent1Uid, _duoAdherent2Uid]) {
          if (uid == null) continue;
          await registrationRepo.coachRegisterAdherentForSlot(
            slotId: slotId,
            adherentUid: uid,
          );
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Erreur lors de l'ajout : $e")));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            style: _kSegmentedButtonStyle,
            segments: const [
              ButtonSegment(value: 'individuel', label: Text('Individuel')),
              ButtonSegment(value: 'duo', label: Text('Duo')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          SizedBox(height: context.hp(20)),
          PickerTile(
            icon: Icons.calendar_today,
            label: _selectedDate == null ? 'Choisir une date' : _fmtDate(_selectedDate!),
            valueSet: _selectedDate != null,
            onTap: _pickDate,
          ),
          SizedBox(height: context.hp(12)),
          PickerTile(
            icon: Icons.access_time,
            label: _startTime == null ? 'Choisir une heure' : 'Début : ${_fmt(_startTime!)}',
            valueSet: _startTime != null,
            onTap: _pickStartTime,
          ),
          if (_kind == 'individuel') ...[
            SizedBox(height: context.hp(12)),
            _AdherentPicker(
              requiredFormula: 'individuel',
              fieldLabel: 'Adhérent',
              emptyMessage: "Aucun adhérent actif n'a la formule Individuel pour l'instant.",
              selectedUid: _selectedAdherentUid,
              selectedLabel: _selectedAdherentLabel,
              onSelected: (uid, label) => setState(() {
                _selectedAdherentUid = uid;
                _selectedAdherentLabel = label;
              }),
            ),
          ],
          // Duo : préremplissage facultatif des 2 places (7 août 2026) — les
          // deux sélecteurs sont indépendants et restent vides par défaut,
          // le coach peut aussi n'en remplir qu'un seul, ou aucun.
          if (_kind == 'duo') ...[
            SizedBox(height: context.hp(12)),
            _AdherentPicker(
              requiredFormula: 'duo',
              fieldLabel: '1er adhérent (facultatif)',
              emptyMessage: "Aucun adhérent actif n'a la formule Duo pour l'instant.",
              selectedUid: _duoAdherent1Uid,
              selectedLabel: _duoAdherent1Label,
              onSelected: (uid, label) => setState(() {
                _duoAdherent1Uid = uid;
                _duoAdherent1Label = label;
              }),
            ),
            SizedBox(height: context.hp(12)),
            _AdherentPicker(
              requiredFormula: 'duo',
              fieldLabel: '2e adhérent (facultatif)',
              emptyMessage: "Aucun adhérent actif n'a la formule Duo pour l'instant.",
              selectedUid: _duoAdherent2Uid,
              selectedLabel: _duoAdherent2Label,
              onSelected: (uid, label) => setState(() {
                _duoAdherent2Uid = uid;
                _duoAdherent2Label = label;
              }),
            ),
          ],
          SizedBox(height: context.hp(24)),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? SizedBox(
                    height: context.hp(20),
                    width: context.wp(20),
                    child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Ajouter au planning'),
          ),
        ],
      ),
    );
  }
}

/// Sélecteur d'adhérent — utilisé pour un cours individuel (limité aux
/// adhérents actifs ayant souscrit la formule "Individuel", sinon le
/// créneau créé ne serait même pas visible pour eux côté planning, voir
/// `weekly_planning_screen.dart`) ET, depuis le 7 août 2026, pour
/// préremplir à l'avance les 2 places d'un cours duo (formule "Duo").
/// [requiredFormula] généralise ce qui était auparavant câblé en dur sur
/// `'individuel'`.
///
/// Utilise `showMenu` + `PopupMenuItem`/`PopupMenuDivider` (et non
/// `DropdownMenu`, ni `DropdownButtonFormField`) : `showMenu` donne un
/// contrôle total sur la couleur de fond du menu (blanc, plutôt que la
/// teinte orange pâle que `DropdownMenu` dérivait automatiquement du thème
/// via `ColorScheme.fromSeed`) et permet d'insérer un `PopupMenuDivider`
/// (gris clair) entre chaque adhérent. Le déclencheur est le `PickerTile`
/// déjà utilisé pour "Choisir une date"/"Choisir une heure", ce qui garantit
/// que "Choisir un adhérent" a exactement le même style/taille que les
/// deux autres — sans dupliquer aucune valeur de style.
class _AdherentPicker extends StatefulWidget {
  final String requiredFormula;
  final String fieldLabel;
  final String emptyMessage;
  final String? selectedUid;
  final String? selectedLabel;
  final void Function(String uid, String label) onSelected;

  const _AdherentPicker({
    required this.requiredFormula,
    required this.fieldLabel,
    required this.emptyMessage,
    required this.selectedUid,
    required this.selectedLabel,
    required this.onSelected,
  });

  @override
  State<_AdherentPicker> createState() => _AdherentPickerState();
}

class _AdherentPickerState extends State<_AdherentPicker> {
  final _fieldKey = GlobalKey();

  Future<void> _openMenu(List<UserModel> eligible) async {
    final box = _fieldKey.currentContext!.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight =
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
    // Décalage de 8px vers le haut (10 août 2026, demande de Margaux —
    // "supprime le blanc tout en haut des listes déroulantes") : `showMenu`
    // ajoute systématiquement un padding vertical interne de 8px avant le
    // premier élément (constante interne du framework Material, stable
    // depuis les premières versions de Flutter, non exposée publiquement
    // pour être désactivée autrement) — ce décalage compense exactement ce
    // padding en remontant tout le menu de 8px, pour que le premier
    // adhérent apparaisse directement sous le champ, sans bande blanche
    // visible au-dessus.
    final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight - const Offset(0, 8)),
      Offset.zero & overlay.size,
    );

    // Un `PopupMenuDivider` (gris clair par défaut) entre chaque adhérent,
    // mais pas avant le premier ni après le dernier.
    final items = <PopupMenuEntry<String>>[];
    for (var i = 0; i < eligible.length; i++) {
      if (i > 0) items.add(PopupMenuDivider(height: context.hp(1)));
      items.add(PopupMenuItem<String>(
        value: eligible[i].uid,
        child: Text(eligible[i].fullName),
      ));
    }

    final uid = await showMenu<String>(
      context: context,
      position: position,
      color: AppColors.white,
      // Hauteur maximale de 5 adhérents (9 août 2026, demande de Margaux) —
      // au-delà, la liste défile à l'intérieur du menu plutôt que de
      // grandir indéfiniment (`showMenu` insère automatiquement un
      // `SingleChildScrollView` quand le contenu dépasse `constraints`).
      // `kMinInteractiveDimension` (48) est la hauteur par défaut d'un
      // `PopupMenuItem` — pas une valeur de mise en page qu'on invente
      // nous-mêmes, donc laissée telle quelle (non `context.wp/hp`) ; seuls
      // les `PopupMenuDivider` entre les éléments sont responsive.
      constraints: BoxConstraints(
        minWidth: box.size.width,
        maxWidth: box.size.width,
        maxHeight: 5 * kMinInteractiveDimension + 4 * context.hp(1),
      ),
      // Correctif (12 août 2026, signalé par Margaux : "j'ai vu le texte se
      // dérouler, puis les bandeaux blancs") : bug connu du framework
      // Flutter, où l'animation d'ouverture par défaut d'un `showMenu`
      // fait apparaître le TEXTE de chaque `PopupMenuItem` légèrement avant
      // que son fond blanc ne soit complètement peint (les 2 éléments
      // s'animent selon des calendriers internes légèrement différents) —
      // un décalage d'une fraction de seconde, mais visible à l'œil. Comme
      // ce menu ne contient qu'une poignée d'adhérents (pas d'animation
      // "utile" à voir de toute façon), on désactive entièrement
      // l'animation d'ouverture/fermeture : le menu apparaît/disparaît
      // instantanément, ce qui élimine ce décalage puisqu'il n'y a plus de
      // période de transition pendant laquelle il pourrait être visible.
      popUpAnimationStyle: AnimationStyle(duration: Duration.zero, reverseDuration: Duration.zero),
      items: items,
    );
    if (uid == null) return;
    final match = eligible.firstWhere((a) => a.uid == uid);
    // Nom complet dans la liste ci-dessus (pour identifier sans ambiguïté
    // pendant la sélection), mais nom court ("Prénom L") pour le libellé
    // retenu : c'est ce libellé qui compose le titre du cours individuel
    // affiché ensuite dans le planning (voir
    // `PlanningRepository.addIndividualSlot`).
    widget.onSelected(uid, match.shortName);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserRepository>();
    return StreamBuilder<List<UserModel>>(
      stream: repo.watchAdherents(),
      builder: (context, snapshot) {
        final eligible = (snapshot.data ?? const <UserModel>[])
            .where((a) => a.isActive && a.formulas.contains(widget.requiredFormula))
            .toList();
        if (!snapshot.hasData) {
          return const LinearProgressIndicator();
        }
        if (eligible.isEmpty) {
          return Text(
            widget.emptyMessage,
            style: const TextStyle(color: AppColors.mediumGrey),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldLabel(widget.fieldLabel),
            KeyedSubtree(
              key: _fieldKey,
              child: PickerTile(
                icon: Icons.person,
                label: widget.selectedLabel ?? 'Choisir un adhérent',
                valueSet: widget.selectedLabel != null,
                onTap: () => _openMenu(eligible),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// Onglet 2 : "Ajouter un évènement" (workshop / fermeture)
// ---------------------------------------------------------------------

class _AddEventTab extends StatefulWidget {
  final DateTime weekStart;
  const _AddEventTab({required this.weekStart});

  @override
  State<_AddEventTab> createState() => _AddEventTabState();
}

class _AddEventTabState extends State<_AddEventTab> with WidgetsBindingObserver {
  String _kind = 'workshop'; // 'workshop' | 'fermeture'

  // Workshop : une seule date, plus heure de début/fin.
  DateTime? _selectedDate;
  // 8h-12h par défaut pour un workshop.
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 12, minute: 0);
  final _titleController = TextEditingController(text: 'Workshop');
  final _descriptionController = TextEditingController();
  // Fermeture : une période (date de début/fin), pas d'heure — une
  // fermeture couvre des jours entiers.
  DateTime? _closureStartDate;
  DateTime? _closureEndDate;
  final _messageController = TextEditingController();
  // Contrôle le défilement de la zone de formulaire ci-dessous — utilisé
  // pour la faire défiler automatiquement jusqu'en bas dès que le clavier
  // s'ouvre (voir `didChangeMetrics`), afin que le bouton "Ajouter au
  // planning" remonte au-dessus du clavier au lieu de rester recouvert.
  final _scrollController = ScrollController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  // Appelé par Flutter à chaque changement des dimensions de la fenêtre —
  // notamment quand le clavier apparaît ou disparaît. On lit l'inset brut de
  // la fenêtre via `View.of(context)` (et non
  // `MediaQuery.of(context).viewInsets.bottom`, qui serait remis à zéro ici
  // par le `Scaffold` parent puisque `resizeToAvoidBottomInset` est actif —
  // il ne refléterait donc jamais l'ouverture du clavier à cet endroit de
  // l'arbre de widgets) : ça permet de détecter fiablement que le clavier
  // vient de s'ouvrir, et de faire défiler la zone de formulaire jusqu'en
  // bas pour révéler le bouton au-dessus de lui.
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final view = View.of(context);
    final bottomInset = view.viewInsets.bottom / view.devicePixelRatio;
    if (bottomInset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Les workshops/fermetures ne sont pas limités à la semaine affichée :
    // `initialDate` peut donc toujours être aujourd'hui (voir `firstDate`).
    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  /// Choix de la période de fermeture (23 juillet 2026, à la demande de
  /// Margaux) : un seul calendrier de plage (`showDateRangePicker`) plutôt
  /// que deux sélecteurs de date séparés (début/fin) — on touche
  /// directement le premier et le dernier jour dans le même calendrier,
  /// comme pour réserver des dates d'hôtel. Une fermeture d'un seul jour
  /// reste possible en touchant deux fois le même jour (comportement
  /// standard du composant Flutter).
  Future<void> _pickClosureRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialRange = _closureStartDate != null
        ? DateTimeRange(start: _closureStartDate!, end: _closureEndDate ?? _closureStartDate!)
        : null;
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: today,
      lastDate: now.add(const Duration(days: 180)),
      helpText: 'Période de fermeture',
      saveText: 'OK',
    );
    if (picked == null) return;
    setState(() {
      _closureStartDate = picked.start;
      _closureEndDate = picked.end;
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showAdaptiveTimePicker(
        context: context, initialTime: isStart ? _startTime : _endTime);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_kind == 'workshop') {
      if (_selectedDate == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Choisis une date.')));
        return;
      }
    } else {
      if (_closureStartDate == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Choisis une date de début.')));
        return;
      }
      if (_messageController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Ajoute un message pour les adhérents.')));
        return;
      }
    }
    setState(() => _submitting = true);
    try {
      final repo = context.read<PlanningRepository>();
      if (_kind == 'workshop') {
        await repo.addWorkshop(
          date: _selectedDate!,
          startTime: _fmt(_startTime),
          endTime: _fmt(_endTime),
          title: _titleController.text.trim().isEmpty ? 'Workshop' : _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
        );
      } else {
        await repo.addClosure(
          startDate: _closureStartDate!,
          // Toujours non-null en pratique (`_pickClosureRange` renseigne les
          // deux dates d'un coup via `showDateRangePicker`), mais on retombe
          // dessus par défense.
          endDate: _closureEndDate ?? _closureStartDate!,
          message: _messageController.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Erreur lors de l'ajout : $e")));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Bandeau fixe, de la même couleur que le fond de la page
        // (`AppColors.lightGrey` = `scaffoldBackgroundColor`), qui porte le
        // sélecteur Workshop/Fermeture. Contrairement au reste du
        // formulaire, il ne fait PAS partie de la zone de scroll ci-dessous
        // : il reste donc toujours visible et immobile, y compris quand le
        // clavier s'ouvre — seule la zone de scroll en dessous se réduit
        // alors pour laisser la place au clavier (et pousser le bouton
        // "Ajouter au planning" au-dessus de celui-ci).
        Container(
          width: double.infinity,
          color: AppColors.lightGrey,
          // Marge réduite sous le sélecteur (8 au lieu de 16) : combinée à
          // la marge réduite en haut de la zone de scroll ci-dessous (12 au
          // lieu de 20), l'écart total entre le sélecteur et le champ
          // "Date" repasse à 20 — comme dans l'onglet "Ajouter un cours" —
          // au lieu des 36 qui créaient un grand vide.
          padding: EdgeInsets.fromLTRB(
              context.wp(16), context.hp(16), context.wp(16), context.hp(8)),
          child: SegmentedButton<String>(
            style: _kSegmentedButtonStyle,
            segments: const [
              ButtonSegment(value: 'workshop', label: Text('Workshop')),
              ButtonSegment(value: 'fermeture', label: Text('Fermeture')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
                context.wp(16), context.hp(12), context.wp(16), context.hp(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_kind == 'workshop') ...[
                  PickerTile(
                    icon: Icons.calendar_today,
                    label: _selectedDate == null ? 'Choisir une date' : _fmtDate(_selectedDate!),
                    valueSet: _selectedDate != null,
                    onTap: _pickDate,
                  ),
                  SizedBox(height: context.hp(12)),
                  // Début et fin côte à côte sur une même ligne, chacun
                  // moitié moins large qu'auparavant.
                  Row(
                    children: [
                      Expanded(
                        child: PickerTile(
                          icon: Icons.access_time,
                          label: 'Début : ${_fmt(_startTime)}',
                          valueSet: true,
                          onTap: () => _pickTime(isStart: true),
                        ),
                      ),
                      SizedBox(width: context.wp(12)),
                      Expanded(
                        child: PickerTile(
                          icon: Icons.access_time,
                          label: 'Fin : ${_fmt(_endTime)}',
                          valueSet: true,
                          onTap: () => _pickTime(isStart: false),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: context.hp(12)),
                  const _FieldLabel('Titre'),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(),
                  ),
                  SizedBox(height: context.hp(12)),
                  const _FieldLabel('Description (facultatif)'),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    // 4px de moins en haut et en bas que le padding vertical
                    // par défaut du thème (14), soit 8px de moins au total
                    // sur la hauteur de la zone de saisie.
                    decoration: InputDecoration(
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(10)),
                    ),
                  ),
                ] else ...[
                  // Période choisie en un seul calendrier de plage (23
                  // juillet 2026, à la demande de Margaux) — voir
                  // `_pickClosureRange`. Affiche "Choisir une période" tant
                  // qu'aucune date n'est sélectionnée, puis soit une seule
                  // date (fermeture d'un jour) soit "Du XX/XX/XXXX au
                  // XX/XX/XXXX" (format demandé par Margaux le 26 juillet
                  // 2026, remplace le précédent "début → fin").
                  PickerTile(
                    icon: Icons.calendar_today,
                    label: _closureStartDate == null
                        ? 'Choisir une période'
                        : (_closureEndDate == null || _closureEndDate!.isAtSameMomentAs(_closureStartDate!)
                            ? _fmtDate(_closureStartDate!)
                            : 'Du ${_fmtDateRaw(_closureStartDate!)} au ${_fmtDateRaw(_closureEndDate!)}'),
                    valueSet: _closureStartDate != null,
                    onTap: _pickClosureRange,
                  ),
                  SizedBox(height: context.hp(12)),
                  const _FieldLabel('Message affiché aux adhérents'),
                  TextFormField(
                    controller: _messageController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Ex. : Salle fermée exceptionnellement, réouverture demain.',
                    ),
                  ),
                ],
                SizedBox(height: context.hp(24)),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? SizedBox(
                          height: context.hp(20),
                          width: context.wp(20),
                          child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Ajouter au planning'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
