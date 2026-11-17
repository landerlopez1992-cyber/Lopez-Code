import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../widgets/cursor_theme.dart';
import '../../widgets/voryxel_brand_logo.dart';

/// Login / crear cuenta (Firebase o local hasta configurar Firebase).
/// [popOnSuccess]: al entrar, vuelve a la pantalla anterior (billetera/ajustes).
class LoginScreen extends StatefulWidget {
  final bool popOnSuccess;
  final String? successMessage;

  const LoginScreen({
    super.key,
    this.popOnSuccess = true,
    this.successMessage,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  static const _minLoading = Duration(milliseconds: 1200);

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final statusLabel =
        _registerMode ? 'Creando tu cuenta…' : 'Iniciando sesión…';
    // Modal bloqueante: da sensación de login aunque Auth local sea instantáneo.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: CursorTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: CursorTheme.border),
            ),
            content: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: CursorTheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusLabel,
                        style: const TextStyle(
                          color: CursorTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _registerMode
                            ? 'Preparando tu billetera'
                            : 'Verificando credenciales',
                        style: const TextStyle(
                          color: CursorTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    final started = DateTime.now();
    Object? failure;
    try {
      if (_registerMode) {
        if (_password.text != _confirm.text) {
          throw AuthException('Las contraseñas no coinciden');
        }
        await AuthService.instance.register(
          email: _email.text,
          password: _password.text,
        );
      } else {
        await AuthService.instance.signIn(
          email: _email.text,
          password: _password.text,
        );
      }
    } catch (e) {
      failure = e;
    }

    final elapsed = DateTime.now().difference(started);
    if (elapsed < _minLoading) {
      await Future<void>.delayed(_minLoading - elapsed);
    }

    if (!mounted) return;
    // Cierra el modal de carga.
    Navigator.of(context, rootNavigator: true).pop();

    if (failure != null) {
      final msg = failure is AuthException
          ? failure.message
          : failure.toString().replaceFirst('Exception: ', '');
      setState(() {
        _busy = false;
        _error = msg;
      });
      return;
    }

    setState(() => _busy = false);
    if (widget.popOnSuccess && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CursorTheme.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: VoryxelBrandLogo(
                    iconSize: 64,
                    fontSize: 22,
                    subtitle: 'Inicia sesión para recargar créditos',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Puedes usar la app sin cuenta. Para agregar saldo '
                  'a la billetera necesitas iniciar sesión. Sin saldo '
                  'el agente no funciona.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  style: const TextStyle(color: CursorTheme.textPrimary),
                  decoration: _fieldDecoration('Email'),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: [
                    _registerMode
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  style: const TextStyle(color: CursorTheme.textPrimary),
                  decoration: _fieldDecoration('Contraseña').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                        color: CursorTheme.textSecondary,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_registerMode) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscure,
                    style: const TextStyle(color: CursorTheme.textPrimary),
                    decoration: _fieldDecoration('Confirmar contraseña'),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: CursorTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_registerMode ? 'Crear cuenta' : 'Iniciar sesión'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _registerMode = !_registerMode;
                            _error = null;
                          }),
                  child: Text(
                    _registerMode
                        ? '¿Ya tienes cuenta? Inicia sesión'
                        : 'Crear cuenta nueva',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: CursorTheme.textSecondary),
      filled: true,
      fillColor: CursorTheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: CursorTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: CursorTheme.primary),
      ),
    );
  }
}
