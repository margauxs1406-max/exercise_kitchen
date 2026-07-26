import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/week_header.dart';
import 'create_adherent_screen.dart';
import 'manage_planning_screen.dart';

/// Espace coach — section 1 des spécifications. Les deux coachs ont les
/// mêmes droits (pas de hiérarchie), donc un seul écran sert les deux.
///
/// Les deux onglets partagent maintenant le même en-tête ([WeekHeader] :
/// logo à gauche, déconnexion à droite) — seul le contenu central change
/// ("Adhérent" ici, le type de semaine côté Planning, géré directement par
/// `manage_planning_screen.dart`).
class CoachHomeScreen extends StatefulWidget {
  const CoachHomeScreen({super.key});

  @override
  State<CoachHomeScreen> createState() => _CoachHomeScreenState();
}

class _CoachHomeScreenState extends State<CoachHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: _index == 0
          ? null
          : WeekHeader(
              onLogout: () => auth.signOut(),
              weekTypeContent: Text(
                'Adhérent'.toUpperCase(),
                style: AppTheme.headerTitleStyle,
              ),
            ),
      body: IndexedStack(
        index: _index,
        children: const [
          ManagePlanningScreen(),
          CreateAdherentScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Planning'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Adhérents'),
        ],
      ),
    );
  }
}
