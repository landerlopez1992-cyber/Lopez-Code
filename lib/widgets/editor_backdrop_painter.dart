import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/agent_diff_review_service.dart';
import 'code_syntax_controller.dart';

/// Capa detrás del TextField del editor: línea actual, ocurrencias, guías de
/// sangría y resaltado Keep/Undo (verdes / rojos fantasma).
class EditorBackdropPainter extends CustomPainter {
  EditorBackdropPainter({
    required this.lines,
    required this.verticalScroll,
    required this.padding,
    required this.charWidth,
    required this.cursorLine,
    required this.showCurrentLine,
    required this.highlightWord,
    this.hunks = const [],
    this.activeHunkId,
    this.agentFocusLine,
    this.agentPulse = 0.0,
    Listenable? repaint,
  }) : super(repaint: repaint ?? verticalScroll);

  final List<String> lines;
  final ScrollController verticalScroll;
  final EdgeInsets padding;
  final double charWidth;
  final int cursorLine;
  final bool showCurrentLine;
  final String? highlightWord;
  final List<DiffHunk> hunks;
  final String? activeHunkId;

  /// Línea 0-based que el agente está tocando (null = inactivo).
  final int? agentFocusLine;

  /// 0..1 para el pulso azul (estilo explorador).
  final double agentPulse;

  static const Color currentLineColor = Color(0xFF2A2D2E);
  static const Color occurrenceColor = Color(0xFF3A3D41);
  static const Color guideColor = Color(0xFF404040);
  static const Color addedFill = Color(0xFF1E3A29);
  static const Color addedBorder = Color(0xFF3FB950);
  static const Color removedFill = Color(0xFF3D1E20);
  static const Color removedBorder = Color(0xFFF85149);
  static const Color removedText = Color(0xFFFFA198);
  static const Color agentLineColor = Color(0xFF007ACC);
  static const int indentStep = 2;
  static const int tabColumns = 4;
  static const int _blankLookaround = 200;

  final Map<String, double> _prefixWidthCache = {};

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty) return;
    const lh = EditorMetrics.lineHeight;
    final scrollY = verticalScroll.hasClients ? verticalScroll.offset : 0.0;

    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(0, padding.top, size.width, size.height - padding.bottom),
    );

    final first = math.max(0, (scrollY / lh).floor() - 1);
    final last = math.min(
      lines.length - 1,
      ((scrollY + size.height) / lh).ceil() + 1,
    );
    double topOf(int i) => padding.top + i * lh - scrollY;

    // ── Diff: verdes (añadidas) y rojos fantasma (eliminadas) ─────────
    if (hunks.isNotEmpty) {
      _paintDiffHunks(canvas, size, lh, scrollY, topOf, first, last);
    }

    if (showCurrentLine && cursorLine >= first && cursorLine <= last) {
      canvas.drawRect(
        Rect.fromLTWH(0, topOf(cursorLine), size.width, lh),
        Paint()..color = currentLineColor.withValues(alpha: 0.55),
      );
    }

    // Línea del agente (preselección + pulso, como el explorador).
    final agentLine = agentFocusLine;
    if (agentLine != null &&
        agentLine >= first &&
        agentLine <= last &&
        agentLine >= 0 &&
        agentLine < lines.length) {
      final y = topOf(agentLine);
      final glow = 0.22 + agentPulse * 0.38;
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, lh),
        Paint()..color = agentLineColor.withValues(alpha: glow),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, y, 3, lh),
        Paint()..color = agentLineColor.withValues(alpha: 0.55 + agentPulse * 0.45),
      );
      // Subrayado inferior de la línea (feedback “escribiendo aquí”).
      canvas.drawRect(
        Rect.fromLTWH(0, y + lh - 2, size.width, 2),
        Paint()
          ..color = agentLineColor.withValues(alpha: 0.45 + agentPulse * 0.55),
      );
    }

    final word = highlightWord;
    if (word != null && word.isNotEmpty) {
      final re = RegExp(
        '(?<![A-Za-z0-9_\$])${RegExp.escape(word)}(?![A-Za-z0-9_\$])',
      );
      final paint = Paint()..color = occurrenceColor;
      for (var i = first; i <= last; i++) {
        final line = lines[i];
        if (!line.contains(word)) continue;
        for (final m in re.allMatches(line)) {
          final x0 = padding.left + _xForColumn(line, m.start);
          final x1 = padding.left + _xForColumn(line, m.end);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(x0, topOf(i) + 1, x1, topOf(i) + lh - 1),
              const Radius.circular(2),
            ),
            paint,
          );
        }
      }
    }

    final guidePaint = Paint()
      ..color = guideColor
      ..strokeWidth = 1;
    for (var i = first; i <= last; i++) {
      final indent = _guideIndent(i);
      if (indent < indentStep) continue;
      final y = topOf(i);
      for (var col = 0; col < indent; col += indentStep) {
        final x = padding.left + col * charWidth + 0.5;
        canvas.drawLine(Offset(x, y), Offset(x, y + lh), guidePaint);
      }
    }

    canvas.restore();
  }

  void _paintDiffHunks(
    Canvas canvas,
    Size size,
    double lh,
    double scrollY,
    double Function(int) topOf,
    int first,
    int last,
  ) {
    final addedPaint = Paint()..color = addedFill;
    final removedPaint = Paint()..color = removedFill;
    final activeAdded = Paint()..color = const Color(0xFF244032);
    final activeRemoved = Paint()..color = const Color(0xFF4A2224);

    for (final hunk in hunks) {
      final isActive = hunk.id == activeHunkId;

      // Líneas eliminadas: bloque rojo fantasma justo encima del hunk.
      if (hunk.removedLines.isNotEmpty) {
        final ghostCount = hunk.removedLines.length;
        final anchorTop = padding.top +
            (hunk.startLine - 1) * lh -
            scrollY -
            ghostCount * lh;
        for (var g = 0; g < ghostCount; g++) {
          final y = anchorTop + g * lh;
          if (y + lh < padding.top || y > size.height) continue;
          canvas.drawRect(
            Rect.fromLTWH(0, y, size.width, lh),
            isActive ? activeRemoved : removedPaint,
          );
          canvas.drawRect(
            Rect.fromLTWH(0, y, 3, lh),
            Paint()..color = removedBorder,
          );
          final tp = TextPainter(
            text: TextSpan(
              text: '- ${hunk.removedLines[g]}',
              style: EditorMetrics.textStyle.copyWith(
                color: removedText,
                decoration: TextDecoration.lineThrough,
                decorationColor: removedText.withValues(alpha: 0.5),
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            strutStyle: EditorMetrics.strut,
          )..layout(maxWidth: math.max(0, size.width - padding.horizontal));
          tp.paint(canvas, Offset(padding.left, y));
          tp.dispose();
        }
      }

      // Líneas añadidas / modificadas en el documento nuevo.
      if (hunk.addedCount > 0) {
        final start0 = hunk.addedStart0;
        final end0 = start0 + hunk.addedCount - 1;
        for (var i = start0; i <= end0; i++) {
          if (i < first || i > last || i >= lines.length) continue;
          final y = topOf(i);
          canvas.drawRect(
            Rect.fromLTWH(0, y, size.width, lh),
            isActive ? activeAdded : addedPaint,
          );
          canvas.drawRect(
            Rect.fromLTWH(0, y, 3, lh),
            Paint()..color = addedBorder,
          );
        }
      } else if (hunk.removedLines.isNotEmpty) {
        // Solo borrados: marca roja en el ancla (línea siguiente).
        final anchor = math.min(hunk.addedStart0, lines.length - 1);
        if (anchor >= first && anchor <= last) {
          canvas.drawRect(
            Rect.fromLTWH(0, topOf(anchor), 3, lh),
            Paint()..color = removedBorder,
          );
        }
      }
    }
  }

  int _guideIndent(int i) {
    final own = _indentOf(lines[i]);
    if (own != null) return own;
    int? before;
    for (var j = i - 1; j >= 0 && j >= i - _blankLookaround; j--) {
      before = _indentOf(lines[j]);
      if (before != null) break;
    }
    int? after;
    for (var j = i + 1; j < lines.length && j <= i + _blankLookaround; j++) {
      after = _indentOf(lines[j]);
      if (after != null) break;
    }
    if (before == null || after == null) return 0;
    return math.min(before, after);
  }

  static int? _indentOf(String line) {
    var cols = 0;
    for (var k = 0; k < line.length; k++) {
      final c = line.codeUnitAt(k);
      if (c == 0x20) {
        cols++;
      } else if (c == 0x09) {
        cols += tabColumns;
      } else if (c == 0x0D) {
        continue;
      } else {
        return cols;
      }
    }
    return null;
  }

  double _xForColumn(String line, int column) {
    var simple = true;
    for (var k = 0; k < column; k++) {
      final c = line.codeUnitAt(k);
      if (c > 0x7E || c == 0x09) {
        simple = false;
        break;
      }
    }
    if (simple) return column * charWidth;
    final prefix = line.substring(0, column);
    return _prefixWidthCache.putIfAbsent(prefix, () {
      final tp = TextPainter(
        text: TextSpan(text: prefix, style: EditorMetrics.textStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    });
  }

  @override
  bool shouldRepaint(covariant EditorBackdropPainter old) =>
      !identical(old.lines, lines) ||
      old.cursorLine != cursorLine ||
      old.showCurrentLine != showCurrentLine ||
      old.highlightWord != highlightWord ||
      old.charWidth != charWidth ||
      old.padding != padding ||
      !identical(old.hunks, hunks) ||
      old.activeHunkId != activeHunkId ||
      old.agentFocusLine != agentFocusLine ||
      old.agentPulse != agentPulse;
}
