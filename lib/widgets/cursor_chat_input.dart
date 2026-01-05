import 'package:flutter/material.dart';
import 'cursor_theme.dart';

class CursorChatInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachFile;
  final bool isLoading;
  final String? placeholder;

  const CursorChatInput({
    super.key,
    required this.controller,
    required this.onSend,
    this.onAttachImage,
    this.onAttachFile,
    this.isLoading = false,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        border: Border(
          top: BorderSide(color: CursorTheme.border, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Botones de adjuntar (compactos)
          if (onAttachImage != null || onAttachFile != null) ...[
            if (onAttachImage != null)
              IconButton(
                icon: const Icon(Icons.image_outlined, size: 18),
                color: CursorTheme.textSecondary,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onAttachImage,
                tooltip: 'Imagen',
              ),
            if (onAttachFile != null)
              IconButton(
                icon: const Icon(Icons.insert_drive_file_outlined, size: 18),
                color: CursorTheme.textSecondary,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onAttachFile,
                tooltip: 'Archivo',
              ),
            const SizedBox(width: 4),
          ],
          // Campo de texto
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: CursorTheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: CursorTheme.border, width: 1),
              ),
              child: TextField(
                controller: controller,
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 13,
                  height: 1.4,
                ),
                maxLines: null,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: placeholder ?? 'Plan, @ for context, / for commands',
                  hintStyle: const TextStyle(
                    color: CursorTheme.textDisabled,
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Botón enviar (compacto)
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isLoading ? CursorTheme.textDisabled : CursorTheme.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: IconButton(
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send, size: 16, color: Colors.white),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: isLoading ? null : onSend,
              tooltip: 'Enviar',
            ),
          ),
        ],
      ),
    );
  }
}


