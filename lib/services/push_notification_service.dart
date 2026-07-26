import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

/// Notifications push (FCM) — section 4 des spécifications. Ne gère QUE le
/// côté client :
/// - demander la permission d'envoyer des notifications (obligatoire sur
///   Android 13+ et iOS) ;
/// - récupérer le token FCM de cet appareil et l'enregistrer sur
///   `users/{uid}.fcmTokens` (tableau — plusieurs appareils possibles pour
///   une même personne, ex. changement de téléphone) ;
/// - afficher un bandeau quand une notification arrive alors que l'app est
///   déjà ouverte au premier plan (sans ça, Android n'affiche rien tant que
///   l'app est active — seul un envoi reçu en arrière-plan/app fermée
///   déclenche automatiquement la notification système).
///
/// Tout l'envoi effectif (à qui, quand, quel texte) vit côté Cloud
/// Functions — voir `functions/src/index.ts`, section "Notifications push".
class PushNotificationService {
  PushNotificationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Rattaché à `MaterialApp.scaffoldMessengerKey` dans `app.dart` — permet
  /// d'afficher un bandeau sans dépendre d'un `BuildContext` d'écran précis.
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool _foregroundListenerAttached = false;

  /// À appeler une seule fois par lancement de l'app (voir `app.dart`) —
  /// protégé contre les appels multiples si jamais le widget parent est
  /// reconstruit.
  void attachForegroundListener() {
    if (_foregroundListenerAttached) return;
    _foregroundListenerAttached = true;
    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title;
      final body = message.notification?.body;
      if (title == null && body == null) return;
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text([title, body].whereType<String>().join(' — ')),
        ),
      );
    });
  }

  /// À appeler une fois la personne authentifiée (voir `RoleGate`) : demande
  /// la permission puis enregistre le token FCM de cet appareil. Ne bloque
  /// jamais l'utilisation de l'app en cas d'échec (permission refusée,
  /// émulateur sans Google Play Services...) — les notifications sont un
  /// bonus, pas un prérequis pour utiliser l'application.
  Future<void> registerForUser(String uid) async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _saveToken(uid, token);
      }
      // Le token peut changer en cours de vie de l'app (réinstall, reset
      // Play Services...) : on le réenregistre alors automatiquement.
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _saveToken(uid, newToken);
      });
    } catch (e) {
      debugPrint('Enregistrement du token FCM impossible : $e');
    }
  }

  Future<void> _saveToken(String uid, String token) {
    return _firestore.collection('users').doc(uid).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
    });
  }
}