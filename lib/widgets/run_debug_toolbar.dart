import 'package:flutter/material.dart';
import '../services/advanced_debugging_service.dart';
import '../services/debug_console_service.dart';
import '../services/platform_service.dart';
import '../services/project_platform_support.dart';
import 'cursor_theme.dart';

/// Barra de herramientas de Run and Debug
/// Similar a Cursor IDE - botones para ejecutar, depurar, etc.
/// Ahora es arrastrable como en Cursor IDE
class RunDebugToolbar extends StatefulWidget {
  final VoidCallback? onRun;
  final VoidCallback? onDebug;
  final VoidCallback? onStop;
  final VoidCallback? onRestart;
  final VoidCallback? onHotReload;
  final VoidCallback? onHotRestart;
  final Function(String)? onPlatformChanged;
  final String? selectedPlatform;
  final bool isRunning;
  final bool isDebugging;

  const RunDebugToolbar({
    super.key,
    this.onRun,
    this.onDebug,
    this.onStop,
    this.onRestart,
    this.onHotReload,
    this.onHotRestart,
    this.onPlatformChanged,
    this.selectedPlatform,
    this.isRunning = false,
    this.isDebugging = false,
  });

  @override
  State<RunDebugToolbar> createState() => _RunDebugToolbarState();
}

class _RunDebugToolbarState extends State<RunDebugToolbar> {
  /// null = aún no arrastrada → centrar arriba (posición default foto 1/2).
  Offset? _draggedPosition;
  bool _isDragging = false;
  static const double _toolbarApproxWidth = 360.0;
  static const double _toolbarApproxHeight = 36.0;
  static const double _defaultTop = 10.0;

  /// Centro horizontal del AppBar, como en la captura de arranque.
  Offset _defaultCenteredPosition(Size screenSize) {
    final left = ((screenSize.width - _toolbarApproxWidth) / 2)
        .clamp(8.0, screenSize.width - _toolbarApproxWidth);
    return Offset(left, _defaultTop);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final defaultPos = _defaultCenteredPosition(screenSize);
    final position = _draggedPosition ?? defaultPos;
    final finalLeft = position.dx.clamp(
      0.0,
      (screenSize.width - _toolbarApproxWidth).clamp(0.0, screenSize.width),
    );
    final finalTop = position.dy.clamp(
      0.0,
      (screenSize.height - _toolbarApproxHeight).clamp(0.0, screenSize.height),
    );

    return Positioned(
      left: finalLeft,
      top: finalTop,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            setState(() {
              _isDragging = true;
              // Congelar la posición actual (centrada) al empezar a arrastrar.
              _draggedPosition ??= Offset(finalLeft, finalTop);
            });
          },
          onPanUpdate: (details) {
            setState(() {
              final current = _draggedPosition ?? Offset(finalLeft, finalTop);
              _draggedPosition = Offset(
                (current.dx + details.delta.dx).clamp(
                  0.0,
                  screenSize.width - _toolbarApproxWidth,
                ),
                (current.dy + details.delta.dy).clamp(
                  0.0,
                  screenSize.height - _toolbarApproxHeight,
                ),
              );
            });
          },
          onPanEnd: (details) {
            setState(() {
              _isDragging = false;
            });
          },
          child: MouseRegion(
          cursor: _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
          child: Material(
            color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 32, maxWidth: 600),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: CursorTheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isDragging ? CursorTheme.primary : CursorTheme.border,
                  width: _isDragging ? 2 : 1,
                ),
                boxShadow: _isDragging
                    ? [
                        BoxShadow(
                          color: CursorTheme.primary.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            child: AnimatedBuilder(
              animation: DebugConsoleService(),
              builder: (context, _) {
                final debug = DebugConsoleService();
                final running = widget.isRunning || debug.isRunning;
                final statusLower = debug.compilationStatus.toLowerCase();
                final progress = debug.compilationProgress;
                final hasUrl =
                    debug.appUrl != null && debug.appUrl!.isNotEmpty;
                // Fases de carga (aún no "app viva" con Hot Reload).
                final loadingPhase = statusLower.contains('instal') ||
                    statusLower.contains('iniciando') ||
                    statusLower.contains('compil') ||
                    statusLower.contains('lanzand') ||
                    statusLower.contains('prepar') ||
                    statusLower.contains('resolv') ||
                    statusLower.contains('syncing') ||
                    statusLower.contains('waiting') ||
                    statusLower.contains('launching') ||
                    statusLower.contains('building');
                final fullyReady = progress >= 1.0 &&
                    (statusLower.contains('ejecut') ||
                        statusLower.contains('running') ||
                        statusLower.contains('hot reload') ||
                        AdvancedDebuggingService.supportsHotReload);
                final building = running && !fullyReady &&
                    (progress < 1.0 || loadingPhase || !hasUrl);
                // App lista → controles Hot Reload / Restart / Stop (foto 2)
                final appReady = running &&
                    (fullyReady || hasUrl || progress > 0.05 || building);
                // Flutter Hot Reload (stdin) O Preview HTML con URL lista.
                final flutterHot = AdvancedDebuggingService.supportsHotReload;
                final previewHot = hasUrl && running;
                final hotReady = flutterHot || previewHot;
                final hotBusy = debug.isHotBusy;
                final reloading = debug.isHotReloading;
                final restarting = debug.isHotRestarting;

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_isDragging)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.drag_handle,
                          size: 12,
                          color: CursorTheme.primary,
                        ),
                      ),

                    if (appReady) ...[
                      // Controles vivos estilo Cursor (foto 2)
                      _LiveActionButton(
                        icon: Icons.bolt,
                        color: hotReady
                            ? const Color(0xFFE8A838)
                            : const Color(0xFFE8A838).withValues(alpha: 0.35),
                        tooltip: reloading
                            ? 'Hot Reloading…'
                            : (flutterHot
                                ? 'Hot Reload'
                                : (previewHot
                                    ? 'Refresh Preview (HTML)'
                                    : 'Hot Reload (espera compile debug…)')),
                        loading: reloading,
                        onPressed: (hotReady && !hotBusy)
                            ? widget.onHotReload
                            : null,
                      ),
                      const SizedBox(width: 2),
                      _LiveActionButton(
                        icon: Icons.restart_alt,
                        color: hotReady
                            ? const Color(0xFF6FCF97)
                            : const Color(0xFF6FCF97).withValues(alpha: 0.35),
                        tooltip: restarting
                            ? 'Hot Restarting…'
                            : (flutterHot
                                ? 'Hot Restart'
                                : (previewHot
                                    ? 'Reload Preview (HTML)'
                                    : 'Hot Restart (o reinicio completo)')),
                        loading: restarting,
                        onPressed: (!hotBusy)
                            ? (widget.onHotRestart ?? widget.onRestart)
                            : null,
                      ),
                      const SizedBox(width: 2),
                      _LiveActionButton(
                        icon: Icons.stop_rounded,
                        color: const Color(0xFFE57373),
                        tooltip: 'Stop',
                        onPressed: widget.onStop,
                      ),
                      if (hotBusy) ...[
                        const SizedBox(width: 6),
                        _HotActionStatusChip(
                          restarting: restarting,
                        ),
                      ],
                    ] else ...[
                      // Idle / compilando: Run + Debug + Stop/Restart clásicos
                      _ToolbarButton(
                        icon: Icons.play_arrow,
                        label: 'Run',
                        onPressed: running ? null : widget.onRun,
                        color: Colors.green,
                        tooltip: 'Ejecutar aplicación',
                      ),
                      const SizedBox(width: 3),
                      _ToolbarButton(
                        icon: Icons.bug_report,
                        label: 'Debug',
                        onPressed: running ? null : widget.onDebug,
                        color: Colors.orange,
                        tooltip: 'Depurar aplicación',
                        isEnabled: widget.isDebugging && running,
                      ),
                      const SizedBox(width: 3),
                      _ToolbarButton(
                        icon: Icons.stop,
                        label: 'Stop',
                        onPressed: running ? widget.onStop : null,
                        color: Colors.red,
                        tooltip: 'Detener ejecución',
                        isEnabled: running,
                      ),
                      const SizedBox(width: 3),
                      _ToolbarButton(
                        icon: Icons.refresh,
                        label: 'Restart',
                        onPressed: running ? widget.onRestart : null,
                        color: Colors.blue,
                        tooltip: 'Reiniciar aplicación',
                        isEnabled: running,
                      ),
                    ],

                    const SizedBox(width: 6),
                    Container(
                      width: 1,
                      height: 20,
                      color: CursorTheme.border,
                    ),
                    const SizedBox(width: 6),

                    AnimatedBuilder(
                      animation: PlatformService(),
                      builder: (context, _) {
                        return _PlatformSelector(
                          selectedPlatform:
                              widget.selectedPlatform ??
                              PlatformService().selectedPlatform,
                          onChanged: widget.onPlatformChanged,
                          isEnabled: !running,
                          supportedPlatforms:
                              PlatformService().supportedPlatforms,
                        );
                      },
                    ),

                    if (running) ...[
                      const SizedBox(width: 6),
                      _RunningStatusChip(
                        building: building,
                        isDebugging: widget.isDebugging,
                        status: debug.compilationStatus,
                        progress: progress,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Controles vivos (Hot Reload / Hot Restart / Stop) — estilo foto 2.
class _LiveActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool loading;

  const _LiveActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(
                    icon,
                    size: 18,
                    color: enabled
                        ? color
                        : CursorTheme.textSecondary.withValues(alpha: 0.35),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Chip "Hot reloading…" / "Hot restarting…" junto a los botones (estilo Cursor).
class _HotActionStatusChip extends StatelessWidget {
  final bool restarting;

  const _HotActionStatusChip({required this.restarting});

  @override
  Widget build(BuildContext context) {
    final label = restarting ? 'Hot restarting…' : 'Hot reloading…';
    final accent =
        restarting ? const Color(0xFF6FCF97) : const Color(0xFFE8A838);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: accent,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de estado Run/Debug: punto intermitente + barra de progreso al cargar.
class _RunningStatusChip extends StatefulWidget {
  final bool building;
  final bool isDebugging;
  final String status;
  final double progress;

  const _RunningStatusChip({
    required this.building,
    required this.isDebugging,
    required this.status,
    required this.progress,
  });

  @override
  State<_RunningStatusChip> createState() => _RunningStatusChipState();
}

class _RunningStatusChipState extends State<_RunningStatusChip>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  /// Brillo “va y ven” sobre la barra (más visible que el pulse del borde).
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _RunningStatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.building != widget.building) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (widget.building) {
      if (!_pulse.isAnimating) {
        _pulse.repeat(reverse: true);
      }
      if (!_shimmer.isAnimating) {
        _shimmer.repeat(reverse: true);
      }
    } else {
      _pulse.stop();
      _pulse.value = 1.0;
      _shimmer.stop();
      _shimmer.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.status.isNotEmpty
        ? widget.status
        : (widget.isDebugging ? 'Debugging...' : 'Running...');
    final accent = widget.building
        ? const Color(0xFFE8A838)
        : const Color(0xFF6FCF97);
    final showBar = widget.building || widget.progress < 1.0;
    final barValue = widget.progress.clamp(0.05, 1.0);
    final indeterminate = widget.progress < 0.08 ||
        (widget.building && widget.progress >= 0.95 && widget.progress < 1.0);

    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _shimmer]),
      builder: (context, _) {
        final glow = widget.building ? (0.45 + _pulse.value * 0.55) : 1.0;
        // Compacto: cabe en la toolbar (~28–32px) sin BOTTOM OVERFLOWED.
        return Container(
          constraints: const BoxConstraints(maxWidth: 210, maxHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: accent.withValues(
                alpha: 0.35 + (widget.building ? _pulse.value * 0.45 : 0.15),
              ),
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: glow,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.65 * glow),
                            blurRadius: widget.building ? 6 : 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      phase,
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (widget.building) ...[
                    const SizedBox(width: 4),
                    Text(
                      indeterminate
                          ? '…'
                          : '${(barValue * 100).round()}%',
                      style: TextStyle(
                        color: accent.withValues(alpha: 0.9),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ],
                ],
              ),
              if (showBar) ...[
                const SizedBox(height: 3),
                _ShimmerProgressBar(
                  width: 176,
                  height: 4,
                  progress: indeterminate ? null : barValue,
                  accent: accent,
                  shimmerT: widget.building ? _shimmer.value : 0.5,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Barra con brillo blanco-dorado que va y viene (muy visible).
class _ShimmerProgressBar extends StatelessWidget {
  final double width;
  final double height;
  final double? progress; // null = indeterminado (lleno + shimmer)
  final Color accent;
  final double shimmerT; // 0..1

  const _ShimmerProgressBar({
    required this.width,
    required this.height,
    required this.progress,
    required this.accent,
    required this.shimmerT,
  });

  @override
  Widget build(BuildContext context) {
    final fill = (progress ?? 1.0).clamp(0.08, 1.0);
    final trackW = width;
    final fillW = trackW * fill;
    // Ancho del destello ~28% del tramo lleno; se mueve de izq → der.
    final shimmerW = (fillW * 0.32).clamp(14.0, 56.0);
    final maxX = (fillW - shimmerW).clamp(0.0, fillW);
    final shimmerX = maxX * shimmerT;

    return SizedBox(
      width: trackW,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Stack(
          children: [
            // Pista
            Positioned.fill(
              child: ColoredBox(
                color: accent.withValues(alpha: 0.18),
              ),
            ),
            // Relleno
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: fillW,
              child: ColoredBox(color: accent),
            ),
            // Destello va-y-ven (contraste alto)
            if (fillW > 8)
              Positioned(
                left: shimmerX,
                top: 0,
                bottom: 0,
                width: shimmerW,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.0),
                        const Color(0xFFFFF3C4).withValues(alpha: 0.95),
                        Colors.white.withValues(alpha: 0.95),
                        const Color(0xFFFFF3C4).withValues(alpha: 0.95),
                        accent.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.28, 0.5, 0.72, 1.0],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Botón de la barra de herramientas
class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final String tooltip;
  final bool isEnabled;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.onPressed,
    required this.color,
    required this.tooltip,
    this.isEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null;
    
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isDisabled ? null : onPressed,
          borderRadius: BorderRadius.circular(4),
            child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: isEnabled
                  ? color.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: isEnabled
                  ? Border.all(
                      color: color.withOpacity(0.3),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: isDisabled
                      ? CursorTheme.textSecondary.withOpacity(0.3)
                      : isEnabled
                          ? color
                          : CursorTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isDisabled
                        ? CursorTheme.textSecondary.withOpacity(0.3)
                        : isEnabled
                            ? color
                            : CursorTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: isEnabled ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Selector de plataforma
class _PlatformSelector extends StatelessWidget {
  final String selectedPlatform;
  final Function(String)? onChanged;
  final bool isEnabled;
  final Set<String> supportedPlatforms;

  const _PlatformSelector({
    required this.selectedPlatform,
    this.onChanged,
    this.isEnabled = true,
    this.supportedPlatforms = const {'macos', 'ios', 'android', 'web'},
  });

  @override
  Widget build(BuildContext context) {
    final platforms = [
      {'value': 'macos', 'label': 'macOS', 'icon': Icons.desktop_mac},
      {
        'value': 'ios',
        'label': 'iOS (Preview)',
        'icon': Icons.phone_iphone,
      },
      {
        'value': 'ios_native',
        'label': 'iOS (Simulador)',
        'icon': Icons.phone_iphone,
      },
      {
        'value': 'android',
        'label': 'Android (Preview)',
        'icon': Icons.android,
      },
      {
        'value': 'android_native',
        'label': 'Android (Emulador Nativo)',
        'icon': Icons.smartphone,
      },
      {'value': 'web', 'label': 'Web', 'icon': Icons.language},
    ];

    final selected = platforms.firstWhere(
      (p) => p['value'] == selectedPlatform,
      orElse: () => platforms.first,
    );
    final selectedSupported = ProjectPlatformSupport.isSupportedVariant(
      selectedPlatform,
      supportedPlatforms,
    );

    return PopupMenuButton<String>(
      enabled: isEnabled,
      initialValue: selectedPlatform,
      tooltip: selectedSupported
          ? 'Seleccionar plataforma'
          : 'Plataforma no disponible en este proyecto',
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: CursorTheme.border, width: 1),
      ),
      color: CursorTheme.surface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 168),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: CursorTheme.background,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selectedSupported
                ? CursorTheme.border
                : Colors.orange.withOpacity(0.6),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected['icon'] as IconData,
              size: 12,
              color: isEnabled
                  ? (selectedSupported
                      ? CursorTheme.textPrimary
                      : Colors.orange)
                  : CursorTheme.textSecondary.withOpacity(0.3),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                selected['label'] as String,
                style: TextStyle(
                  color: isEnabled
                      ? (selectedSupported
                          ? CursorTheme.textPrimary
                          : Colors.orange)
                      : CursorTheme.textSecondary.withOpacity(0.3),
                  fontSize: 10,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 12,
              color: isEnabled
                  ? CursorTheme.textSecondary
                  : CursorTheme.textSecondary.withOpacity(0.3),
            ),
          ],
        ),
      ),
      onSelected: (value) {
        if (!ProjectPlatformSupport.isSupportedVariant(
          value,
          supportedPlatforms,
        )) {
          final hint = ProjectPlatformSupport.missingFolderHint(
            value,
            supportedPlatforms,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(hint),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 4),
            ),
          );
          final preferred = ProjectPlatformSupport.preferPlatform(
            supportedPlatforms,
          );
          if (preferred != null) {
            onChanged?.call(preferred);
          }
          return;
        }
        onChanged?.call(value);
      },
      itemBuilder: (context) {
        return platforms.map((platform) {
          final value = platform['value'] as String;
          final isSelected = value == selectedPlatform;
          final supported = ProjectPlatformSupport.isSupportedVariant(
            value,
            supportedPlatforms,
          );
          return PopupMenuItem<String>(
            value: value,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  platform['icon'] as IconData,
                  size: 18,
                  color: !supported
                      ? CursorTheme.textDisabled
                      : isSelected
                          ? CursorTheme.primary
                          : CursorTheme.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        platform['label'] as String,
                        style: TextStyle(
                          color: !supported
                              ? CursorTheme.textDisabled
                              : isSelected
                                  ? CursorTheme.primary
                                  : CursorTheme.textPrimary,
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (!supported)
                        Text(
                          'sin carpeta $value/',
                          style: const TextStyle(
                            color: CursorTheme.textDisabled,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isSelected && supported)
                  const Icon(
                    Icons.check,
                    size: 18,
                    color: CursorTheme.primary,
                  ),
              ],
            ),
          );
        }).toList();
      },
    );
  }
}
