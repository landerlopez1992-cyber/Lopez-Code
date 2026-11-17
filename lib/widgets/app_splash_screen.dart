import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cursor_theme.dart';
import 'voryxel_brand_logo.dart';

/// Splash moderna con logo + barra de carga (~4–6 s).
class AppSplashScreen extends StatefulWidget {
  final VoidCallback onFinished;
  /// Trabajo opcional en paralelo (permisos, init…).
  final Future<void> Function()? whileLoading;

  const AppSplashScreen({
    super.key,
    required this.onFinished,
    this.whileLoading,
  });

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _progressCtrl;
  late final AnimationController _fadeCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _progress;
  late final Animation<double> _fadeOut;
  late final Animation<double> _logoScale;
  String _status = 'Iniciando…';

  static const _statusSteps = [
    'Iniciando…',
    'Cargando entorno…',
    'Preparando editor…',
    'Listo',
  ];

  @override
  void initState() {
    super.initState();

    // Duración aleatoria entre 4.0 y 6.0 s (aspecto natural).
    final seconds = 4.0 + math.Random().nextDouble() * 2.0;
    final duration = Duration(milliseconds: (seconds * 1000).round());

    _progressCtrl = AnimationController(vsync: this, duration: duration);
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _progress = CurvedAnimation(
      parent: _progressCtrl,
      curve: const Cubic(0.22, 0.61, 0.36, 1),
    );
    _fadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic),
    );
    _logoScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseCtrl,
        curve: Curves.easeInOut,
      ),
    );

    _progressCtrl.addListener(_updateStatus);
    _progressCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finish();
      }
    });

    _boot();
  }

  Future<void> _boot() async {
    final work = widget.whileLoading?.call() ?? Future<void>.value();
    _progressCtrl.forward();
    try {
      await work;
    } catch (_) {
      // El splash sigue hasta completar la barra.
    }
  }

  void _updateStatus() {
    final t = _progress.value;
    final idx = (t * (_statusSteps.length - 1)).floor().clamp(
          0,
          _statusSteps.length - 1,
        );
    final next = _statusSteps[idx];
    if (next != _status && mounted) {
      setState(() => _status = next);
    }
  }

  Future<void> _finish() async {
    if (!mounted) return;
    setState(() => _status = 'Listo');
    await _fadeCtrl.forward();
    if (mounted) widget.onFinished();
  }

  @override
  void dispose() {
    _progressCtrl.removeListener(_updateStatus);
    _progressCtrl.dispose();
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeOut,
      child: Scaffold(
        backgroundColor: const Color(0xFF121214),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.35),
              radius: 1.15,
              colors: [
                Color(0xFF1A2332),
                Color(0xFF121214),
                Color(0xFF0C0C0E),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: _logoScale,
                      child: const VoryxelBrandLogo(
                        iconSize: 88,
                        fontSize: 26,
                        showSubtitle: true,
                        subtitle: 'IDE · Web Builder',
                        style: VoryxelLogoStyle.tile,
                      ),
                    ),
                    const SizedBox(height: 48),
                    AnimatedBuilder(
                      animation: _progress,
                      builder: (context, _) {
                        return _ModernProgressBar(value: _progress.value);
                      },
                    ),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        _status,
                        key: ValueKey(_status),
                        style: TextStyle(
                          color: CursorTheme.textSecondary
                              .withValues(alpha: 0.95),
                          fontSize: 12,
                          letterSpacing: 0.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernProgressBar extends StatelessWidget {
  final double value;

  const _ModernProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fill = (width * value.clamp(0.0, 1.0));
        return SizedBox(
          height: 6,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Track
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const SizedBox.expand(),
              ),
              // Fill + glow
              Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 40),
                  width: fill.clamp(0, width),
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF0EA5E9),
                        Color(0xFF007ACC),
                        Color(0xFF38BDF8),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF007ACC)
                            .withValues(alpha: 0.45),
                        blurRadius: 12,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                ),
              ),
              // Leading shimmer tip
              if (fill > 8)
                Positioned(
                  left: (fill - 10).clamp(0, width),
                  top: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.85),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF38BDF8)
                              .withValues(alpha: 0.7),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
