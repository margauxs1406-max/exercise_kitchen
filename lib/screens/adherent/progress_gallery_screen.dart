import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/progress_photo_model.dart';
import '../../services/photo_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/photo_gallery_grid.dart';
import '../../widgets/week_header.dart';
import 'adherent_profile_screen.dart';

/// Section 2.1 : galerie des photos de progression de l'adhérent connecté
/// (importées par un coach depuis sa fiche, voir
/// `adherent_photos_screen.dart`) — pas d'import ici (réservé au coach), mais
/// l'adhérent peut sélectionner ses photos par appui long pour les
/// télécharger (`onDownload`, depuis le 26 juillet 2026, à la demande de
/// Margaux) — pas de suppression possible pour lui (`onDelete` non fourni,
/// donc le bouton correspondant n'apparaît pas — voir `photo_gallery_grid.dart`).
///
/// En-tête identique à celui du planning ([WeekHeader] : logo à gauche,
/// bouton profil à droite), avec "Galerie" au centre à la place du type de
/// semaine.
class ProgressGalleryScreen extends StatelessWidget {
  final String adherentUid;
  const ProgressGalleryScreen({super.key, required this.adherentUid});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<PhotoRepository>();
    return Scaffold(
      appBar: WeekHeader(
        onProfileTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdherentProfileScreen()),
        ),
        weekTypeContent: Text(
          'Galerie'.toUpperCase(),
          style: AppTheme.headerTitleStyle,
        ),
      ),
      body: StreamBuilder<List<ProgressPhotoModel>>(
        stream: repo.watchPhotos(adherentUid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return PhotoGalleryGrid(
            photos: snapshot.data!,
            selectable: true,
            onDownload: (selected) => repo.downloadPhotos(selected),
          );
        },
      ),
    );
  }
}
