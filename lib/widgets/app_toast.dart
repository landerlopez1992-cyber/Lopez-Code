import 'dart:async';

import 'package:flutter/material.dart';

import 'cursor_theme.dart';

enum AppToastTone { success, error, warning, info }

/// Avisos centrados oscuros (estilo Cursor / Voryxel).
/// **No usa SnackBar** — nada de barras verdes abajo.
class AppToast {
  AppToast._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  /// Toast modal centrado que se cierra solo.
  static void show(
    BuildContext context, {
    required String message,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 2200),
    bool loading = false,
    AppToastTone tone = AppToastTone.info,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      // Sin Overlay: diálogo modal de respaldo.
      unawaited(
        showModal(
          context,
          title: _titleForTone(tone),
          message: message,
        ),
      );
      return;
    }

    hide();

    final resolvedIcon = icon ?? _iconForTone(tone, loading: loading);
    final accent = _accentForTone(tone);

    _entry = OverlayEntry(
      builder: (ctx) {
        return IgnorePointer(
          ignoring: true,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                // Veladura suave para sensación de modal.
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 280,
                      maxWidth: 420,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: CursorTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: CursorTheme.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (loading)
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: accent,
                                ),
                              )
                            else
                              Icon(resolvedIcon, size: 20, color: accent),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                message,
                                style: const TextStyle(
                                  color: CursorTheme.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    overlay.insert(_entry!);
    _timer = Timer(duration, hide);
  }

  static void success(BuildContext context, String message) => show(
        context,
        message: message,
        tone: AppToastTone.success,
      );

  static void error(BuildContext context, String message) => show(
        context,
        message: message,
        tone: AppToastTone.error,
        duration: const Duration(milliseconds: 3200),
      );

  static void warning(BuildContext context, String message) => show(
        context,
        message: message,
        tone: AppToastTone.warning,
        duration: const Duration(milliseconds: 2800),
      );

  static void info(BuildContext context, String message) => show(
        context,
        message: message,
        tone: AppToastTone.info,
      );

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  /// Modal centrado con botón (avisos / confirmaciones).
  static Future<void> showModal(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Entendido',
    AppToastTone tone = AppToastTone.info,
  }) {
    final accent = _accentForTone(tone);
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: CursorTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: CursorTheme.border),
          ),
          title: Row(
            children: [
              Icon(_iconForTone(tone), size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
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
                style: TextStyle(color: accent),
              ),
            ),
          ],
        );
      },
    );
  }

  static IconData _iconForTone(AppToastTone tone, {bool loading = false}) {
    if (loading) return Icons.hourglass_top_rounded;
    switch (tone) {
      case AppToastTone.success:
        return Icons.check_circle_outline;
      case AppToastTone.error:
        return Icons.error_outline;
      case AppToastTone.warning:
        return Icons.warning_amber_rounded;
      case AppToastTone.info:
        return Icons.info_outline;
    }
  }

  static Color _accentForTone(AppToastTone tone) {
    switch (tone) {
      case AppToastTone.success:
        return const Color(0xFF3FB950);
      case AppToastTone.error:
        return const Color(0xFFE57373);
      case AppToastTone.warning:
        return const Color(0xFFE8A838);
      case AppToastTone.info:
        return CursorTheme.primary;
    }
  }

  static String _titleForTone(AppToastTone tone) {
    switch (tone) {
      case AppToastTone.success:
        return 'Listo';
      case AppToastTone.error:
        return 'Error';
      case AppToastTone.warning:
        return 'Aviso';
      case AppToastTone.info:
        return 'Información';
    }
  }
}

/// Sustituto drop-in de [ScaffoldMessenger.showSnackBar] → toast centrado.
void showAppSnack(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(milliseconds: 2200),
}) {
  final tone = _toneFromColor(backgroundColor);
  AppToast.show(
    context,
    message: message,
    tone: tone,
    duration: duration,
  );
}

AppToastTone _toneFromColor(Color? c) {
  if (c == null) return AppToastTone.info;
  // ignore: deprecated_member_use
  final r = c.red;
  // ignore: deprecated_member_use
  final g = c.green;
  // ignore: deprecated_member_use
  final b = c.blue;
  // Heurística: verde → success, rojo → error, naranja → warning.
  if (g > r + 30 && g > b) return AppToastTone.success;
  if (r > g + 30 && r > b) return AppToastTone.error;
  if (r > 180 && g > 100 && b < 100) return AppToastTone.warning;
  return AppToastTone.info;
}
