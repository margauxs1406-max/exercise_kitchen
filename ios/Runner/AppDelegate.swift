import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Ajout explicite (21 août 2026, diagnostic notifications iPhone) : en
    // théorie, le "method swizzling" de Firebase Messaging (bien actif,
    // confirmé par "FIRMessaging Remote Notifications proxy enabled" dans
    // les logs) est censé appeler ceci automatiquement dès que la personne
    // accorde la permission de notifications. En pratique, constaté avec
    // Margaux : `getAPNSToken()` n'aboutit jamais côté Dart, même après 20
    // secondes d'attente et plusieurs nouvelles tentatives, alors que
    // `authorizationStatus` confirme bien `authorized`. On appelle donc
    // maintenant ceci explicitement, en plus du mécanisme automatique — cet
    // appel est sans risque même avant que la permission soit accordée (il
    // ne déclenche lui-même aucune fenêtre de permission ; il indique juste
    // à iOS de fournir le token dès qu'il sera disponible et autorisé).
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
