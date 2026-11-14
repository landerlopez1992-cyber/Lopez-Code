import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cursor_theme.dart';

enum InlineEditPhase { prompt, generating, preview }

/// Barra flotante Inline Edit (Cmd+K) estilo Cursor.
class InlineEditBar extends StatefulWidget {
  final InlineEditPhase phase;
  final String originalCode;
  final String? proposedCode;
  final String? errorMessage;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final ValueChanged<String> onSubmitInstruction;

  const InlineEditBar({
    super.key,
    required this.phase,
    required this.originalCode,
    required this.onCancel,
    required this.onAccept,
    required this.onSubmitInstruction,
    this.proposedCode,
    this.errorMessage,
  });

  @override
  State<InlineEditBar> createState() => _InlineEditBarState();
}

class _InlineEditBarState extends State<InlineEditBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.phase == InlineEditPhase.prompt) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant InlineEditBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase == InlineEditPhase.prompt &&
        oldWidget.phase != InlineEditPhase.prompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmitInstruction(text);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
          if (widget.phase == InlineEditPhase.preview) {
            widget.onAccept();
          } else if (widget.phase == InlineEditPhase.prompt) {
            _submit();
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (widget.phase == InlineEditPhase.preview) {
            widget.onAccept();
          } else if (widget.phase == InlineEditPhase.prompt) {
            _submit();
          }
        },
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: CursorTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: CursorTheme.primary.withValues(alpha: 0.7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              if (widget.phase == InlineEditPhase.prompt ||
                  widget.phase == InlineEditPhase.generating)
                _buildPromptRow(),
              if (widget.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    widget.errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFF14C4C),
                      fontSize: 11,
                    ),
                  ),
                ),
              if (widget.phase == InlineEditPhase.preview) ...[
                _buildDiffPreview(),
                _buildAcceptRejectRow(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final label = switch (widget.phase) {
      InlineEditPhase.prompt => 'Inline Edit',
      InlineEditPhase.generating => 'Generating…',
      InlineEditPhase.preview => 'Review changes',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      child: Row(
        children: [
          const Icon(Icons.auto_fix_high, size: 14, color: CursorTheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: CursorTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            color: CursorTheme.textSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Cancel (Esc)',
            onPressed: widget.onCancel,
          ),
        ],
      ),
    );
  }

  Widget _buildPromptRow() {
    final generating = widget.phase == InlineEditPhase.generating;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: !generating,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 13,
              ),
              decoration: const InputDecoration(
                isDense: true,
                hintText:
                    'Describe el cambio para este bloque (ej. añade manejo de errores, extrae a widget)...',
                hintStyle: TextStyle(
                  color: CursorTheme.textDisabled,
                  fontSize: 12,
                ),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          if (generating)
            const Padding(
              padding: EdgeInsets.only(top: 8, right: 4),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _submit,
              style: TextButton.styleFrom(
                foregroundColor: CursorTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Generar', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildDiffPreview() {
    final proposed = widget.proposedCode ?? '';
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: CursorTheme.codeBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: CursorTheme.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '− original',
              style: TextStyle(
                color: Color(0xFFF14C4C),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            SelectableText(
              widget.originalCode,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.4,
                color: const Color(0xFFF14C4C).withValues(alpha: 0.85),
                backgroundColor: const Color(0x33F14C4C),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '+ proposed',
              style: TextStyle(
                color: Color(0xFF89D185),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            SelectableText(
              proposed,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.4,
                color: const Color(0xFF89D185).withValues(alpha: 0.95),
                backgroundColor: const Color(0x3389D185),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcceptRejectRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          Text(
            'Cmd/Ctrl+Enter aceptar · Esc rechazar',
            style: TextStyle(
              color: CursorTheme.textDisabled,
              fontSize: 10,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: widget.onCancel,
            child: const Text('Rechazar', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          ElevatedButton(
            onPressed: widget.onAccept,
            style: ElevatedButton.styleFrom(
              backgroundColor: CursorTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text('Aceptar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
