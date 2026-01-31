import 'package:flutter/material.dart';
import 'cursor_theme.dart';
import '../services/debug_console_service.dart';

/// Diálogo modal de confirmación para errores
/// Reemplaza los SnackBar con una ventana modal más profesional
class ErrorConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final bool showViewErrorsButton;
  final VoidCallback? onViewErrors;

  const ErrorConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.showViewErrorsButton = false,
    this.onViewErrors,
  });

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
    bool showViewErrorsButton = false,
    VoidCallback? onViewErrors,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ErrorConfirmationDialog(
        title: title,
        message: message,
        showViewErrorsButton: showViewErrorsButton,
        onViewErrors: onViewErrors,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: CursorTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: CursorTheme.border, width: 1),
      ),
      title: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: TextStyle(
          color: CursorTheme.textSecondary,
          fontSize: 14,
          height: 1.5,
        ),
      ),
      actions: [
        if (showViewErrorsButton)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (onViewErrors != null) {
                onViewErrors!();
              } else {
                // Abrir Debug Console por defecto
                DebugConsoleService().openPanel();
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: CursorTheme.primary,
            ),
            child: const Text('Ver errores'),
          ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: CursorTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
