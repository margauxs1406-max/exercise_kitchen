import Flutter
import UIKit
import UserNotifications

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
    // Ajout explicite (21 août 2026, suite du diagnostic — le token
    // s'enregistre désormais et la bannière système fonctionne bien app
    // fermée/arrière-plan, MAIS `FirebaseMessaging.onMessage` ne se
    // déclenche JAMAIS côté Dart quand l'app est au premier plan, constaté
    // en observant les logs en direct pendant un vrai test) : pour qu'iOS
    // transmette une notification reçue au premier plan à l'app plutôt que
    // de simplement l'ignorer, il faut qu'un délégué
    // `UNUserNotificationCenterDelegate` soit explicitement désigné — rien
    // ne le faisait jusqu'ici. On se désigne nous-mêmes ci-dessous (voir
    // l'extension en bas de ce fichier) : ça permet à la fois d'afficher la
    // bannière système même app ouverte, et de laisser le swizzling de
    // Firebase Messaging (qui intercepte cette méthode) transmettre
    // l'événement à `FirebaseMessaging.onMessage` côté Dart.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

// Correctif (21 août 2026, 4 erreurs de compilation Xcode signalées par
// Margaux) — deux causes distinctes :
// 1. PAS de ": UNUserNotificationCenterDelegate" ici — `FlutterAppDelegate`
//    (la classe dont hérite `AppDelegate`) conforme déjà elle-même à ce
//    protocole. Le redéclarer sur cette extension provoquait "Redundant
//    conformance of 'AppDelegate' to protocol
//    'UNUserNotificationCenterDelegate'".
// 2. `override` est OBLIGATOIRE sur `userNotificationCenter(...)`
//    ci-dessous — contrairement à ce qu'on pensait initialement,
//    `FlutterAppDelegate` fournit déjà une implémentation concrète de cette
//    méthode (Xcode l'a confirmé explicitement : "Overriding declaration
//    requires an 'override'"), ce n'est donc pas une méthode de protocole
//    encore jamais implémentée.
extension AppDelegate {
  // Appelée par iOS quand une notification arrive alors que l'app est au
  // premier plan. Sans ce délégué, iOS n'affichait rien du tout (ni
  // bannière système, ni transmission à Flutter) — c'était la cause du
  // bandeau interne (SnackBar) qui ne se déclenchait jamais. Le swizzling
  // de Firebase Messaging intercepte cet appel pour transmettre
  // l'événement à `FirebaseMessaging.onMessage` ; on demande en plus
  // explicitement l'affichage de la bannière système même app ouverte.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // `.banner`/`.list` n'existent que depuis iOS 14 — le projet cible
    // encore iOS 13.0 (voir notes de projet, section "Reste à faire", point
    // sur le relèvement de l'iOS Deployment Target avant le printemps
    // 2027), d'où les erreurs "'banner' is only available in iOS 14.0 or
    // newer"/idem pour 'list'. `.alert` est l'équivalent compatible iOS 13,
    // remplacé par `.banner`+`.list` à partir d'iOS 14 (dépréciation, pas
    // suppression) — on choisit donc dynamiquement selon la version réelle
    // de l'appareil, plutôt que de relever le Deployment Target du projet
    // entier pour ce seul détail.
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
}
