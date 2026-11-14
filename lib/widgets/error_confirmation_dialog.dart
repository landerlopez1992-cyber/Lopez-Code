import 'package:flutter/material.dart';
import 'cursor_theme.dart';
import '../services/debug_console_service.dart';

/// Diálogo modal de confirmación para errores.
/// Preferir [showFixWithAIButton] para devolver el diagnóstico al chat.
/// [showViewCodeButton] abre el editor Code para trabajar sin IA.
class ErrorConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final bool showViewErrorsButton;
  final VoidCallback? onViewErrors;
  final bool showFixWithAIButton;
  final VoidCallback? onFixWithAI;
  final bool showViewCodeButton;
  final VoidCallback? onViewCode;
  final bool showRunOnWebButton;
  final VoidCallback? onRunOnWeb;

  const ErrorConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.showViewErrorsButton = false,
    this.onViewErrors,
    this.showFixWithAIButton = false,
    this.onFixWithAI,
    this.showViewCodeButton = false,
    this.onViewCode,
    this.showRunOnWebButton = false,
    this.onRunOnWeb,
  });

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
    bool showViewErrorsButton = false,
    VoidCallback? onViewErrors,
    bool showFixWithAIButton = false,
    VoidCallback? onFixWithAI,
    bool showViewCodeButton = false,
    VoidCallback? onViewCode,
    bool showRunOnWebButton = false,
    VoidCallback? onRunOnWeb,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => ErrorConfirmationDialog(
        title: title,
        message: message,
        showViewErrorsButton: showViewErrorsButton,
        onViewErrors: onViewErrors,
        showFixWithAIButton: showFixWithAIButton,
        onFixWithAI: onFixWithAI,
        showViewCodeButton: showViewCodeButton,
        onViewCode: onViewCode,
        showRunOnWebButton: showRunOnWebButton,
        onRunOnWeb: onRunOnWeb,
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
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.close,
              size: 18,
              color: CursorTheme.textSecondary,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280, maxWidth: 480),
        child: SingleChildScrollView(
          child: Text(
            message,
            style: const TextStyle(
              color: CursorTheme.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ),
      actions: [
        if (showRunOnWebButton)
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onRunOnWeb?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2EA043),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Ejecutar en Web Preview'),
          ),
        if (showFixWithAIButton)
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onFixWithAI?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: CursorTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('Arreglar con IA'),
          ),
        if (showViewCodeButton)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onViewCode?.call();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: CursorTheme.textPrimary,
              side: const BorderSide(color: CursorTheme.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            icon: const Icon(Icons.code, size: 16),
            label: const Text('Ver código'),
          ),
        if (showViewErrorsButton)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (onViewErrors != null) {
                onViewErrors!();
              } else {
                DebugConsoleService().openPanel();
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: CursorTheme.primary,
            ),
            child: const Text('Ver errores'),
          ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          style: TextButton.styleFrom(
            foregroundColor: CursorTheme.textSecondary,
          ),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
