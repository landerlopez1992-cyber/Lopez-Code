import 'package:flutter/material.dart';

import 'cursor_theme.dart';

/// Feedback corto estilo Cursor: toast flotante oscuro (no SnackBar verde).
class AppToast {
  AppToast._();

  static void show(
    BuildContext context, {
    required String message,
    IconData icon = Icons.check_circle_outline,
    Duration duration = const Duration(milliseconds: 1600),
    bool loading = false,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CursorTheme.primary,
                ),
              )
            else
              Icon(icon, size: 16, color: CursorTheme.primary),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: CursorTheme.surface,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        margin: const EdgeInsets.only(bottom: 72, left: 24, right: 24),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: CursorTheme.border),
        ),
        duration: duration,
      ),
    );
  }

  /// Modal compacto para confirmaciones / avisos (alternativa al SnackBar).
  static Future<void> showModal(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Entendido',
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: CursorTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: CursorTheme.border),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: CursorTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: CursorTheme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                confirmLabel,
                style: const TextStyle(color: CursorTheme.primary),
              ),
            ),
          ],
        );
      },
    );
  }
}
