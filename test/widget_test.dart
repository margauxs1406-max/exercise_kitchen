// Test par défaut généré par `flutter create` (jamais adapté à ce projet) —
// il référençait une classe `MyApp` qui n'existe pas dans ce projet (la
// classe racine s'appelle `ExerciseKitchenApp`, voir `lib/app.dart`), d'où
// l'erreur `creation_with_non_type` remontée par `flutter analyze` (18 août
// 2026, signalé par Margaux).
//
// Remplacé par un test minimal plutôt que corrigé tel quel : le test
// d'origine (compteur "+1") simulait l'app de démo Flutter, pas
// `ExerciseKitchenApp` (Firebase, providers, repositories Firestore...).
// Construire un vrai test de widget pour `ExerciseKitchenApp` nécessiterait
// de mocker Firebase et tous les repositories (`PlanningRepository`,
// `RegistrationRepository`, etc.) — hors périmètre de ce MVP pour l'instant
// (voir `MVP_Flutter_Scaffold_Notes.md`, section "Hors périmètre").
//
// Ce test minimal garantit seulement que `flutter analyze`/`flutter test`
// ne remontent plus d'erreur de compilation à cause de ce fichier.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder — aucun vrai test de widget pour le moment', () {
    expect(1 + 1, 2);
  });
}
