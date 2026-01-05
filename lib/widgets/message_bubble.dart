import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../models/message.dart';
import 'code_viewer.dart';
import 'cursor_theme.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor: const Color(0xFF007ACC),
              child: const Icon(Icons.smart_toy, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? CursorTheme.userMessageBg
                    : CursorTheme.assistantMessageBg,
                borderRadius: BorderRadius.circular(6),
                border: !isUser
                    ? Border.all(color: CursorTheme.assistantMessageBorder, width: 1)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Botón de copiar en la esquina superior derecha
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy, size: 14),
                        color: CursorTheme.textSecondary,
                        iconSize: 14,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: message.content));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Mensaje copiado'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        tooltip: 'Copiar mensaje',
                      ),
                    ],
                  ),
                  // Mostrar imágenes si existen (COMPACTO - tarjetas pequeñas)
                  if (message.imageUrls != null && message.imageUrls!.isNotEmpty)
                    ...message.imageUrls!.map((imagePath) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () {
                            // Mostrar imagen en tamaño completo al tocar
                            showDialog(
                              context: context,
                              builder: (context) => Dialog(
                                backgroundColor: Colors.transparent,
                                child: Stack(
                                  children: [
                                    Center(
                                      child: Image.file(
                                        File(imagePath),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    Positioned(
                                      top: 10,
                                      right: 10,
                                      child: IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white),
                                        onPressed: () => Navigator.of(context).pop(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: CursorTheme.border, width: 1),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.file(
                                File(imagePath),
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 120,
                                    height: 120,
                                    color: Colors.grey[800],
                                    child: const Icon(Icons.broken_image, color: Colors.white70, size: 32),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),

                  // Mostrar ruta de archivo si existe
                  if (message.filePath != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file,
                              size: 16, color: Colors.white70),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              message.filePath!.split('/').last,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Mostrar contenido del mensaje
                  MarkdownBody(
                    data: message.content,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        color: CursorTheme.textPrimary,
                        fontSize: 13,
                        height: 1.5,
                        letterSpacing: 0.1,
                      ),
                      h1: const TextStyle(
                        color: CursorTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      h2: const TextStyle(
                        color: CursorTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      h3: const TextStyle(
                        color: CursorTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      code: const TextStyle(
                        color: CursorTheme.codeText,
                        backgroundColor: CursorTheme.codeBackground,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: CursorTheme.codeBackground,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: CursorTheme.codeBorder,
                          width: 1,
                        ),
                      ),
                      blockquote: const TextStyle(
                        color: CursorTheme.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                      listBullet: const TextStyle(
                        color: CursorTheme.textPrimary,
                      ),
                    ),
                    builders: {
                      'code': CodeBlockBuilder(),
                    },
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey[700],
              child: const Icon(Icons.person, size: 18, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent;
    final language = element.attributes['class']?.replaceAll('language-', '') ?? '';

    return _CompactCodeBlock(code: code, language: language);
  }
}

class _CompactCodeBlock extends StatefulWidget {
  final String code;
  final String language;

  const _CompactCodeBlock({
    required this.code,
    required this.language,
  });

  @override
  State<_CompactCodeBlock> createState() => _CompactCodeBlockState();
}

class _CompactCodeBlockState extends State<_CompactCodeBlock> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final lines = widget.code.split('\n');
    final previewLines = lines.take(3).join('\n');
    final hasMore = lines.length > 3;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: CursorTheme.codeBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: CursorTheme.codeBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header compacto
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: CursorTheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border(
                  bottom: BorderSide(color: CursorTheme.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 14,
                    color: CursorTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  if (widget.language.isNotEmpty)
                    Text(
                      widget.language.toUpperCase(),
                      style: const TextStyle(
                        color: CursorTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  if (widget.language.isNotEmpty) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${lines.length} líneas',
                      style: const TextStyle(
                        color: CursorTheme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 12),
                    color: CursorTheme.textSecondary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.code));
                    },
                    tooltip: 'Copiar',
                  ),
                ],
              ),
            ),
          ),
          // Contenido - compacto o expandido
          AnimatedCrossFade(
            firstChild: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                previewLines,
                style: const TextStyle(
                  color: CursorTheme.codeText,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            secondChild: Padding(
              padding: const EdgeInsets.all(8),
              child: CodeViewer(code: widget.code, language: widget.language),
            ),
            crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

