import 'package:flutter/material.dart';
import '../models/pending_action.dart';
import 'cursor_theme.dart';

/// Tarjeta compacta de acciones pendientes (estilo Cursor).
class PendingActionsCard extends StatelessWidget {
  final List<PendingAction> pendingActions;
  final Function(List<PendingAction>) onAccept;
  final Function() onReject;

  const PendingActionsCard({
    super.key,
    required this.pendingActions,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        color: CursorTheme.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: CursorTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...pendingActions.map(_buildCompactAction),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onReject,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF8E8E93),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reject', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: () => onAccept(pendingActions),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CursorTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    elevation: 0,
                  ),
                  child: const Text('Accept', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactAction(PendingAction action) {
    final filePath = action.arguments['file_path'] as String? ?? '';
    final fileName = filePath.isEmpty
        ? action.getActionSummary()
        : filePath.split('/').last;
    final visualDiff = _resolveDiff(action);
    final counts = _countDiff(visualDiff);
    final previewLines = visualDiff.isEmpty
        ? const <String>[]
        : visualDiff.split('\n').where((l) => l.trim().isNotEmpty).take(5).toList();

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: CursorTheme.border.withValues(alpha: 0.6),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cabecera delgada: icono + archivo + +X -Y
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.insert_drive_file_outlined,
                  size: 14,
                  color: const Color(0xFF8E8E93),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fileName,
                    style: const TextStyle(
                      color: CursorTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (counts.$1 > 0)
                  Text(
                    '+${counts.$1}',
                    style: const TextStyle(
                      color: Color(0xFF3FB950),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                if (counts.$1 > 0 && counts.$2 > 0) const SizedBox(width: 6),
                if (counts.$2 > 0)
                  Text(
                    '-${counts.$2}',
                    style: const TextStyle(
                      color: Color(0xFFF85149),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
          if (previewLines.isNotEmpty)
            Container(
              color: const Color(0xFF181818),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < previewLines.length; i++)
                    _buildDiffLine(previewLines[i], i + 1),
                ],
              ),
            ),
        ],
      ),
    );
  }

  (int, int) _countDiff(String visualDiff) {
    var added = 0;
    var removed = 0;
    for (final line in visualDiff.split('\n')) {
      if (line.startsWith('+') && !line.startsWith('+++')) added++;
      if (line.startsWith('-') && !line.startsWith('---')) removed++;
    }
    return (added, removed);
  }

  String _resolveDiff(PendingAction action) {
    final existingDiff = action.diff?.trim() ?? '';
    if (existingDiff.isNotEmpty) return existingDiff;

    final oldContent = action.oldContent;
    final newContent = action.newContent;
    if (oldContent == null || newContent == null || oldContent == newContent) {
      return '';
    }

    final oldLines = oldContent.split('\n');
    final newLines = newContent.split('\n');
    final output = <String>[];
    final maxLength =
        oldLines.length > newLines.length ? oldLines.length : newLines.length;

    for (var index = 0; index < maxLength; index++) {
      final oldLine = index < oldLines.length ? oldLines[index] : null;
      final newLine = index < newLines.length ? newLines[index] : null;
      if (oldLine == newLine && oldLine != null) {
        output.add('  $oldLine');
      } else {
        if (oldLine != null) output.add('- $oldLine');
        if (newLine != null) output.add('+ $newLine');
      }
    }
    return output.join('\n');
  }

  Widget _buildDiffLine(String line, int lineNumber) {
    final isRemoved = line.startsWith('-');
    final isAdded = line.startsWith('+');
    final barColor = isRemoved
        ? const Color(0xFFF85149)
        : isAdded
            ? const Color(0xFF3FB950)
            : Colors.transparent;
    final foregroundColor = isRemoved
        ? const Color(0xFFFFA198)
        : isAdded
            ? const Color(0xFF7EE787)
            : const Color(0xFF8E8E93);
    final text = line.length >= 2 && (isAdded || isRemoved)
        ? line.substring(1).trimLeft()
        : line.trimLeft();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 3, color: barColor),
          SizedBox(
            width: 32,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  '$lineNumber',
                  style: const TextStyle(
                    color: Color(0xFF6E7681),
                    fontSize: 10,
                    fontFamily: 'monospace',
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 6),
              child: Text(
                text.isEmpty ? ' ' : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foregroundColor,
                  fontFamily: 'JetBrains Mono',
                  fontFamilyFallback: const ['monospace'],
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
