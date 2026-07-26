import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Sous-titre de section affiché au-dessus des créneaux d'un même jour
/// dans le planning (ex. "Lundi 20 juillet").
///
/// [isFirst] réduit l'espace au-dessus du tout premier jour de la liste,
/// pour qu'il colle au bas de la zone "Semaine du XX/XX" plutôt que de
/// laisser un grand vide en haut de la zone de défilement (section 4.1/4.2).
class DayHeader extends StatelessWidget {
  final DateTime date;
  final bool isFirst;
  const DayHeader({super.key, required this.date, this.isFirst = false});

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('EEEE d MMMM', 'fr_FR').format(date);
    final capitalized = '${label[0].toUpperCase()}${label.substring(1)}';
    return Padding(
      padding: EdgeInsets.only(
        top: isFirst ? 0 : context.hp(16),
        bottom: context.hp(6),
        left: context.wp(4),
      ),
      child: Text(
        capitalized,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: context.sp(15),
          color: AppColors.black,
        ),
      ),
    );
  }
}
