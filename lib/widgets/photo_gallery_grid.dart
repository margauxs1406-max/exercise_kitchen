import 'package:flutter/material.dart';

import '../models/progress_photo_model.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

const List<String> _kMonths = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// Libellé du jour affiché au-dessus de chaque groupe de photos :
/// "Aujourd'hui" / "Hier" pour les deux jours les plus récents, sinon
/// "20 juin 2026".
String _dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  if (day == today) return "Aujourd'hui";
  if (day == yesterday) return 'Hier';
  return '${day.day} ${_kMonths[day.month - 1]} ${day.year}';
}

/// Un groupe de photos prises le même jour.
class _PhotoDaySection {
  final DateTime day;
  final List<ProgressPhotoModel> photos;
  _PhotoDaySection({required this.day, required this.photos});
}

/// Regroupe [photos] par jour de prise de vue ([ProgressPhotoModel.takenAt]),
/// en un seul passage — suppose que [photos] est déjà trié par date
/// décroissante (c'est le cas : voir `PhotoRepository.watchPhotos`), donc les
/// photos d'un même jour sont forcément consécutives dans la liste.
List<_PhotoDaySection> _groupByDay(List<ProgressPhotoModel> photos) {
  final sections = <_PhotoDaySection>[];
  for (final photo in photos) {
    final day = DateTime(photo.takenAt.year, photo.takenAt.month, photo.takenAt.day);
    if (sections.isNotEmpty && sections.last.day == day) {
      sections.last.photos.add(photo);
    } else {
      sections.add(_PhotoDaySection(day: day, photos: [photo]));
    }
  }
  return sections;
}

/// Galerie de photos de progression (section 2.1), réutilisée à la fois côté
/// adhérent (lecture seule, voir `progress_gallery_screen.dart`) et côté
/// coach (import + gestion, voir `adherent_photos_screen.dart`) — même rendu
/// partout, mais la sélection multiple n'est activée que côté coach (voir
/// [selectable]).
///
/// Rangée par date de prise de vue décroissante, avec un libellé de jour
/// au-dessus de chaque groupe ("Aujourd'hui", "Hier", puis "20 juin 2026").
/// Chaque jour a sa propre mini-grille de 4 colonnes MAXIMUM — un jour avec
/// moins de 4 photos ne les étire pas pour autant, la ligne reste
/// simplement incomplète.
///
/// Un tap simple sur une vignette ouvre la photo en plein écran, avec
/// possibilité de continuer à naviguer vers les photos précédentes/suivantes
/// en balayant l'écran de gauche à droite (voir `_FullScreenPhotoGallery`).
/// Quand [selectable] vaut `true`, un appui long sur une vignette active la
/// sélection multiple : les taps suivants basculent la sélection au lieu
/// d'ouvrir le plein écran, et une barre d'actions apparaît en bas. Chaque
/// bouton de cette barre (télécharger / supprimer) n'apparaît que si le
/// callback correspondant est fourni — voir [onDelete] / [onDownload].
/// Depuis le 26 juillet 2026, l'écran adhérent (`progress_gallery_screen.dart`)
/// active la sélection avec [onDownload] seul (pas de suppression possible
/// pour un adhérent), tandis que l'écran coach (`adherent_photos_screen.dart`)
/// fournit les deux.
class PhotoGalleryGrid extends StatefulWidget {
  final List<ProgressPhotoModel> photos;
  final bool selectable;
  final Future<void> Function(List<ProgressPhotoModel> selected)? onDelete;
  final Future<void> Function(List<ProgressPhotoModel> selected)? onDownload;

  const PhotoGalleryGrid({
    super.key,
    required this.photos,
    this.selectable = false,
    this.onDelete,
    this.onDownload,
  });

  @override
  State<PhotoGalleryGrid> createState() => _PhotoGalleryGridState();
}

class _PhotoGalleryGridState extends State<PhotoGalleryGrid> {
  final Set<String> _selectedIds = {};
  bool _busy = false;

  bool get _selecting => _selectedIds.isNotEmpty;

  void _toggle(ProgressPhotoModel photo) {
    setState(() {
      if (!_selectedIds.remove(photo.id)) {
        _selectedIds.add(photo.id);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedIds.clear());

  List<ProgressPhotoModel> get _selectedPhotos =>
      widget.photos.where((p) => _selectedIds.contains(p.id)).toList();

  Future<void> _confirmDelete() async {
    final selected = _selectedPhotos;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          (selected.length > 1
                  ? 'Supprimer ces ${selected.length} photos ?'
                  : 'Supprimer cette photo ?')
              .toUpperCase(),
        ),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true || widget.onDelete == null) return;
    setState(() => _busy = true);
    try {
      await widget.onDelete!(selected);
      _clearSelection();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur lors de la suppression : $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final selected = _selectedPhotos;
    if (widget.onDownload == null) return;
    setState(() => _busy = true);
    try {
      await widget.onDownload!(selected);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            selected.length > 1
                ? '${selected.length} photos téléchargées.'
                : 'Photo téléchargée.',
          ),
        ));
      }
      _clearSelection();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur lors du téléchargement : $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.wp(24), vertical: context.hp(24)),
          child: const Text(
            'Aucune photo de progression pour le moment.',
            style: TextStyle(color: AppColors.mediumGrey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final sections = _groupByDay(widget.photos);
    return Stack(
      children: [
        ListView.builder(
          padding: EdgeInsets.fromLTRB(
            context.wp(12),
            context.hp(12),
            context.wp(12),
            _selecting ? context.hp(88) : context.hp(12),
          ),
          itemCount: sections.length,
          itemBuilder: (context, sectionIndex) {
            final section = sections[sectionIndex];
            return Padding(
              padding: EdgeInsets.only(
                bottom: context.hp(16),
                top: sectionIndex == 0 ? 0 : context.hp(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: context.hp(8), left: context.wp(4)),
                    child: Text(
                      _dayLabel(section.day),
                      style:
                          const TextStyle(fontWeight: FontWeight.w600, color: AppColors.black),
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: context.wp(6),
                      mainAxisSpacing: context.hp(6),
                    ),
                    itemCount: section.photos.length,
                    itemBuilder: (context, i) {
                      final photo = section.photos[i];
                      final selected = _selectedIds.contains(photo.id);
                      return GestureDetector(
                        onTap: () {
                          if (_selecting) {
                            _toggle(photo);
                          } else {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => _FullScreenPhotoGallery(
                                photos: widget.photos,
                                initialIndex: widget.photos.indexOf(photo),
                              ),
                              fullscreenDialog: true,
                            ));
                          }
                        },
                        onLongPress: widget.selectable ? () => _toggle(photo) : null,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(context.wp(8)),
                              child: Image.network(
                                photo.url,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return Container(
                                    color: AppColors.lightGrey,
                                    child: Center(
                                      child: SizedBox(
                                        height: context.hp(18),
                                        width: context.wp(18),
                                        child: const CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: AppColors.lightGrey,
                                  child:
                                      const Icon(Icons.broken_image, color: AppColors.mediumGrey),
                                ),
                              ),
                            ),
                            if (selected)
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.black.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(context.wp(8)),
                                  border: Border.all(color: AppColors.orange, width: 2),
                                ),
                              ),
                            if (widget.selectable && _selecting)
                              Positioned(
                                top: context.hp(4),
                                right: context.wp(4),
                                child: Icon(
                                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: selected ? AppColors.orange : AppColors.white,
                                  size: context.wp(20),
                                  shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
        // Barre d'actions "sélection multiple" (uniquement côté coach, voir
        // [selectable]) : apparaît dès qu'au moins une photo est
        // sélectionnée par appui long, au-dessus des boutons flottants
        // d'import.
        if (_selecting)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              color: AppColors.black,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: context.wp(8), vertical: context.hp(8)),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _busy ? null : _clearSelection,
                      icon: const Icon(Icons.close, color: AppColors.white),
                      tooltip: 'Annuler la sélection',
                    ),
                    Expanded(
                      child: Text(
                        '${_selectedIds.length} sélectionnée${_selectedIds.length > 1 ? 's' : ''}',
                        style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_busy)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: context.wp(12)),
                        child: SizedBox(
                          height: context.hp(20),
                          width: context.wp(20),
                          child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      )
                    else ...[
                      // Bouton "télécharger" : uniquement si l'écran appelant
                      // fournit [onDownload] (coach ET adhérent, depuis le 26
                      // juillet 2026).
                      if (widget.onDownload != null)
                        IconButton(
                          onPressed: _download,
                          icon: const Icon(Icons.download, color: AppColors.white),
                          tooltip: 'Télécharger',
                        ),
                      // Bouton "supprimer" : uniquement si l'écran appelant
                      // fournit [onDelete] (coach seulement — un adhérent ne
                      // peut pas supprimer ses photos de progression).
                      if (widget.onDelete != null)
                        IconButton(
                          onPressed: _confirmDelete,
                          icon: const Icon(Icons.delete, color: AppColors.orange),
                          tooltip: 'Supprimer',
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Visionneuse plein écran avec balayage gauche/droite entre toutes les
/// photos de la galerie ([photos]), en partant de celle sur laquelle on a
/// tapé ([initialIndex]) — remplace l'ancienne vue à une seule image.
class _FullScreenPhotoGallery extends StatefulWidget {
  final List<ProgressPhotoModel> photos;
  final int initialIndex;
  const _FullScreenPhotoGallery({required this.photos, required this.initialIndex});

  @override
  State<_FullScreenPhotoGallery> createState() => _FullScreenPhotoGalleryState();
}

class _FullScreenPhotoGalleryState extends State<_FullScreenPhotoGallery> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.white,
        title: Text(_fmtPhotoDate(widget.photos[_index].takenAt).toUpperCase()),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          return Center(
            child: InteractiveViewer(
              child: Image.network(widget.photos[i].url),
            ),
          );
        },
      ),
    );
  }
}

String _fmtPhotoDate(DateTime date) {
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  return '$d/$m/${date.year}';
}
