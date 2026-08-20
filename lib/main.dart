import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
// Généré par `flutterfire configure` — voir README.md, étape 4.
// Ce fichier n'existe pas encore dans ce livrable : il doit être créé en
// local en connectant le projet Firebase de la salle.
import 'firebase_options.dart';

/// Doit être une fonction top-level (ou statique) — obligation de
/// `firebase_messaging` : elle est appelée dans un isolate séparé quand un
/// message arrive alors que l'app est en arrière-plan ou fermée.
///
/// Trace de diagnostic (20 août 2026, notifications iPhone toujours
/// invisibles malgré une chaîne de livraison APNs/SpringBoard confirmée
/// saine côté système) — permet de vérifier si le message atteint seulement
/// le moteur Flutter en arrière-plan ou pas du tout. À retirer une fois le
/// problème résolu.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundMessageHandler(RemoteMessage message) async {
  debugPrint(
    '[PUSH] onBackgroundMessage déclenché — title=${message.notification?.title} '
    'body=${message.notification?.body} data=${message.data} '
    'messageId=${message.messageId}',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessageHandler);
  await initializeDateFormatting('fr_FR', null);
  runApp(const ExerciseKitchenApp());
}