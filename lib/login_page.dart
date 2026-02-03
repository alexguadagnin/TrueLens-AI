import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'main.dart'; // Per accedere ad AppTheme
import 'package:flutter_svg/flutter_svg.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;

  void _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    final user = await AuthService.instance.signInWithGoogle();
    setState(() => _isLoading = false);

    if (user != null) {
      print("Login successo: ${user.displayName}");
      // Non serve navigare manualmente, il main.dart ascolterà il cambiamento!
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Login fallito o annullato")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // LOGO / ICONA
            Container(
              // Riduciamo un po' il padding se il logo è già grande
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.accentPurple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.accentPurple, width: 2),
              ),
              // Usiamo SvgPicture.asset
              child: Image.asset(
                'assets/images/icon-no-sfondo.png',
                height: 100,
                width: 100,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 30),

            const Text(
              "TRUE LENS",
              style: TextStyle(
                fontFamily: 'RobotoMono',
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 4.0,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Fact-Checking AI Ibrido",
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),

            const SizedBox(height: 60),

            // BOTTONE GOOGLE
            _isLoading
                ? const CircularProgressIndicator(color: AppTheme.accentPurple)
                : ElevatedButton.icon(
                    onPressed: _handleGoogleSignIn,
                    icon: const Icon(Icons.login, color: Colors.black),
                    label: const Text("Accedi con Google"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black, // Testo nero
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
