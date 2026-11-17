import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../widgets/cursor_theme.dart';
import '../welcome_screen.dart';

/// Arranque de la app: se puede usar en anónimo.
/// Login solo hace falta para recargar la billetera.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (context, _) {
        final auth = AuthService.instance;
        if (!auth.isReady) {
          return const Scaffold(
            backgroundColor: CursorTheme.background,
            body: Center(
              child: CircularProgressIndicator(color: CursorTheme.primary),
            ),
          );
        }
        // Anónimo o con sesión → misma app. Sin saldo el agente no corre.
        return const WelcomeScreen();
      },
    );
  }
}
