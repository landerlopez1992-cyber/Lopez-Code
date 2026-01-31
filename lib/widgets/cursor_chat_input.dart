import 'package:flutter/material.dart';
import 'cursor_theme.dart';

class CursorChatInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachFile;
  final bool isLoading;
  final VoidCallback? onStop;
  final String? placeholder;

  const CursorChatInput({
    super.key,
    required this.controller,
    required this.onSend,
    this.onAttachImage,
    this.onAttachFile,
    this.isLoading = false,
    this.onStop,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Más padding como Cursor
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        border: Border(
          top: BorderSide(color: CursorTheme.border, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Botones de adjuntar (más discretos como Cursor)
          if (onAttachImage != null || onAttachFile != null) ...[
            if (onAttachImage != null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onAttachImage,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.image_outlined,
                      size: 18,
                      color: CursorTheme.textSecondary.withOpacity(0.8),
                    ),
                  ),
                ),
              ),
            if (onAttachFile != null)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onAttachFile,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.insert_drive_file_outlined,
                      size: 18,
                      color: CursorTheme.textSecondary.withOpacity(0.8),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 6),
          ],
          // Campo de texto (estilo Cursor)
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 150),
              decoration: BoxDecoration(
                color: CursorTheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: CursorTheme.border.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: controller,
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 13,
                  height: 1.5, // Mejor interlineado
                ),
                maxLines: null,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: placeholder ?? 'Plan, @ for context, / for commands',
                  hintStyle: TextStyle(
                    color: CursorTheme.textDisabled.withOpacity(0.7),
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Botón enviar/stop (estilo Cursor más pulido)
          Material(
            color: isLoading 
                ? Colors.red.withOpacity(0.9)
                : CursorTheme.primary,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: isLoading 
                  ? (onStop ?? () {})
                  : onSend,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                child: isLoading
                    ? const Icon(Icons.stop, size: 18, color: Colors.white)
                    : const Icon(Icons.send, size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


