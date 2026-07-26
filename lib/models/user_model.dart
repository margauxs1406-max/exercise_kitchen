import 'package:cloud_firestore/cloud_firestore.dart';

/// Rôle d'un utilisateur — section 3 des spécifications techniques :
/// seul un coach peut créer un compte adhérent ; les deux coachs ont les
/// mêmes droits (pas de hiérarchie entre eux).
enum UserRole { coach, adherent }

enum AccountStatus { active, closed }

UserRole userRoleFromString(String value) =>
    value == 'coach' ? UserRole.coach : UserRole.adherent;

String userRoleToString(UserRole role) => role == UserRole.coach ? 'coach' : 'adherent';

AccountStatus accountStatusFromString(String value) =>
    value == 'closed' ? AccountStatus.closed : AccountStatus.active;

/// Modèle correspondant à la collection Firestore `users`.
///
/// Champs clés côté RGPD (section 2 des spécifications) :
/// - [needsPasswordChange] force le changement du mot de passe temporaire
///   à la toute première connexion.
/// - [consentAccepted] / [consentAcceptedAt] / [consentVersion] constituent
///   le registre de preuve de consentement qui doit être conservé.
/// Formules souscrites par un adhérent — contrôlent à la fois ce qu'il peut
/// voir/faire côté planning (section 4.2) et ce qu'un coach peut cocher
/// depuis sa fiche (section 5) : 'collectif', 'duo', 'individuel', 'rekovery'.
const List<String> kAllFormulas = ['collectif', 'duo', 'individuel', 'rekovery'];

class UserModel {
  final String uid;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final UserRole role;
  final AccountStatus status;
  final bool needsPasswordChange;
  final bool consentAccepted;
  final DateTime? consentAcceptedAt;
  final String? consentVersion;
  final Set<String> formulas;
  final DateTime createdAt;
  // Section (profil adhérent) : switch visuel pour l'instant (ne bloque pas
  // encore réellement l'accès à l'app — voir `adherent_profile_screen.dart`).
  final bool biometricUnlockEnabled;
  // Section (profil adhérent) : préférences de notifications par type de
  // clé (voir `kNotificationTypes` dans `notification_settings_screen.dart`)
  // — absent ou `true` = activée, `false` = désactivée explicitement. Lu
  // aussi côté Cloud Functions (`functions/src/index.ts`) pour ne pas
  // envoyer les notifications désactivées.
  final Map<String, bool> notificationPrefs;

  const UserModel({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.status,
    required this.needsPasswordChange,
    required this.consentAccepted,
    required this.createdAt,
    this.phone,
    this.consentAcceptedAt,
    this.consentVersion,
    this.formulas = const {},
    this.biometricUnlockEnabled = false,
    this.notificationPrefs = const {},
  });

  String get fullName => '$firstName $lastName';

  /// "Prénom L" (ex. "Margaux S") — format court demandé par Margaux
  /// (22 juillet 2026) pour l'affichage du nom d'un adhérent dans les
  /// notifications, les créneaux de planning (titre d'un cours individuel,
  /// nom affiché sur une ligne Rekovery), la pop-up "inscrits/liste
  /// d'attente" et le titre de la page photos côté coach. Volontairement
  /// PAS utilisé pour la fiche adhérent (son propre nom complet reste
  /// affiché en entier) ni pour la liste complète des adhérents côté coach
  /// (`create_adherent_screen.dart`), où le nom complet reste plus utile
  /// pour identifier sans ambiguïté deux adhérents partageant un prénom et
  /// la même initiale de nom.
  String get shortName => lastName.isEmpty ? firstName : '$firstName ${lastName[0]}';

  bool get isCoach => role == UserRole.coach;
  bool get isActive => status == AccountStatus.active;

  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return UserModel(
      uid: doc.id,
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String?,
      role: userRoleFromString(data['role'] as String? ?? 'adherent'),
      status: accountStatusFromString(data['status'] as String? ?? 'active'),
      needsPasswordChange: data['needsPasswordChange'] as bool? ?? false,
      consentAccepted: data['consentAccepted'] as bool? ?? false,
      consentAcceptedAt: (data['consentAcceptedAt'] as Timestamp?)?.toDate(),
      consentVersion: data['consentVersion'] as String?,
      formulas: {
        ...((data['formulas'] as List<dynamic>?)?.map((e) => e as String) ?? const <String>[]),
      },
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      biometricUnlockEnabled: data['biometricUnlockEnabled'] as bool? ?? false,
      notificationPrefs: {
        ...((data['notificationPrefs'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as bool)) ??
            const <String, bool>{}),
      },
    );
  }

  Map<String, dynamic> toFirestore() => {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'role': userRoleToString(role),
        'status': status == AccountStatus.active ? 'active' : 'closed',
        'needsPasswordChange': needsPasswordChange,
        'consentAccepted': consentAccepted,
        'consentAcceptedAt':
            consentAcceptedAt != null ? Timestamp.fromDate(consentAcceptedAt!) : null,
        'consentVersion': consentVersion,
        'formulas': formulas.toList(),
        'createdAt': Timestamp.fromDate(createdAt),
        'biometricUnlockEnabled': biometricUnlockEnabled,
        'notificationPrefs': notificationPrefs,
      };
}