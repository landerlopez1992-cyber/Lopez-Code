import 'package:flutter/material.dart';

import '../services/agent_diff_review_service.dart';
import 'cursor_theme.dart';

/// Barra flotante estilo Cursor: ↑ ↓ · 1 of N · Undo · Keep (+ All).
class DiffReviewBar extends StatelessWidget {
  const DiffReviewBar({
    super.key,
    required this.review,
    required this.onPrevious,
    required this.onNext,
    required this.onUndo,
    required this.onKeep,
    required this.onUndoAll,
    required this.onKeepAll,
  });

  final FileDiffReview review;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onUndo;
  final VoidCallback onKeep;
  final VoidCallback onUndoAll;
  final VoidCallback onKeepAll;

  @override
  Widget build(BuildContext context) {
    final total = review.hunks.length;
    final index = review.activeIndex.clamp(0, total - 1) + 1;
    final hunk = review.activeHunk;
    final added = hunk?.addedLines.length ?? 0;
    final removed = hunk?.removedLines.length ?? 0;

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF252526),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: CursorTheme.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IconBtn(
              icon: Icons.keyboard_arrow_up,
              tooltip: 'Cambio anterior',
              onTap: onPrevious,
            ),
            _IconBtn(
              icon: Icons.keyboard_arrow_down,
              tooltip: 'Siguiente cambio',
              onTap: onNext,
            ),
            const SizedBox(width: 4),
            Text(
              '$index of $total',
              style: const TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            if (removed > 0 || added > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  [
                    if (removed > 0) '−$removed',
                    if (added > 0) '+$added',
                  ].join(' '),
                  style: TextStyle(
                    color: removed > 0
                        ? const Color(0xFFF85149)
                        : const Color(0xFF3FB950),
                    fontSize: 11,
                    fontFamily: 'Menlo',
                  ),
                ),
              ),
            _TextBtn(
              label: 'Undo',
              color: const Color(0xFFF85149),
              onTap: onUndo,
            ),
            const SizedBox(width: 4),
            _TextBtn(
              label: 'Keep',
              color: const Color(0xFF3FB950),
              filled: true,
              onTap: onKeep,
            ),
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: CursorTheme.border,
            ),
            _TextBtn(
              label: 'Undo All',
              color: CursorTheme.textSecondary,
              onTap: onUndoAll,
            ),
            const SizedBox(width: 4),
            _TextBtn(
              label: 'Keep All',
              color: CursorTheme.textSecondary,
              onTap: onKeepAll,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: CursorTheme.textPrimary),
        ),
      ),
    );
  }
}

class _TextBtn extends StatelessWidget {
  const _TextBtn({
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: filled ? color.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: filled ? 0.6 : 0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Regla vertical de cambios (overview ruler) a la derecha del editor.
class DiffOverviewRuler extends StatelessWidget {
  const DiffOverviewRuler({
    super.key,
    required this.hunks,
    required this.lineCount,
    required this.activeHunkId,
    required this.onTapHunk,
  });

  final List<DiffHunk> hunks;
  final int lineCount;
  final String? activeHunkId;
  final ValueChanged<DiffHunk> onTapHunk;

  static const double width = 10;

  @override
  Widget build(BuildContext context) {
    if (hunks.isEmpty || lineCount <= 0) {
      return const SizedBox(width: width);
    }
    return SizedBox(
      width: width,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;
          return Stack(
            children: [
              for (final hunk in hunks)
                _mark(
                  hunk: hunk,
                  height: h,
                  onTap: () => onTapHunk(hunk),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _mark({
    required DiffHunk hunk,
    required double height,
    required VoidCallback onTap,
  }) {
    final total = mathMax(lineCount, 1);
    final start = ((hunk.startLine - 1) / total).clamp(0.0, 1.0);
    final spanLines = mathMax(
      hunk.addedCount > 0 ? hunk.addedCount : hunk.removedLines.length,
      1,
    );
    final span = (spanLines / total).clamp(2.0 / height, 0.2);
    final top = start * height;
    final markHeight = (span * height).clamp(2.0, height - top);
    final isActive = hunk.id == activeHunkId;
    final hasAdd = hunk.hasAdditions;
    final hasDel = hunk.hasDeletions;
    final color = hasAdd && hasDel
        ? const Color(0xFFD29922)
        : hasDel
            ? const Color(0xFFF85149)
            : const Color(0xFF3FB950);

    return Positioned(
      top: top,
      right: 2,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: isActive ? 6 : 4,
          height: markHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: isActive
                ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4)]
                : null,
          ),
        ),
      ),
    );
  }
}

int mathMax(int a, int b) => a > b ? a : b;
