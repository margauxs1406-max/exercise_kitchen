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
///
/// [WidgetsBindingObserver] : ajouté le 21 août 2026 suite au diagnostic
/// suivant — sur iOS, la toute première négociation du token APNs auprès
/// d'Apple (juste après une installation) peut occasionnellement prendre
/// plus longtemps que le délai qu'on lui accorde ci-dessous. Jusqu'ici, un
/// échec de cette négociation était DÉFINITIF pour la session en cours :
/// aucune notification n'était jamais réessayée tant que l'app n'était pas
/// entièrement relancée depuis zéro (nouveau processus). Or un utilisateur
/// normal ne fait quasiment jamais ça — il met l'app en arrière-plan puis
/// la rouvre, ce qui ne redéclenchait rien. Constat de Margaux : seul le
/// compte utilisé pour tester (réinstallé/relancé des dizaines de fois) a
/// fini par obtenir un token ; aucun compte adhérent réel n'en a un seul.
/// On retente donc maintenant automatiquement à chaque retour au premier
/// plan de l'app, tant que l'enregistrement n'a pas encore réussi.
class PushNotificationService with WidgetsBindingObserver {
  PushNotificationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Rattaché à `MaterialApp.scaffoldMessengerKey` dans `app.dart` — permet
  /// d'afficher un bandeau sans dépendre d'un `BuildContext` d'écran précis.
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool _foregroundListenerAttached = false;
  bool _lifecycleObserverAttached = false;

  /// uid de la personne connectée pour laquelle on n'a pas encore réussi à
  /// enregistrer de token — sert à savoir s'il faut retenter au prochain
  /// retour au premier plan. `null` = rien à retenter (soit personne
  /// connectée, soit déjà enregistré avec succès).
  String? _pendingUid;

  /// À appeler une seule fois par lancement de l'app (voir `app.dart`) —
  /// protégé contre les appels multiples si jamais le widget parent est
  /// reconstruit.
  void attachForegroundListener() {
    if (!_lifecycleObserverAttached) {
      _lifecycleObserverAttached = true;
      WidgetsBinding.instance.addObserver(this);
    }
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final uid = _pendingUid;
    if (uid == null) return;
    debugPrint(
      '[PUSH] App revenue au premier plan, nouvel essai d\'enregistrement '
      'du token pour $uid (le précédent essai n\'avait pas abouti)...',
    );
    registerForUser(uid);
  }

  /// À appeler une fois la personne authentifiée (voir `RoleGate`) : demande
  /// la permission puis enregistre le token FCM de cet appareil. Ne bloque
  /// jamais l'utilisation de l'app en cas d'échec (permission refusée,
  /// émulateur sans Google Play Services...) — les notifications sont un
  /// bonus, pas un prérequis pour utiliser l'application.
  Future<void> registerForUser(String uid) async {
    // Reste "en attente" tant qu'on n'a pas confirmé un enregistrement
    // réussi — c'est ce qui permet à `didChangeAppLifecycleState` de savoir
    // s'il doit retenter au prochain retour au premier plan.
    _pendingUid = uid;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      // Trace de diagnostic (21 août 2026, aucun token iOS enregistré même
      // après ajout de GoogleService-Info.plist — TOUS les comptes iPhone,
      // pas seulement le compte coach) : si `authorizationStatus` n'est pas
      // `authorized` (ou `provisional`), c'est qu'iOS a mémorisé un refus
      // antérieur (ou n'a jamais demandé) — dans ce cas `getAPNSToken()` ne
      // recevra jamais rien, ce n'est pas un bug de notre code. À retirer
      // une fois le problème résolu.
      debugPrint(
        '[PUSH] requestPermission($uid) -> authorizationStatus=${settings.authorizationStatus}',
      );
      // Sur iOS, `getToken()` a besoin que l'appareil ait fini d'obtenir
      // son token APNs natif auprès d'Apple — une étape asynchrone
      // distincte de la simple autorisation, qui peut prendre plus de temps
      // que prévu, en particulier lors de la toute première négociation
      // après une installation. Si `getToken()` est appelé trop tôt, le
      // token FCM renvoyé existe bien comme chaîne de caractères et
      // s'enregistre normalement, mais n'est jamais relié à Apple côté
      // serveur : les envois échouent alors indéfiniment avec l'erreur FCM
      // "NotRegistered" (19-20 août 2026, diagnostiqué avec Margaux). On
      // attend donc explicitement ce token APNs (jusqu'à 20 secondes,
      // porté de 10 à 20s le 21 août 2026 — la première négociation
      // s'avère parfois plus longue que ça) avant de demander le token FCM
      // — inutile sur Android, qui n'a pas cette étape intermédiaire. En
      // cas d'échec, on NE bloque PAS définitivement : `didChangeAppLifecycleState`
      // ci-dessus retentera automatiquement au prochain retour au premier
      // plan, sans attendre un relancement complet de l'app.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        var apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        var attempts = 0;
        while (apnsToken == null && attempts < 20) {
          await Future.delayed(const Duration(seconds: 1));
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
          attempts++;
        }
        if (apnsToken == null) {
          debugPrint(
            '[PUSH] Token APNs jamais reçu après 20s pour $uid — nouvel essai '
            'au prochain retour au premier plan de l\'app.',
          );
          return;
        }
      }
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('[PUSH] registerForUser($uid) : token FCM obtenu = $token');
      if (token != null) {
        await _saveToken(uid, token);
        // Enregistrement réussi : plus besoin de retenter au retour au
        // premier plan.
        _pendingUid = null;
        debugPrint('[PUSH] registerForUser($uid) : token enregistré sur Firestore.');
      }
      // Le token peut changer en cours de vie de l'app (réinstall, reset
      // Play Services...) : on le réenregistre alors automatiquement.
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _saveToken(uid, newToken);
      });
    } catch (e) {
      debugPrint('[PUSH] Enregistrement du token FCM impossible pour $uid : $e');
    }
  }

  Future<void> _saveToken(String uid, String token) {
    return _firestore.collection('users').doc(uid).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
    });
  }
}
