import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Contournement du bug connu du SDK Firebase Auth Android (27 août 2026,
/// voir `cold_start_relogin_screen.dart` pour le détail du diagnostic) :
/// stocke — UNIQUEMENT après une activation biométrique réussie, jamais à
/// l'aveugle — l'email et le mot de passe du compte, chiffrés matériellement
/// (Android Keystore / iOS Keychain via `flutter_secure_storage`, jamais en
/// clair et jamais dans Firestore ni ailleurs). Sert ensuite à reconnecter
/// silencieusement la personne quand Firebase perd sa session au lancement
/// "à froid", à condition de réussir d'abord un prompt biométrique — voir
/// `login_screen.dart` (bouton "Utiliser la biométrie") et
/// `cold_start_relogin_screen.dart` (tentative automatique au démarrage).
///
/// Toujours effacé :
/// - à la déconnexion manuelle (`AuthService.signOut`) ;
/// - à la désactivation du switch biométrique côté profil adhérent
///   (`adherent_profile_screen.dart`) ;
/// - si les identifiants stockés se révèlent invalides au moment de s'en
///   servir (mot de passe changé depuis un autre appareil...).
class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // `encryptedSharedPreferences` : implémentation recommandée
              // par le plugin côté Android, chiffrée avec une clé gérée par
              // l'Android Keystore (jamais extractible du matériel).
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _kEmailKey = 'ek_stored_email';
  static const _kPasswordKey = 'ek_stored_password';

  Future<void> save({required String email, required String password}) async {
    await _storage.write(key: _kEmailKey, value: email);
    await _storage.write(key: _kPasswordKey, value: password);
  }

  /// `null` si aucun identifiant n'est stocké (jamais activé, ou effacé
  /// depuis — voir la liste des cas d'effacement dans la doc de classe).
  Future<StoredCredentials?> read() async {
    final email = await _storage.read(key: _kEmailKey);
    final password = await _storage.read(key: _kPasswordKey);
    if (email == null || password == null) return null;
    return StoredCredentials(email: email, password: password);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kEmailKey);
    await _storage.delete(key: _kPasswordKey);
  }
}

/// Simple porteur de données (email + mot de passe stockés) — utilisé plutôt
/// qu'un record Dart pour rester lisible aux points d'appel (`stored.email`,
/// `stored.password`).
class StoredCredentials {
  final String email;
  final String password;
  const StoredCredentials({required this.email, required this.password});
}
