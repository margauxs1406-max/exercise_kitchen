import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/user_repository.dart';
import '../../theme/app_theme.dart';
import '../../theme/responsive.dart';
import 'adherent_detail_screen.dart';
import 'create_adherent_form_screen.dart';

/// Section 1.1 : liste des adhérents (triée par ordre alphabétique — voir
/// `UserRepository.watchAdherents`, déjà `orderBy('lastName')`), avec une
/// recherche textuelle en haut de l'écran pour retrouver rapidement un
/// compte, et un simple bouton "Nouvel adhérent" qui ouvre une page de
/// formulaire à part entière ([CreateAdherentFormScreen]).
///
/// Le bouton est fixé dans un bandeau gris juste au-dessus de la barre de
/// navigation basse (donc en bas de l'écran) : il ne défile pas avec la
/// liste des adhérents au-dessus, qui occupe seule la zone de scroll.
class CreateAdherentScreen extends StatefulWidget {
  const CreateAdherentScreen({super.key});

  @override
  State<CreateAdherentScreen> createState() => _CreateAdherentScreenState();
}

class _CreateAdherentScreenState extends State<CreateAdherentScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserRepository>();
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              context.wp(16), context.hp(16), context.wp(16), context.hp(8)),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Rechercher un adhérent...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(context.wp(16), 0, context.wp(16), context.hp(16)),
            child: _AdherentList(repo: repo, query: _query),
          ),
        ),
        Container(
          width: double.infinity,
          color: AppColors.lightGrey,
          padding: EdgeInsets.symmetric(horizontal: context.wp(16), vertical: context.hp(16)),
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateAdherentFormScreen()),
            ),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Nouvel adhérent'),
          ),
        ),
      ],
    );
  }
}

class _AdherentList extends StatelessWidget {
  final UserRepository repo;
  final String query;
  const _AdherentList({required this.repo, required this.query});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserModel>>(
      stream: repo.watchAdherents(),
      builder: (context, snapshot) {
        // Sans ce test, une erreur de requête (ex. index Firestore encore en
        // cours de construction juste après un déploiement) laissait la roue
        // de chargement tourner indéfiniment, sans aucun message — le flux
        // ne renvoyait jamais de données, mais `hasData` ne devenait jamais
        // `true` non plus.
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: context.wp(24), vertical: context.hp(24)),
              child: Text(
                "Impossible de charger les adhérents pour l'instant "
                '(l\'index Firestore est peut-être encore en cours de '
                'construction juste après un déploiement — réessaie dans '
                "quelques minutes).\n\nDétail : ${snapshot.error}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.mediumGrey),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        // Le tri alphabétique vient directement de la requête Firestore
        // (`orderBy('firstName')`) — le filtre ci-dessous ne fait que
        // retirer des éléments, il ne change jamais leur ordre.
        final adherents = query.isEmpty
            ? all
            : all
                .where((a) =>
                    a.fullName.toLowerCase().contains(query) ||
                    a.email.toLowerCase().contains(query))
                .toList();

        if (adherents.isEmpty) {
          return Center(
            child: Text(
              query.isEmpty
                  ? 'Aucun adhérent pour le moment.'
                  : 'Aucun adhérent ne correspond à "$query".',
            ),
          );
        }
        return ListView.builder(
          itemCount: adherents.length,
          itemBuilder: (context, index) {
            final a = adherents[index];
            return Card(
              child: ListTile(
                title: Text(a.fullName),
                subtitle: Text(a.email),
                // Section 5.1 : "Actif" en simple texte + coche vert flashy,
                // "Clôturé" sur le même modèle (texte + icône, sans fond ni
                // contour) mais en gris foncé, avec une croix à la place de
                // la coche.
                trailing: a.isActive
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, color: AppColors.flashyGreen, size: context.wp(18)),
                          SizedBox(width: context.wp(4)),
                          const Text(
                            'Actif',
                            style: TextStyle(
                              color: AppColors.flashyGreen,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cancel, color: AppColors.darkGrey, size: context.wp(18)),
                          SizedBox(width: context.wp(4)),
                          const Text(
                            'Clôturé',
                            style: TextStyle(
                              color: AppColors.darkGrey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                // La fiche complète (téléphone, formules modifiables,
                // clôture/réactivation) est sur un écran dédié.
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => AdherentDetailScreen(uid: a.uid)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
