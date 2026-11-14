import 'package:flutter/material.dart';

/// Barra de progreso horizontal con efecto de “rayos de luz” (shimmer).
/// Estilo Voryxel Code / Cursor: track oscuro + fill ámbar + sweep luminoso.
class LightRayProgressBar extends StatefulWidget {
  final double value; // 0.0 – 1.0
  final bool indeterminate;
  final Color accent;
  final double height;
  final BorderRadius? borderRadius;

  const LightRayProgressBar({
    super.key,
    required this.value,
    this.indeterminate = false,
    this.accent = const Color(0xFFE8A838),
    this.height = 3,
    this.borderRadius,
  });

  @override
  State<LightRayProgressBar> createState() => _LightRayProgressBarState();
}

class _LightRayProgressBarState extends State<LightRayProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(2);
    final track = widget.accent.withValues(alpha: 0.14);
    final fill = widget.accent;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: radius,
        child: AnimatedBuilder(
          animation: _shimmer,
          builder: (context, _) {
            return CustomPaint(
              painter: _LightRayProgressPainter(
                value: widget.indeterminate
                    ? null
                    : widget.value.clamp(0.0, 1.0),
                shimmer: _shimmer.value,
                trackColor: track,
                fillColor: fill,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

class _LightRayProgressPainter extends CustomPainter {
  final double? value;
  final double shimmer;
  final Color trackColor;
  final Color fillColor;

  _LightRayProgressPainter({
    required this.value,
    required this.shimmer,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()..color = trackColor;
    canvas.drawRect(Offset.zero & size, trackPaint);

    late Rect fillRect;
    if (value == null) {
      // Indeterminado: segmento que viaja de izq → der
      final segW = size.width * 0.28;
      final x = (shimmer * (size.width + segW)) - segW;
      fillRect = Rect.fromLTWH(x, 0, segW, size.height);
    } else {
      final w = size.width * value!;
      if (w <= 0) return;
      fillRect = Rect.fromLTWH(0, 0, w, size.height);
    }

    final fillPaint = Paint()..color = fillColor;
    canvas.drawRect(fillRect, fillPaint);

    // Rayo de luz: gradiente blanco/ámbar que barre el fill
    final rayW = fillRect.width * 0.45;
    if (rayW < 4) return;
    final rayX = fillRect.left +
        (shimmer * (fillRect.width + rayW)) -
        rayW;
    final rayRect = Rect.fromLTWH(
      rayX.clamp(fillRect.left - rayW, fillRect.right),
      0,
      rayW,
      size.height,
    ).intersect(fillRect);

    if (rayRect.width <= 0) return;

    final rayPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          fillColor.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.75),
          fillColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rayRect);
    canvas.drawRect(rayRect, rayPaint);
  }

  @override
  bool shouldRepaint(covariant _LightRayProgressPainter old) {
    return old.value != value ||
        old.shimmer != shimmer ||
        old.trackColor != trackColor ||
        old.fillColor != fillColor;
  }
}

/// Franja de estado de compilación para el panel inferior (foto 2 → foto 3).
class CompilationProgressStrip extends StatelessWidget {
  final double progress;
  final String status;
  final bool visible;

  const CompilationProgressStrip({
    super.key,
    required this.progress,
    required this.status,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    const accent = Color(0xFFE8A838);
    final indeterminate =
        progress < 0.08 || (progress >= 0.95 && progress < 1.0);
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    final label = status.isNotEmpty ? status : 'Compilando…';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(
            color: accent.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.55),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              Text(
                indeterminate ? '…' : '$percent%',
                style: TextStyle(
                  color: accent.withValues(alpha: 0.9),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LightRayProgressBar(
            value: progress.clamp(0.05, 1.0),
            indeterminate: indeterminate,
            accent: accent,
            height: 3,
          ),
        ],
      ),
    );
  }
}
