import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
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
      // Trace de diagnostic (20 août 2026, notifications iPhone toujours
      // invisibles malgré une chaîne de livraison APNs/SpringBoard
      // confirmée saine côté système) — INCONDITIONNELLE (avant le retour
      // anticipé ci-dessous) pour établir, sans ambiguïté cette fois, si le
      // code Dart reçoit seulement l'événement ou pas du tout quand l'app
      // est au premier plan. À retirer une fois le problème résolu.
      debugPrint(
        '[PUSH] onMessage déclenché — title=${message.notification?.title} '
        'body=${message.notification?.body} data=${message.data} '
        'messageId=${message.messageId}',
      );
      final title = message.notification?.title;
      final body = message.notification?.body;
      if (title == null && body == null) {
        debugPrint('[PUSH] onMessage : title ET body sont null — pas de SnackBar affiché.');
        return;
      }
      debugPrint('[PUSH] onMessage : affichage du SnackBar en cours...');
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text([title, body].whereType<String>().join(' — ')),
        ),
      );
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint(
        '[PUSH] onMessageOpenedApp — app rouverte via une notification : '
        'title=${message.notification?.title}',
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
      // Sur iOS, `getToken()` a besoin que l'appareil ait fini d'obtenir
      // son token APNs natif auprès d'Apple — une étape asynchrone
      // distincte de la simple autorisation, qui peut prendre quelques
      // secondes après `requestPermission()`. Si `getToken()` est appelé
      // trop tôt, le token FCM renvoyé existe bien comme chaîne de
      // caractères et s'enregistre normalement, mais n'est jamais relié à
      // Apple côté serveur : les envois échouent alors indéfiniment avec
      // l'erreur FCM "NotRegistered", quel que soit le nombre de
      // reconnexions (19-20 août 2026, diagnostiqué avec Margaux — aucune
      // notification n'arrivait jamais sur iPhone alors que la
      // configuration Apple/Firebase était pourtant correcte). On attend
      // donc explicitement ce token APNs (jusqu'à 10 secondes) avant de
      // demander le token FCM — inutile sur Android, qui n'a pas cette
      // étape intermédiaire.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        var apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        var attempts = 0;
        while (apnsToken == null && attempts < 10) {
          await Future.delayed(const Duration(seconds: 1));
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
          attempts++;
        }
        if (apnsToken == null) {
          debugPrint(
            'Token APNs jamais reçu après 10s — abandon de l\'enregistrement FCM.',
          );
          return;
        }
      }
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('[PUSH] registerForUser($uid) : token FCM obtenu = $token');
      if (token != null) {
        await _saveToken(uid, token);
        debugPrint('[PUSH] registerForUser($uid) : token enregistré sur Firestore.');
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