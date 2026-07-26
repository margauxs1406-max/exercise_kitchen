import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
// Généré par `flutterfire configure` — voir README.md, étape 4.
// Ce fichier n'existe pas encore dans ce livrable : il doit être créé en
// local en connectant le projet Firebase de la salle.
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('fr_FR', null);
  runApp(const ExerciseKitchenApp());
}
