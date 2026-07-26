import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;
import 'package:gal/gal.dart';

import '../models/progress_photo_model.dart';

/// Gère les photos de progression (section 1.2 / 2.1) : import par un coach
/// depuis la fiche d'un adhérent (`adherent_photos_screen.dart`),
/// consultation par l'adhérent lui-même (`progress_gallery_screen.dart`).
///
/// Le fichier binaire est stocké dans Firebase Storage
/// (`progressPhotos/{adherentUid}/{id}.{ext}`) ; ses métadonnées (URL, date
/// de prise de vue) vivent dans la sous-collection Firestore
/// `users/{adherentUid}/progressPhotos/{id}`.
class PhotoRepository {
  PhotoRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> _photosOf(String adherentUid) =>
      _firestore.collection('users').doc(adherentUid).collection('progressPhotos');

  /// Galerie de progression d'un adhérent, triée par date de prise de vue
  /// ([ProgressPhotoModel.takenAt]), la plus récente en premier.
  Stream<List<ProgressPhotoModel>> watchPhotos(String adherentUid) {
    return _photosOf(adherentUid)
        .orderBy('takenAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(ProgressPhotoModel.fromFirestore).toList());
  }

  /// Coach : importe une photo de progression pour [adherentUid], prise le
  /// [takenAt] (par défaut aujourd'hui, modifiable — notamment pour
  /// rattraper d'anciennes photos d'un adhérent historique) — upload du
  /// fichier vers Storage puis création du document de métadonnées une fois
  /// l'upload terminé (pour ne jamais avoir de document Firestore pointant
  /// vers un fichier qui n'existe pas encore).
  Future<void> uploadPhoto({
    required String adherentUid,
    required DateTime takenAt,
    required File file,
  }) async {
    final docRef = _photosOf(adherentUid).doc();
    // Conserve l'extension d'origine (une sélection multiple depuis la
    // galerie peut mélanger JPEG et PNG, par ex. de vieilles captures
    // d'écran) plutôt que de forcer `.jpg` pour tout le monde.
    final dotIndex = file.path.lastIndexOf('.');
    final ext = dotIndex == -1 ? 'jpg' : file.path.substring(dotIndex + 1).toLowerCase();
    final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
    final storagePath = 'progressPhotos/$adherentUid/${docRef.id}.$ext';
    final ref = _storage.ref(storagePath);
    await ref.putFile(file, SettableMetadata(contentType: contentType));
    final url = await ref.getDownloadURL();
    final now = DateTime.now();

    await docRef.set(ProgressPhotoModel(
      id: docRef.id,
      url: url,
      storagePath: storagePath,
      takenAt: takenAt,
      uploadedAt: now,
    ).toFirestore());
  }

  /// Coach : supprime une photo de progression — le fichier dans Storage
  /// puis son document de métadonnées dans Firestore (dans cet ordre : si la
  /// suppression du fichier échoue, on garde le document pointant vers un
  /// fichier existant plutôt que l'inverse).
  Future<void> deletePhoto(String adherentUid, ProgressPhotoModel photo) async {
    await _storage.ref(photo.storagePath).delete();
    await _photosOf(adherentUid).doc(photo.id).delete();
  }

  /// Coach : supprime plusieurs photos sélectionnées d'un coup (sélection
  /// multiple par appui long dans la galerie, voir `photo_gallery_grid.dart`).
  Future<void> deletePhotos(String adherentUid, List<ProgressPhotoModel> photos) {
    return Future.wait(photos.map((p) => deletePhoto(adherentUid, p)));
  }

  /// Télécharge une photo depuis son URL et l'enregistre dans la galerie
  /// photos du téléphone (app "Photos"/"Galerie" native, pas seulement dans
  /// l'app) via le paquet `gal`. Utilise `HttpClient` + `consolidateHttpClientResponseBytes`
  /// (déjà fourni par Flutter) plutôt qu'une dépendance HTTP supplémentaire.
  Future<void> _downloadToGallery(ProgressPhotoModel photo) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(photo.url));
      final response = await request.close();
      final Uint8List bytes = await consolidateHttpClientResponseBytes(response);
      await Gal.putImageBytes(bytes, name: 'exercise_kitchen_${photo.id}');
    } finally {
      client.close();
    }
  }

  /// Coach : télécharge plusieurs photos sélectionnées d'un coup.
  Future<void> downloadPhotos(List<ProgressPhotoModel> photos) {
    return Future.wait(photos.map(_downloadToGallery));
  }
}