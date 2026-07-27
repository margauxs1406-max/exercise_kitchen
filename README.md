# Exercise Kitchen

Application mobile coach / adhérent pour la méthode Functional Pattern.
Ce document reflète l'état d'avancement au **26 juillet 2026**.

Le projet est allé bien au-delà du MVP initial (section 6 des
spécifications techniques) : la quasi-totalité des priorités 2 et 3 du
document de spécifications sont déjà implémentées (notifications push,
galerie de photos de progression, profil adhérent, déverrouillage
biométrique, cycle de 6 semaines, périodes de fermeture...). **Le seul
point du document de spécifications encore non couvert à ce jour est la
bibliothèque de points d'automassage façon GOWOD (sections 1.5 / 2.3) et
le questionnaire/score d'hydratation (section 2.4)** — voir "Non couvert
à ce jour" plus bas.

Le code est déjà en cours de test réel sur le téléphone de Margaux
(Android) ; le dossier `ios/` existe et est configuré, en attente d'un
premier test sur Mac.

## Ce qui est implémenté

**Authentification et rôles (section 3)**
- Connexion par email/mot de passe, rôles coach/adhérent, personne ne peut
  s'auto-inscrire (comptes créés par un coach).
- Mot de passe temporaire à la création d'un compte adhérent (email envoyé
  via l'extension Firebase "Trigger Email from Firestore"), écran de
  consentement RGPD, changement de mot de passe.
- Mot de passe oublié (email de réinitialisation Firebase).
- Reconnexion obligatoire après fermeture complète de l'app pour les
  adhérents (les coachs gardent une session persistante) — voir
  `app_lock_gate.dart`/`auth_service.dart`.
- Déverrouillage biométrique optionnel (Face ID / empreinte), en plus de la
  reconnexion ci-dessus — `biometric_auth_service.dart`.

**Planning et inscriptions (sections 1.3–1.4, 2.2)**
- Planning hebdomadaire : cours collectifs récurrents (générés
  automatiquement, `default_collective_schedule.dart`), cours duo et
  individuels ajoutés par le coach, workshops et fermetures.
- Inscription, liste d'attente (promotion automatique en cas de
  désistement), alerte créneau à un seul inscrit, alerte double inscription
  le même jour.
- Semaine glissante (inscription à la semaine suivante ouverte à partir du
  vendredi), navigation par balayage ou flèches, historique des semaines
  passées.
- Cycle de 6 semaines (2 basiques, 2 intermédiaires, 2 dynamiques),
  configurable par le coach — `planning_repository.dart`.
- Fiche adhérent, création/clôture de compte — `screens/coach/`.

**Photos de progression (sections 1.2, 2.1)**
- Import par le coach (appareil photo ou galerie, sélection multiple),
  consultation par l'adhérent.
- Téléchargement des photos dans la pellicule du téléphone par appui long,
  pour le coach ET l'adhérent (l'adhérent ne peut pas supprimer ses photos,
  seul le coach le peut) — `photo_gallery_grid.dart`.

**Notifications push (FCM, section 4)**
- Six catégories : passage de liste d'attente à inscrit, créneau à un seul
  inscrit, rappel de cours (2h avant), rappel Rekovery (30 min avant, aux
  coachs), création/modification d'un workshop ou d'une fermeture,
  modification/annulation d'un cours duo/individuel.
- Préférences de notification par type, modifiables par chaque adhérent
  (`notification_settings_screen.dart`).

**Profil adhérent**
- Consultation/modification des informations, changement de mot de passe,
  activation du déverrouillage biométrique, préférences de notifications,
  FAQ, politique de confidentialité.

**Design**
- Police Poppins sur les titres (pages, pop-up, en-tête), en majuscules,
  espacement des lettres resserré de 5%.
- Toute l'app est responsive (`theme/responsive.dart` — `context.wp/hp/sp`) :
  aucune dimension en dur, tout est calculé en pourcentage de la taille
  réelle de l'écran. **Convention à respecter pour tout code futur.**
- Icône adaptative Android (suit le thème de contours du téléphone), fond
  de démarrage noir, nom affiché "Exercise Kitchen" sur Android et iOS.

**Configuration native**
- Android : permissions (biométrie, notifications), icône adaptative,
  splash natif, nom affiché — tout est en place.
- iOS : dossier `ios/` généré et configuré (icône, `Info.plist` avec les
  autorisations caméra/photos/Face ID/notifications en arrière-plan) — reste
  à activer la capacité "Push Notifications" dans Xcode (Signing &
  Capabilities) avant le premier test, voir "Étapes restantes" plus bas.

**Infrastructure**
- Projet Firebase déjà créé et connecté (`exercise-kitchen`, voir
  `.firebaserc`) : Authentication, Firestore, Cloud Functions
  (`australia-southeast1`), Storage.
- Code source hébergé sur GitHub :
  [margauxs1406-max/exercise_kitchen](https://github.com/margauxs1406-max/exercise_kitchen).

## Non couvert à ce jour

Seuls ces deux points du document de spécifications restent à faire :

- **Bibliothèque de points d'automassage façon GOWOD** (sections 1.5 / 2.3)
  : import de photos/vidéos par le coach, conseils sur l'hydratation des
  fascias, choix de la durée/matériel disponible côté adhérent.
- **Questionnaire et score d'hydratation** (section 2.4) : questionnaire
  sur les habitudes d'entraînement/automassage/consommation de liquide.

## Récupérer le projet sur une nouvelle machine (ex. le Mac, pour iOS)

Le projet est déjà entièrement configuré (Firebase connecté, `android/` et
`ios/` déjà générés) — sur une machine qui a déjà `git` et le SDK Flutter
installés, il suffit de :

```bash
git clone https://github.com/margauxs1406-max/exercise_kitchen.git
cd exercise_kitchen
flutter pub get
```

Puis, pour lancer sur iOS (Xcode requis, donc uniquement sur Mac) :

```bash
open ios/Runner.xcworkspace
```

Dans Xcode, avant le premier lancement : onglet Runner → **Signing &
Capabilities** → vérifier qu'une équipe de développement est sélectionnée,
puis ajouter la capacité **"Push Notifications"** (bouton "+ Capability")
pour que les notifications marchent sur iOS. Ensuite, `flutter run` (depuis
VS Code ou le terminal) fonctionne normalement.

Pour les Cloud Functions (uniquement si tu modifies
`functions/src/index.ts`) :

```bash
cd functions && npm install && cd ..
firebase deploy --only functions
```

## Créer un compte coach (bootstrap manuel)

Personne ne peut s'auto-inscrire (section 3) : chaque compte coach doit
être créé manuellement, une seule fois par personne (voir la conversation
du 26 juillet 2026 sur pourquoi un compte par personne plutôt qu'un compte
partagé) :

1. Console Firebase → Authentication → "Add user" : crée un compte pour
   cette personne (email + mot de passe de ton choix).
2. Console Firebase → Firestore → collection `users` → crée un document
   dont l'ID est l'UID généré à l'étape précédente, avec :

```json
{
  "firstName": "Prénom",
  "lastName": "Nom",
  "email": "email-du-coach@exemple.com",
  "role": "coach",
  "status": "active",
  "needsPasswordChange": false,
  "consentAccepted": true,
  "consentVersion": "1.0",
  "createdAt": "<horodatage actuel>"
}
```

Une fois ce document créé, la personne peut se connecter dans l'app et
créer elle-même tous les comptes adhérents depuis l'écran "Adhérents".

## Structure du projet

```
lib/
  main.dart                  Point d'entrée, initialisation Firebase
  app.dart                   MaterialApp, thème, providers
  theme/
    app_theme.dart           Palette provisoire, police des titres
    responsive.dart          context.wp/hp/sp — voir "Design" ci-dessus
  data/
    default_collective_schedule.dart   Créneaux collectifs récurrents
  models/                    UserModel, SlotModel, RegistrationModel,
                             ProgressPhotoModel, RekoverySessionModel,
                             ClosureModel
  services/                  AuthService, BiometricAuthService,
                             PushNotificationService + repositories
                             (planning, inscriptions, photos, utilisateurs)
  screens/auth/              Connexion, mot de passe (oublié/changement),
                             consentement RGPD
  screens/coach/             Planning, créer/gérer un adhérent, ajouter un
                             cours/évènement, photos de progression
  screens/adherent/          Planning, galerie, profil, FAQ,
                             confidentialité, notifications
  widgets/                   RoleGate, AppLockGate, WeekHeader, SlotCard,
                             feuilles d'action (créneau/fermeture/Rekovery),
                             galerie photo

functions/src/index.ts       createAdherentAccount, registerForSlot,
                             cancelRegistration, generateWeeklySlots,
                             notifications push, alertes divers
firestore.rules              Sécurité basée sur les rôles (section 3)
firestore.indexes.json       Index composites requis par les requêtes
firebase.json                Configuration Firebase CLI
storage.rules                Sécurité des photos de progression (Storage)
```

## Décisions encore ouvertes (voir section 8 des spécifications)

Ces points ne bloquent pas le développement mais restent à valider avec le
gérant avant mise en production :

- Durée de conservation des données après clôture d'un compte adhérent
  (proposition du document : 12 mois).
- Texte définitif de la politique de confidentialité et des mentions
  légales — celui affiché dans `ConsentScreen`/`PrivacyPolicyScreen` est un
  **texte provisoire**, à ne pas publier tel quel sur les stores.
- Réception de la charte graphique officielle pour remplacer la palette
  provisoire de `app_theme.dart` (seul `flashyGreen` est confirmé à ce
  jour).

Pour l'historique détaillé de chaque décision et de chaque correctif
(dates, raisons, alternatives écartées), voir le document de notes de
projet tenu au fil de l'eau (`MVP_Flutter_Scaffold_Notes.md`, disponible
dans le projet Claude "Exercise Kitchen").
