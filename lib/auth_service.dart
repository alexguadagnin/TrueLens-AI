import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  // Singleton instance
  static final AuthService instance = AuthService._init();
  AuthService._init();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Istanziamo GoogleSignIn con i parametri di default
  // Invece di GoogleSignIn();
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  // Stream per ascoltare se l'utente è loggato o no
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Ottieni utente corrente
  User? get currentUser => _auth.currentUser;

  // LOGIN CON GOOGLE
  Future<User?> signInWithGoogle() async {
    try {
      // 1. Fa partire il flusso di login nativo (apre il popup Google)
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        print("Login Google annullato dall'utente.");
        return null;
      }

      // 2. Ottiene i dettagli di autenticazione (token)
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // 3. Crea una credenziale per Firebase usando i token
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Usa la credenziale per entrare in Firebase
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      return userCredential.user;
    } catch (e) {
      print("Errore Login Google: $e");
      return null;
    }
  }

  // LOGOUT
  Future<void> signOut() async {
    await _googleSignIn.signOut(); // Disconnette da Google
    await _auth.signOut(); // Disconnette da Firebase
  }
}
