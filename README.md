# Exercise Kitchen — MVP

Application mobile coach / adhérent pour la méthode Functional Pattern.
Ce dossier contient le **MVP** défini section 6 des spécifications
techniques : authentification, gestion des rôles (coach / adhérent),
planning de la semaine (cours collectifs récurrents + cours duo ponctuels)
et inscriptions, avec liste d'attente (2.2bis).

Sont **volontairement absents** de ce MVP (priorités 2 à 4 du document) :
les notifications push, la galerie de photos de progression, le contenu
d'automassage et le questionnaire d'hydratation. Les points d'accroche pour
les brancher plus tard sont commentés dans le code (`// TODO priorité 2`
dans `functions/src/index.ts`, `SlotModel.hasOnlyOneRegistered`, etc.).

## ⚠️ Pourquoi ce projet n'est pas déjà "prêt à lancer"

Ce projet a été préparé dans un environnement cloud dont la politique
réseau bloque les domaines nécessaires aux outils Flutter et Firebase
(`storage.googleapis.com`, `registry.npmjs.org`, `pypi.org`, etc.). Il a
donc été **impossible d'exécuter `flutter create`, `flutter pub get`,
`npm install` ou `tsc` pour valider la compilation** depuis cette session.

Tout le code (Dart, TypeScript, règles Firestore) a été écrit à la main en
suivant scrupuleusement les conventions Flutter/Firebase, mais **il doit
être finalisé et testé sur ta machine**, où tu as un accès réseau complet.
Les étapes ci-dessous prennent 15–20 minutes.

## Ce que tu dois avoir installé sur ta machine

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`flutter doctor` sans erreur bloquante)
- [Node.js](https://nodejs.org/) 20+ (pour les Cloud Functions)
- [VS Code](https://code.visualstudio.com/) + extension "Flutter"
- Un compte Google (pour créer le projet Firebase)

## Étapes pour finaliser le projet

### 1. Extraire l'archive

Dézippe `exercise_kitchen.zip` dans le dossier de ton choix, puis ouvre-le
dans VS Code.

### 2. Générer les dossiers de plateforme (Android / iOS)

Ce livrable contient le code Dart (`lib/`), `pubspec.yaml`, les règles
Firestore et les Cloud Functions — mais pas les dossiers `android/` et
`ios/` générés par `flutter create` (ils contiennent des milliers de
fichiers de boilerplate spécifiques à ta machine/SDK). Génère-les avec :

```bash
cd exercise_kitchen
flutter create --platforms=android,ios --org com.exercisekitchen .
```

Rassure-toi : lancée dans un dossier qui a déjà un `pubspec.yaml`, cette
commande **n'écrase ni `lib/`, ni tes dépendances** — elle ajoute
uniquement les dossiers de plateforme manquants.

### 3. Installer les dépendances Flutter

```bash
flutter pub get
```

### 4. Créer le projet Firebase et connecter l'app

1. Va sur [console.firebase.google.com](https://console.firebase.google.com), crée un projet (ex. "Exercise Kitchen").
2. Active **Authentication** → méthode "Email/Mot de passe".
3. Active **Firestore Database** (mode production).
4. Installe les CLI nécessaires puis génère `lib/firebase_options.dart` (qui remplace le fichier placeholder livré ici) :

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
flutterfire configure
```

Sélectionne ton projet Firebase et les plateformes Android/iOS quand c'est demandé.

### 5. Configurer l'envoi d'email du mot de passe temporaire

La Cloud Function `createAdherentAccount` écrit dans une collection
Firestore `mail`, consommée par l'extension officielle **"Trigger Email
from Firestore"** :

1. Dans la console Firebase → Extensions → installer *Trigger Email from Firestore*.
2. Renseigne un fournisseur SMTP (ex. un compte Gmail dédié, SendGrid, etc.) pendant l'installation.
3. Laisse le nom de collection par défaut `mail` (déjà celui utilisé dans le code).

### 6. Installer les dépendances des Cloud Functions et déployer

```bash
cd functions
npm install
cd ..
firebase use --add        # sélectionne le projet Firebase créé à l'étape 4
firebase deploy --only firestore:rules,firestore:indexes,functions
```

### 7. Créer les deux premiers comptes coach (bootstrap)

Personne ne peut s'auto-inscrire (section 3) : `createAdherentAccount` doit
être appelée par un coach déjà authentifié. Il faut donc créer les deux
premiers comptes coach **manuellement**, une seule fois :

1. Console Firebase → Authentication → "Add user" : crée un compte pour chaque coach (email + mot de passe de ton choix).
2. Console Firebase → Firestore → collection `users` → crée un document dont l'ID est l'UID généré à l'étape précédente, avec :

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
  "createdAt": <horodatage actuel>
}
```

Une fois ces deux documents créés, les coachs peuvent se connecter dans
l'app et créer eux-mêmes tous les comptes adhérents depuis l'écran
"Adhérents".

### 8. Lancer l'application

```bash
flutter run
```

## Structure du projet

```
lib/
  main.dart                  Point d'entrée, initialisation Firebase
  app.dart                   MaterialApp, thème, providers
  theme/app_theme.dart       Palette provisoire (section 7)
  models/                    UserModel, CourseModel, SlotModel, RegistrationModel
  services/                  AuthService + repositories (Firestore / Cloud Functions)
  screens/auth/              Connexion, changement de mot de passe, consentement RGPD
  screens/coach/              Créer un adhérent, gérer le planning
  screens/adherent/           Planning de la semaine, inscription / liste d'attente
  widgets/                    RoleGate (routage selon rôle/état de compte), SlotCard

functions/src/index.ts       createAdherentAccount, registerForSlot,
                             cancelRegistration, generateWeeklySlots
firestore.rules              Sécurité basée sur les rôles (section 3)
firestore.indexes.json       Index composites requis par les requêtes ci-dessus
firebase.json                Configuration Firebase CLI (Firestore + Functions)
```

## Décisions encore ouvertes (voir section 8 des spécifications)

Ces points ne bloquent pas le développement du MVP mais restent à valider
avec le gérant avant mise en production :

- Durée de conservation des données après clôture d'un compte adhérent
  (proposition du document : 12 mois).
- Texte définitif de la politique de confidentialité et des mentions
  légales — celui affiché dans `ConsentScreen` est un **texte provisoire**,
  à ne pas publier tel quel sur les stores.
- Réception de la charte graphique officielle pour remplacer la palette
  provisoire de `app_theme.dart`.

## Non couvert par ce MVP (priorités 2 à 4)

- Notifications push (créneau vide/1 inscrit, place libérée en liste d'attente) — section 4.
- Galerie de photos de progression (import coach, consultation adhérent) — sections 1.2 / 2.1.
- Bibliothèque d'automassage façon GOWOD — sections 1.5 / 2.3.
- Questionnaire et score d'hydratation — section 2.4.
- Périodes de vacances et cycle de 6 semaines (basique/intermédiaire/dynamique) — section 1.4.
