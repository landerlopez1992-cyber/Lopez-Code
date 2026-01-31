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

  Widget _buildMessageContent(BuildContext context, bool isUser) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
                Icon(Icons.insert_drive_file,
                    size: 16, color: isUser ? Colors.white70 : CursorTheme.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    message.filePath!.split('/').last,
                    style: TextStyle(
                      color: isUser ? Colors.white70 : CursorTheme.textSecondary,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        // Mostrar contenido del mensaje - texto fluido sin contenedor para asistente
        MarkdownBody(
          data: message.content,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              color: isUser ? Colors.white : CursorTheme.textPrimary,
              fontSize: 13,
              height: 1.6, // Mejor interlineado
              letterSpacing: 0,
            ),
            h1: TextStyle(
              color: isUser ? Colors.white : CursorTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            h2: TextStyle(
              color: isUser ? Colors.white : CursorTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            h3: TextStyle(
              color: isUser ? Colors.white : CursorTheme.textPrimary,
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
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: CursorTheme.codeBorder.withOpacity(0.5),
                width: 0.5,
              ),
            ),
            blockquote: TextStyle(
              color: isUser ? Colors.white70 : CursorTheme.textSecondary,
              fontStyle: FontStyle.italic,
            ),
            listBullet: TextStyle(
              color: isUser ? Colors.white : CursorTheme.textPrimary,
            ),
          ),
          builders: {
            'code': CodeBlockBuilder(),
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12), // Espacio más compacto como Cursor
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            // Icono del proyecto (robot azul)
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFF007ACC),
                shape: BoxShape.circle,
              ),
              child: CustomPaint(
                painter: RobotIconPainter(),
              ),
            ),
            const SizedBox(width: 12), // Más espacio como Cursor
          ],
          Flexible(
            child: isUser 
                ? Container(
                    constraints: const BoxConstraints(maxWidth: 900),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: CursorTheme.userMessageBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _buildMessageContent(context, isUser),
                  )
                : _buildMessageContent(context, isUser),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 12, // Mismo tamaño que el avatar del asistente
              backgroundColor: const Color(0xFF37373D), // Color más consistente con el tema
              child: const Icon(Icons.person, size: 14, color: Colors.white),
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

// Custom painter para el icono de código (corchetes angulares <>)
class RobotIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    
    // Tamaño de los corchetes
    final bracketSize = size.width * 0.25; // 25% del ancho
    final bracketHeight = size.height * 0.4; // 40% de la altura
    final spacing = size.width * 0.15; // Espacio entre corchetes
    
    // Corchete izquierdo <
    final leftBracketPath = Path()
      ..moveTo(centerX - spacing / 2, centerY)
      ..lineTo(centerX - spacing / 2 - bracketSize, centerY - bracketHeight / 2)
      ..lineTo(centerX - spacing / 2 - bracketSize, centerY + bracketHeight / 2)
      ..lineTo(centerX - spacing / 2, centerY);
    canvas.drawPath(leftBracketPath, paint);
    
    // Corchete derecho >
    final rightBracketPath = Path()
      ..moveTo(centerX + spacing / 2, centerY)
      ..lineTo(centerX + spacing / 2 + bracketSize, centerY - bracketHeight / 2)
      ..lineTo(centerX + spacing / 2 + bracketSize, centerY + bracketHeight / 2)
      ..lineTo(centerX + spacing / 2, centerY);
    canvas.drawPath(rightBracketPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    final firstLine = lines.isNotEmpty ? lines[0].trim() : '';
    final previewText = firstLine.length > 60 ? '${firstLine.substring(0, 60)}...' : firstLine;
    final hasMore = lines.length > 1 || widget.code.length > 100;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8), // Separación como Cursor
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), // Fondo oscuro
        borderRadius: BorderRadius.circular(6), // Bordes más redondeados
        border: Border.all(
          color: const Color(0xFF3E3E42).withOpacity(0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header ultra compacto estilo Cursor
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF252526), // Fondo del header
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(6),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                      size: 14,
                      color: CursorTheme.textSecondary.withOpacity(0.8),
                    ),
                    const SizedBox(width: 6),
                    if (widget.language.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF37373D),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          widget.language.toUpperCase(),
                          style: const TextStyle(
                            color: CursorTheme.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        _isExpanded 
                          ? '${lines.length} líneas' 
                          : previewText,
                        style: TextStyle(
                          color: _isExpanded 
                            ? CursorTheme.textSecondary 
                            : CursorTheme.codeText,
                          fontSize: 12,
                          fontFamily: _isExpanded ? null : 'monospace',
                          height: 1.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!_isExpanded && hasMore)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '...',
                          style: TextStyle(
                            color: CursorTheme.textSecondary.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: widget.code));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Código copiado'),
                              duration: Duration(milliseconds: 800),
                              backgroundColor: CursorTheme.surface,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.copy,
                            size: 14,
                            color: CursorTheme.textSecondary.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Contenido - solo mostrar si está expandido
          if (_isExpanded)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFF3E3E42), width: 0.5),
                ),
              ),
              child: CodeViewer(code: widget.code, language: widget.language),
            ),
        ],
      ),
    );
  }
}

