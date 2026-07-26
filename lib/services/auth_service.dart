import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';

/// Version courante de la politique de confidentialité présentée à l'écran
/// de consentement (section 2 des spécifications). Incrémenter cette valeur
/// et republier l'écran de consentement si le texte change substantiellement
/// après relecture par le gérant.
const String kPrivacyPolicyVersion = '1.0';

/// Centralise l'authentification et le cycle de vie "compte fermé"
/// (section 3) : connexion, changement du mot de passe temporaire imposé à
/// la première connexion, et enregistrement du consentement RGPD.
class AuthService extends ChangeNotifier {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  User? _firebaseUser;
  UserModel? _currentUser;
  bool _loading = true;

  User? get firebaseUser => _firebaseUser;
  UserModel? get currentUser => _currentUser;
  bool get isLoading => _loading;
  bool get isSignedIn => _firebaseUser != null;

  // Distingue, pour `AppLockGate`, une session restaurée automatiquement par
  // Firebase au lancement (persistance native, aucun appel à `signIn` cette
  // fois-ci) d'une reconnexion volontaire faite PENDANT ce lancement — sert
  // à savoir s'il faut forcer une reconnexion par mot de passe pour les
  // personnes n'utilisant pas le déverrouillage biométrique. Volontairement
  // un simple champ en mémoire (jamais persisté) : il repart à `false`
  // uniquement quand le processus redémarre, comme `AppLockGate`.
  bool _hasExplicitlySignedIn = false;
  bool get hasExplicitlySignedIn => _hasExplicitlySignedIn;

  Future<void> _onAuthStateChanged(User? user) async {
    _firebaseUser = user;
    if (user == null) {
      _currentUser = null;
      _loading = false;
      notifyListeners();
      return;
    }
    await refreshCurrentUser();
  }

  /// Recharge le document `users/{uid}` — à appeler après un changement de
  /// mot de passe ou de consentement pour rafraîchir l'état local.
  Future<void> refreshCurrentUser() async {
    final uid = _firebaseUser?.uid;
    if (uid == null) return;
    _loading = true;
    notifyListeners();
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      _currentUser = UserModel.fromFirestore(doc);
      // Compte clôturé par un coach (section 3) : on déconnecte immédiatement.
      if (!_currentUser!.isActive) {
        await signOut();
        return;
      }
    } else {
      _currentUser = null;
    }
    _loading = false;
    notifyListeners();
  }

  Future<UserCredential> signIn({required String email, required String password}) {
    // Posé AVANT l'appel (pas après) pour éviter toute course avec l'écoute
    // de `authStateChanges()` ci-dessus, qui peut se déclencher dès que
    // Firebase traite la connexion.
    _hasExplicitlySignedIn = true;
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  /// Première connexion obligatoire : l'adhérent (ou le coach) doit
  /// remplacer le mot de passe temporaire par un mot de passe personnel.
  Future<void> completePasswordChange(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.updatePassword(newPassword);
    await _firestore.collection('users').doc(user.uid).update({
      'needsPasswordChange': false,
    });
    await refreshCurrentUser();
  }

  /// Enregistre l'acceptation de la politique de confidentialité — la case
  /// à cocher doit être non pré-cochée côté UI (section 2). On conserve la
  /// date, l'heure et la version acceptée comme registre de preuve.
  Future<void> acceptConsent() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).update({
      'consentAccepted': true,
      'consentAcceptedAt': Timestamp.now(),
      'consentVersion': kPrivacyPolicyVersion,
    });
    await refreshCurrentUser();
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  /// Section (profil adhérent) : modifie le mot de passe une fois déjà
  /// connecté depuis un moment — contrairement à [completePasswordChange]
  /// (première connexion obligatoire, juste après une authentification
  /// fraîche), Firebase peut exiger ici une reconnexion récente pour une
  /// opération aussi sensible. On ré-authentifie donc systématiquement avec
  /// le mot de passe actuel avant de poser le nouveau, plutôt que d'attendre
  /// l'erreur `requires-recent-login`.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final email = user.email;
    if (email == null) {
      throw Exception("Ce compte n'a pas d'email associé.");
    }
    final credential = EmailAuthProvider.credential(email: email, password: currentPassword);
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }
}