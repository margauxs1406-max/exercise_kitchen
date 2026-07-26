import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle correspondant à la sous-collection Firestore
/// `users/{adherentUid}/progressPhotos` — une photo de progression importée
/// par un coach (section 1.2), affichée dans la galerie de l'adhérent
/// (section 2.1).
///
/// [takenAt] est la date de prise de la photo, choisie par le coach au
/// moment de l'import (par défaut aujourd'hui) — pas forcément la même que
/// [uploadedAt] (horodatage technique de l'import lui-même), notamment pour
/// les photos d'archive importées en rattrapage. La galerie est triée sur
/// [takenAt].
///
/// Le fichier binaire lui-même vit dans Firebase Storage
/// (`progressPhotos/{adherentUid}/{id}.{ext}`, voir `storage.rules`) ; ce
/// document Firestore ne stocke que ses métadonnées et son URL de
/// téléchargement — nécessaire pour pouvoir trier/écouter en direct sans
/// lister le contenu du bucket à chaque affichage (Storage seul ne permet
/// pas ce genre de requêtes).
class ProgressPhotoModel {
  final String id;
  final String url;
  final String storagePath;
  final DateTime takenAt;
  final DateTime uploadedAt;

  const ProgressPhotoModel({
    required this.id,
    required this.url,
    required this.storagePath,
    required this.takenAt,
    required this.uploadedAt,
  });

  factory ProgressPhotoModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final uploadedAt = (data['uploadedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return ProgressPhotoModel(
      id: doc.id,
      url: data['url'] as String? ?? '',
      storagePath: data['storagePath'] as String? ?? '',
      // Repli sur `uploadedAt` pour d'éventuels anciens documents créés
      // avant l'ajout de ce champ (rétrocompatibilité).
      takenAt: (data['takenAt'] as Timestamp?)?.toDate() ?? uploadedAt,
      uploadedAt: uploadedAt,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'url': url,
        'storagePath': storagePath,
        'takenAt': Timestamp.fromDate(takenAt),
        'uploadedAt': Timestamp.fromDate(uploadedAt),
      };
}