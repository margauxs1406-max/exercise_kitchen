import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import 'progress_gallery_screen.dart';
import 'weekly_planning_screen.dart';

/// Espace adhérent — section 2 des spécifications.
///
/// Bottom bar avec deux onglets : Planning (section 4.2, en-tête géré par
/// `WeeklyPlanningScreen` elle-même, commun avec le planning coach) et
/// Photos (galerie de progression, section 2.1, voir
/// `progress_gallery_screen.dart`) — remplace l'ancien espace réservé
/// "Bientôt".
class AdherentHomeScreen extends StatefulWidget {
  const AdherentHomeScreen({super.key});

  @override
  State<AdherentHomeScreen> createState() => _AdherentHomeScreenState();
}

class _AdherentHomeScreenState extends State<AdherentHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthService>().currentUser?.uid;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const WeeklyPlanningScreen(),
          // `uid` ne peut être `null` que dans le tout premier instant du
          // chargement de la session (voir `AuthService.refreshCurrentUser`)
          // — cet écran n'est de toute façon affiché qu'une fois connecté.
          uid == null
              ? const Center(child: CircularProgressIndicator())
              : ProgressGalleryScreen(adherentUid: uid),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Planning'),
          NavigationDestination(icon: Icon(Icons.photo_library), label: 'Photos'),
        ],
      ),
    );
  }
}
