import 'package:local_auth/local_auth.dart';

/// Authentification biométrique de déverrouillage de l'app (switch du profil
/// adhérent, voir `adherent_profile_screen.dart`) — à ne pas confondre avec
/// la connexion Firebase (`AuthService`), qui elle reste ouverte en
/// arrière-plan comme d'habitude. Ici il s'agit uniquement d'un verrou
/// d'accès à l'app, déclenché par `AppLockGate` une seule fois par
/// lancement "à froid" du processus (jamais à un simple retour au premier
/// plan — voir le commentaire de `AppLockGate`).
class BiometricAuthService {
  final LocalAuthentication _localAuth = LocalAuthentication();

  /// À vérifier avant d'autoriser l'activation du switch : l'appareil doit
  /// à la fois supporter l'authentification locale et avoir une empreinte /
  /// un visage effectivement enregistré, sinon le switch resterait activé
  /// sans jamais pouvoir être satisfait (verrouillage définitif de l'app).
  Future<bool> get isSupported async {
    try {
      final deviceSupported = await _localAuth.isDeviceSupported();
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      return deviceSupported && canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Déclenche le prompt natif (empreinte / visage — ou code de l'appareil
  /// en repli si la biométrie échoue, `biometricOnly: false`, puisque cette
  /// app ne gère aucune donnée confidentielle et qu'on préfère éviter un
  /// blocage total en cas de souci de capteur). `persistAcrossBackgrounding`
  /// conserve la demande active si l'app est brièvement mise en
  /// arrière-plan pendant le prompt (ex. notification système), au lieu de
  /// l'annuler.
  ///
  /// Note : depuis `local_auth` 3.x, `authenticate()` prend ces réglages en
  /// paramètres nommés directement (il n'y a plus de classe
  /// `AuthenticationOptions`/paramètre `options:` comme en 2.x), et les
  /// échecs remontent en `LocalAuthException` plutôt qu'en
  /// `PlatformException` — peu importe ici puisqu'on les avale tous et
  /// retourne simplement `false`.
  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Déverrouille Exercise Kitchen',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}