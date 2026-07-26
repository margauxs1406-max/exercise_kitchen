import 'package:flutter/material.dart';

import '../models/rekovery_session_model.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Ligne compacte "thermomètre" représentant une session rekovery réservée
/// dans le planning (section 2.4bis) — volontairement plus discrète qu'un
/// [SlotCard] complet : pas de carte, pas d'inscription, juste un repère
/// visuel pour que les coachs (et l'adhérent lui-même) sachent qu'un
/// créneau rekovery est prévu ce jour-là.
///
/// [showName] affiche le nom de l'adhérent (utile côté coach, qui voit les
/// sessions de tout le monde) ; masqué côté adhérent, qui ne voit que les
/// siennes.
///
/// [color] : gris moyen par défaut (non utilisé actuellement — coach et
/// adhérent passent tous les deux `AppColors.orange`, pour que la ligne
/// Rekovery ressorte davantage dans les deux plannings) ; conservé comme
/// valeur de repli si un futur écran veut l'afficher plus discrètement.
///
/// [onTap] (section 2.4bis) : ouvre le menu "Modifier"/"Supprimer" (voir
/// `rekovery_actions_sheet.dart`) — branché uniquement côté planning
/// adhérent, sur sa propre session ; `null` par défaut, ce qui laisse la
/// ligne non cliquable (planning coach, lecture seule ici).
class RekoveryLine extends StatelessWidget {
  final RekoverySessionModel session;
  final bool showName;
  final Color color;
  final VoidCallback? onTap;

  const RekoveryLine({
    super.key,
    required this.session,
    this.showName = false,
    this.color = AppColors.mediumGrey,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.wp(8)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: context.hp(4), horizontal: context.wp(4)),
        child: Row(
          children: [
            Icon(Icons.thermostat, color: color, size: context.wp(18)),
            SizedBox(width: context.wp(8)),
            Text(
              'Rekovery — ${session.startTime}',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            if (showName) ...[
              SizedBox(width: context.wp(6)),
              Text(
                '(${session.adherentName})',
                style: TextStyle(color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
