import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';
import 'widgets/cursor_theme.dart';
import 'services/permission_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lopez Code',
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
  bool _isCheckingPermissions = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    // Esperar un momento para que la UI se cargue
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!mounted) return;
    
    // Verificar y solicitar permisos
    await PermissionService.checkAndRequestPermissions(context);
    
    if (mounted) {
      setState(() {
        _isCheckingPermissions = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mientras se verifican permisos, mostrar pantalla de carga
    if (_isCheckingPermissions) {
      return Scaffold(
        backgroundColor: CursorTheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF007ACC)),
              ),
              const SizedBox(height: 24),
              const Text(
                'Verificando permisos...',
                style: TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // SIEMPRE mostrar WelcomeScreen al abrir la app
    // (incluso si no hay permisos, para que el usuario pueda intentar de nuevo)
    return const WelcomeScreen();
  }
}
