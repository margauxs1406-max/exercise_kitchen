import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Bandeau de navigation de semaine ("< Semaine du XX/XX >"), en gris clair,
/// affiché entre l'en-tête ([WeekHeader]) et la zone de défilement du
/// planning (sections 4.1/4.2).
class WeekNavBar extends StatelessWidget {
  final DateTime weekStart;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;

  const WeekNavBar({
    super.key,
    required this.weekStart,
    required this.onPreviousWeek,
    required this.onNextWeek,
  });

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.lightGrey,
      child: Row(
        children: [
          IconButton(
            onPressed: onPreviousWeek,
            icon: const Icon(Icons.chevron_left, color: AppColors.black),
          ),
          Expanded(
            child: Text(
              // sections 4.1/4.2 : toujours 2 chiffres pour le jour ET le
              // mois ("06/07", jamais "06/7").
              'Semaine du ${_pad2(weekStart.day)}/${_pad2(weekStart.month)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.black, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: onNextWeek,
            icon: const Icon(Icons.chevron_right, color: AppColors.black),
          ),
        ],
      ),
    );
  }
}
