import 'dart:async';

import 'package:flutter/material.dart';
import 'screens/auth/auth_gate.dart';
import 'widgets/app_splash_screen.dart';
import 'widgets/cursor_theme.dart';
import 'services/auth_service.dart';
import 'services/permission_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lopez → Voryxel: recuperar API Key del plist del bundle anterior.
  await SettingsService.migrateLegacyMacPrefsIfNeeded();
  // NO await Auth aquí: si Firebase se cuelga, la ventana queda negra
  // (runApp nunca corre). Init en paralelo con timeout.
  unawaited(
    AuthService.instance.initialize().timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        debugPrint('⚠️ Auth init timeout — continuando sin bloquear UI');
      },
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voryxel Code',
      debugShowCheckedModeBanner: false,
      theme: CursorTheme.theme,
      home: const AppInitializer(),
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _showSplash = true;

  Future<void> _whileSplash() async {
    // Permisos en paralelo mientras corre la barra (~4–6 s).
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    await PermissionService.checkAndRequestPermissions(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return AppSplashScreen(
        whileLoading: _whileSplash,
        onFinished: () {
          if (mounted) setState(() => _showSplash = false);
        },
      );
    }

    // App usable en anónimo; login opcional (recargas).
    return const AuthGate();
  }
}
