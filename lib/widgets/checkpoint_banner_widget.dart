import 'package:flutter/material.dart';

import '../models/chat_checkpoint.dart';
import '../services/checkpoint_service.dart';
import 'cursor_theme.dart';
import 'app_toast.dart';

/// Banner compacto estilo Cursor para restaurar un checkpoint con 1 clic.
///
/// Pensado para incrustarse bajo/sobre un mensaje del asistente.
class CheckpointBannerWidget extends StatefulWidget {
  final ChatCheckpoint checkpoint;

  /// Callback tras una restauración exitosa (p. ej. refrescar editor).
  final VoidCallback? onRestored;

  /// Override opcional del restore (por defecto usa [CheckpointService]).
  final Future<void> Function(ChatCheckpoint checkpoint)? onRestore;

  /// Si es `false`, oculta el botón Restore (solo lectura).
  final bool allowRestore;

  const CheckpointBannerWidget({
    super.key,
    required this.checkpoint,
    this.onRestored,
    this.onRestore,
    this.allowRestore = true,
  });

  @override
  State<CheckpointBannerWidget> createState() => _CheckpointBannerWidgetState();
}

class _CheckpointBannerWidgetState extends State<CheckpointBannerWidget> {
  bool _expanded = false;
  bool _restoring = false;
  bool _restoredLocally = false;

  ChatCheckpoint get _checkpoint => widget.checkpoint;

  int get _fileCount => _checkpoint.files.length;

  bool get _isRestored => _restoredLocally || _checkpoint.restored;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CursorTheme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          if (_expanded) _buildFileList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.history,
            size: 16,
            color: _isRestored
                ? CursorTheme.textSecondary
                : CursorTheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        _isRestored
                            ? 'Checkpoint restaurado • $_fileCount archivo(s)'
                            : 'Checkpoint • $_fileCount archivo(s) modificado(s)',
                        style: TextStyle(
                          color: CursorTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          decoration: _isRestored
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          decorationColor: CursorTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 16,
                      color: CursorTheme.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.allowRestore) ...[
            const SizedBox(width: 8),
            _buildRestoreButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildRestoreButton() {
    if (_restoring) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: CursorTheme.primary,
        ),
      );
    }

    return TextButton(
      onPressed: _isRestored ? null : _confirmAndRestore,
      style: TextButton.styleFrom(
        foregroundColor: CursorTheme.primary,
        disabledForegroundColor: CursorTheme.textDisabled,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: const Text(
        'Restore',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildFileList() {
    final files = _checkpoint.files;
    if (files.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(34, 0, 12, 10),
        child: Text(
          'Sin archivos registrados',
          style: TextStyle(color: CursorTheme.textSecondary, fontSize: 11),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: CursorTheme.border),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_checkpoint.label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _checkpoint.label,
                style: const TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ...files.map(_buildFileRow),
        ],
      ),
    );
  }

  Widget _buildFileRow(CheckpointFileEntry entry) {
    final isNew = entry.wasNewFile;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            isNew ? Icons.add_circle_outline : Icons.edit_outlined,
            size: 13,
            color: isNew ? Colors.greenAccent.shade400 : Colors.orangeAccent,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              entry.relativePath.isNotEmpty
                  ? entry.relativePath
                  : entry.originalPath,
              style: const TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            isNew ? 'nuevo' : 'modificado',
            style: const TextStyle(
              color: CursorTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: CursorTheme.surface,
          title: const Row(
            children: [
              Icon(Icons.history, color: CursorTheme.primary, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Restaurar checkpoint',
                  style: TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se revertirán $_fileCount archivo(s) al estado anterior '
                  'a este cambio. Los archivos creados en este turno se '
                  'eliminarán.',
                  style: const TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _checkpoint.label,
                  style: const TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _checkpoint.files.map((f) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• ${f.relativePath}${f.wasNewFile ? ' (eliminar)' : ''}',
                            style: const TextStyle(
                              color: CursorTheme.textPrimary,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: CursorTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: CursorTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Restore'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _restoring = true);
    try {
      final restore = widget.onRestore ?? CheckpointService.restoreCheckpoint;
      await restore(_checkpoint);
      if (!mounted) return;
      setState(() {
        _restoredLocally = true;
        _restoring = false;
      });
      widget.onRestored?.call();
      AppToast.info(context, 'Checkpoint restaurado ($_fileCount archivo(s))');
    } catch (e) {
      if (!mounted) return;
      setState(() => _restoring = false);
      AppToast.error(context, 'Error al restaurar: $e');
    }
  }
}
