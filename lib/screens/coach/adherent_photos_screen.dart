import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/progress_photo_model.dart';
import '../../models/user_model.dart';
import '../../services/photo_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import '../../widgets/photo_gallery_grid.dart';

/// Section 1.2 : galerie + import des photos de progression d'un adhérent,
/// ouverte depuis sa fiche (voir `adherent_detail_screen.dart`). Le coach
/// choisit d'abord la date de prise de vue (par défaut aujourd'hui, pour
/// pouvoir aussi rattraper d'anciennes photos), puis :
/// - soit prend une photo à l'appareil (bouton appareil photo) ;
/// - soit en choisit plusieurs d'un coup dans la galerie du téléphone
///   (bouton galerie, sélection multiple) — pratique pour importer tout
///   l'historique d'un adhérent déjà inscrit avant cette fonctionnalité.
class AdherentPhotosScreen extends StatefulWidget {
  final UserModel adherent;
  const AdherentPhotosScreen({super.key, required this.adherent});

  @override
  State<AdherentPhotosScreen> createState() => _AdherentPhotosScreenState();
}

class _AdherentPhotosScreenState extends State<AdherentPhotosScreen> {
  bool _uploadingCamera = false;
  bool _uploadingGallery = false;

  bool get _uploading => _uploadingCamera || _uploadingGallery;

  Future<void> _importFromCamera() async {
    final date = await _pickDate();
    if (date == null || !mounted) return;

    // `imageQuality: 85` : compression légère à la source, pour limiter le
    // poids uploadé (photos de progression prises régulièrement, pas besoin
    // du fichier brut de l'appareil).
    final photo =
        await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
    if (photo == null || !mounted) return;

    await _upload([photo], date, camera: true);
  }

  Future<void> _importFromGallery() async {
    final date = await _pickDate();
    if (date == null || !mounted) return;

    // Sélection multiple : toutes les photos choisies sont importées avec
    // la même date de prise de vue sélectionnée ci-dessus.
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (picked.isEmpty || !mounted) return;

    await _upload(picked, date, camera: false);
  }

  Future<void> _upload(List<XFile> files, DateTime date, {required bool camera}) async {
    setState(() => camera ? _uploadingCamera = true : _uploadingGallery = true);
    try {
      await Future.wait(files.map(
        (file) => context.read<PhotoRepository>().uploadPhoto(
              adherentUid: widget.adherent.uid,
              takenAt: date,
              file: File(file.path),
            ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erreur lors de l'import : $e")));
      }
    } finally {
      if (mounted) {
        setState(() => camera ? _uploadingCamera = false : _uploadingGallery = false);
      }
    }
  }

  Future<DateTime?> _pickDate() {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: now,
      // Une photo ne peut pas avoir été prise dans le futur ; en revanche on
      // autorise à remonter loin dans le passé pour les photos d'archive.
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      locale: const Locale('fr', 'FR'),
      helpText: 'Date de la photo',
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<PhotoRepository>();
    return Scaffold(
      appBar: AppBar(title: Text('Photos'.toUpperCase())),
      body: StreamBuilder<List<ProgressPhotoModel>>(
        stream: repo.watchPhotos(widget.adherent.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return PhotoGalleryGrid(
            photos: snapshot.data!,
            // Sélection multiple par appui long — uniquement côté coach
            // (l'écran adhérent, `progress_gallery_screen.dart`, n'active
            // pas `selectable` et reste en lecture seule).
            selectable: true,
            onDelete: (selected) => repo.deletePhotos(widget.adherent.uid, selected),
            onDownload: (selected) => repo.downloadPhotos(selected),
          );
        },
      ),
      // Deux boutons ronds distincts, rangés verticalement (appareil photo
      // au-dessus, galerie en sélection multiple en dessous), légèrement
      // remontés et décalés à gauche par rapport à la position standard
      // "bas à droite" — voir `_RaisedEndFabLocation` ci-dessous. `heroTag`
      // distinct sur chacun, obligatoire dès qu'il y a plus d'un
      // `FloatingActionButton` sur le même écran.
      floatingActionButtonLocation: _RaisedEndFabLocation(context),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'adherentPhotosCamera',
            backgroundColor: AppColors.black,
            shape: const CircleBorder(),
            onPressed: _uploading ? null : _importFromCamera,
            child: _uploadingCamera
                ? SizedBox(
                    height: context.hp(22),
                    width: context.wp(22),
                    child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.add_a_photo, color: AppColors.white),
          ),
          SizedBox(height: context.hp(16)),
          FloatingActionButton(
            heroTag: 'adherentPhotosGallery',
            backgroundColor: AppColors.black,
            shape: const CircleBorder(),
            onPressed: _uploading ? null : _importFromGallery,
            child: _uploadingGallery
                ? SizedBox(
                    height: context.hp(22),
                    width: context.wp(22),
                    child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.photo_library, color: AppColors.white),
          ),
        ],
      ),
    );
  }
}

/// Position personnalisée des deux boutons d'ajout de photo. Part de la
/// position standard "en bas à droite" (`endFloat`) puis la remonte de
/// [_raiseBy] pixels et la décale de [_shiftLeftBy] pixels vers la gauche —
/// pour ajuster, change uniquement ces deux valeurs.
///
/// Prend un [BuildContext] (transmis par l'écran appelant, via
/// `context.wp`/`context.hp`) car `getOffset` ne reçoit lui-même qu'un
/// `ScaffoldPrelayoutGeometry`, sans accès à `MediaQuery`.
class _RaisedEndFabLocation extends FloatingActionButtonLocation {
  final BuildContext context;
  _RaisedEndFabLocation(this.context);

  // Remonté suffisamment pour dégager le bandeau "X sélectionnée(s)" qui
  // apparaît en bas pendant la sélection multiple (voir
  // `photo_gallery_grid.dart`) — pour ajuster, change uniquement cette
  // valeur (et `_shiftLeftBy` juste en dessous pour le décalage horizontal).
  static const double _raiseBy = 88;
  static const double _shiftLeftBy = 12;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final endOffset = FloatingActionButtonLocation.endFloat.getOffset(scaffoldGeometry);
    return Offset(endOffset.dx - context.wp(_shiftLeftBy), endOffset.dy - context.hp(_raiseBy));
  }
}
