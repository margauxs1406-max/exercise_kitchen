import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'services/auth_service.dart';
import 'services/photo_repository.dart';
import 'services/planning_repository.dart';
import 'services/push_notification_service.dart';
import 'services/registration_repository.dart';
import 'services/rekovery_repository.dart';
import 'services/user_repository.dart';
import 'theme/app_theme.dart';
import 'widgets/role_gate.dart';

class ExerciseKitchenApp extends StatelessWidget {
  const ExerciseKitchenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => UserRepository()),
        Provider(create: (_) => PlanningRepository()),
        Provider(create: (_) => RegistrationRepository()),
        Provider(create: (_) => RekoveryRepository()),
        Provider(create: (_) => PhotoRepository()),
        Provider(create: (_) => PushNotificationService()),
      ],
      // `Builder` : nécessaire pour obtenir un `context` sous le
      // `MultiProvider` ci-dessus (donc capable de faire `context.read` sur
      // `PushNotificationService`) avant de construire le `MaterialApp`.
      child: Builder(
        builder: (context) {
          final push = context.read<PushNotificationService>();
          push.attachForegroundListener();
          return MaterialApp(
            title: 'Exercise Kitchen',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(context),
            locale: const Locale('fr', 'FR'),
            supportedLocales: const [Locale('fr', 'FR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // Permet à `PushNotificationService` d'afficher un bandeau
            // (notification reçue au premier plan) sans avoir besoin d'un
            // `BuildContext` d'écran précis.
            scaffoldMessengerKey: push.scaffoldMessengerKey,
            home: const RoleGate(),
          );
        },
      ),
    );
  }
}
