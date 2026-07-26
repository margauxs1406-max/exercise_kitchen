import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// Champ de saisie avec son libellé affiché juste au-dessus, en texte fixe
/// (et non en label flottant superposé au bord du champ).
///
/// Utilisé sur les écrans à fond noir (connexion, mot de passe) : avec un
/// label flottant classique, le texte remonte au-dessus du champ et se
/// retrouve à cheval entre le fond blanc du champ et le fond noir de
/// l'écran — d'où ce libellé fixe, toujours au-dessus, jamais superposé.
class LabeledTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const LabeledTextField({
    super.key,
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.w600,
            fontSize: context.sp(14),
          ),
        ),
        SizedBox(height: context.hp(6)),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          decoration: InputDecoration(suffixIcon: suffixIcon),
          validator: validator,
        ),
      ],
    );
  }
}
