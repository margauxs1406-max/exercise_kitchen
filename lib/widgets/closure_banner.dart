import 'package:flutter/material.dart';

import '../models/closure_model.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Bandeau de fermeture affiché en tête d'une journée du planning (coach ET
/// adhérent) — section "ajouter un évènement > fermeture".
///
/// MVP : purement informatif dans le planning, pas d'envoi d'email/
/// notification automatique pour l'instant (voir décision du 2026-07-09).
///
/// [onLongPress] : appui long ouvrant "Modifier"/"Supprimer" (voir
/// `closure_actions_sheet.dart`) — branché uniquement côté planning coach ;
/// `null` par défaut, ce qui laisse le bandeau non cliquable (planning
/// adhérent, lecture seule).
class ClosureBanner extends StatelessWidget {
  final ClosureModel closure;
  final VoidCallback? onLongPress;
  const ClosureBanner({super.key, required this.closure, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(context.wp(10)),
      child: Container(
        margin: EdgeInsets.only(bottom: context.hp(6)),
        padding: EdgeInsets.symmetric(horizontal: context.wp(14), vertical: context.hp(10)),
        decoration: BoxDecoration(
          color: AppColors.orange.withValues(alpha: 0.12),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(context.wp(10)),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_clock, color: AppColors.orange, size: context.wp(20)),
            SizedBox(width: context.wp(10)),
            Expanded(
              child: Text(
                closure.message,
                style: const TextStyle(color: AppColors.black, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
