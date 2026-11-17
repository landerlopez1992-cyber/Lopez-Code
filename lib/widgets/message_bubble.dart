import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../models/agent_live_step.dart';
import '../models/message.dart';
import '../models/pending_action.dart';
import 'app_toast.dart';
import 'cursor_theme.dart';
import 'pending_actions_card.dart';

/// Burbuja de chat estilo Cursor: copy / edit / resend en mensajes del usuario.
class MessageBubble extends StatefulWidget {
  final Message message;
  final Function(List<PendingAction>)? onAcceptActions;
  final Function()? onRejectActions;

  /// Reenviar este mensaje (trunca el hilo desde aquí y vuelve a enviar).
  final VoidCallback? onResend;

  /// Editar: carga el texto en el composer (y opcionalmente trunca el hilo).
  final VoidCallback? onEdit;

  /// El agente agotó sus pasos: reanudar otra tanda.
  final VoidCallback? onContinueTask;

  /// Abre un archivo en la pestaña Code al pulsar su tarjeta/chip.
  final ValueChanged<String>? onOpenFile;

  const MessageBubble({
    super.key,
    required this.message,
    this.onAcceptActions,
    this.onRejectActions,
    this.onResend,
    this.onEdit,
    this.onContinueTask,
    this.onOpenFile,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _hovered = false;
  bool _expandedLong = false;
  static const int _collapseAfterChars = 2800;
  /// Burbuja azul del usuario: corta agresivo para no comerse el chat.
  static const int _userCollapseAfterChars = 140;

  Message get message => widget.message;

  bool _userMessageIsCollapsible(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;
    return trimmed.length > _userCollapseAfterChars ||
        trimmed.contains('\n');
  }

  String _userCollapsedPreview(String body) {
    final firstLine = body.trim().split('\n').first.trim();
    if (firstLine.length <= _userCollapseAfterChars) return firstLine;
    return '${firstLine.substring(0, _userCollapseAfterChars).trimRight()}…';
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final userCollapsible =
        isUser && _userMessageIsCollapsible(message.content);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: EdgeInsets.only(bottom: isUser ? 14 : 10),
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Asistente: texto directo sobre el fondo (sin avatar/caja).
            // Usuario: burbuja alineada a la derecha.
            Flexible(
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: userCollapsible
                            ? () => setState(
                                  () => _expandedLong = !_expandedLong,
                                )
                            : null,
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topLeft,
                          child: Container(
                            width: isUser ? null : double.infinity,
                            constraints: const BoxConstraints(maxWidth: 900),
                            padding: EdgeInsets.fromLTRB(
                              isUser ? 14 : 4,
                              isUser ? 10 : 2,
                              isUser
                                  ? (userCollapsible ? 44 : 36)
                                  : 28,
                              isUser ? 10 : 2,
                            ),
                            decoration: isUser
                                ? BoxDecoration(
                                    color: CursorTheme.userMessageBg,
                                    borderRadius: BorderRadius.circular(8),
                                  )
                                : null,
                            child: _buildMessageContent(context, isUser),
                          ),
                        ),
                      ),
                      if (userCollapsible)
                        Positioned(
                          top: 6,
                          right: 28,
                          child: IgnorePointer(
                            child: Icon(
                              _expandedLong
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 18,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      Positioned(
                        top: isUser ? 6 : 0,
                        right: isUser ? 6 : 0,
                        child: _IconAction(
                          icon: Icons.copy_outlined,
                          tooltip: 'Copiar',
                          color: isUser
                              ? Colors.white70
                              : CursorTheme.textSecondary,
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: message.content),
                            );
                            AppToast.show(
                              context,
                              message: 'Copiado',
                              icon: Icons.content_copy,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  if (!isUser && widget.onContinueTask != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4),
                      child: _ContinueTaskButton(
                        onPressed: widget.onContinueTask!,
                      ),
                    ),
                  // Toolbar tipo Cursor bajo el mensaje del usuario.
                  if (isUser &&
                      (_hovered ||
                          message.isCancelled ||
                          widget.onEdit != null ||
                          widget.onResend != null))
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 2),
                      child: _UserActionBar(
                        isCancelled: message.isCancelled,
                        onCopy: () {
                          Clipboard.setData(
                            ClipboardData(text: message.content),
                          );
                          AppToast.show(context, message: 'Copiado');
                        },
                        onEdit: widget.onEdit,
                        onResend: widget.onResend,
                      ),
                    ),
                ],
              ),
            ),
            if (isUser) ...[
              const SizedBox(width: 10),
              const CircleAvatar(
                radius: 14,
                backgroundColor: Color(0xFF37373D),
                child: Icon(Icons.person, size: 16, color: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context, bool isUser) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.pendingActions != null &&
            message.pendingActions!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PendingActionsCard(
              pendingActions: message.pendingActions!,
              onAccept: widget.onAcceptActions ?? (_) {},
              onReject: widget.onRejectActions ?? () {},
            ),
          ),
        if (message.imageUrls != null && message.imageUrls!.isNotEmpty)
          ...message.imageUrls!.map((imagePath) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
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
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
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
                    border: Border.all(color: CursorTheme.border),
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
                          child: const Icon(
                            Icons.broken_image,
                            color: Colors.white70,
                            size: 32,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          }),
        if (message.filePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  Icons.insert_drive_file,
                  size: 16,
                  color: isUser ? Colors.white70 : CursorTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    message.filePath!.split('/').last,
                    style: TextStyle(
                      color:
                          isUser ? Colors.white70 : CursorTheme.textSecondary,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (message.isCancelled)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Cancelado',
              style: TextStyle(
                color: isUser ? Colors.orange.shade200 : Colors.orange,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Builder(
          builder: (context) {
            final raw = message.content;
            final split = !isUser
                ? _splitTimelineAndBody(raw)
                : (steps: const <String>[], body: raw);
            final bodyRaw = split.body;
            final userCollapsible =
                isUser && _userMessageIsCollapsible(bodyRaw);
            final assistantLong = !isUser &&
                bodyRaw.length > _collapseAfterChars;
            final isCollapsible = userCollapsible || assistantLong;
            final String shown;
            if (!isCollapsible || _expandedLong) {
              shown = bodyRaw;
            } else if (userCollapsible) {
              shown = _userCollapsedPreview(bodyRaw);
            } else {
              shown =
                  '${bodyRaw.substring(0, _collapseAfterChars)}\n\n…';
            }
            final live = message.liveSteps;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (live != null && live.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: shown.isNotEmpty ? 10 : 0,
                    ),
                    child: _CursorLiveStepsColumn(
                      steps: live,
                      hasAnswerBody: shown.isNotEmpty,
                      onOpenFile: widget.onOpenFile,
                    ),
                  )
                else if (split.steps.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: shown.isNotEmpty ? 10 : 0,
                    ),
                    child: _AgentTimelineCard(
                      steps: split.steps,
                      hasAnswerBody: shown.isNotEmpty,
                      onOpenFile: widget.onOpenFile,
                    ),
                  ),
                if (shown.isNotEmpty)
                  ..._buildBodySegments(context, shown, isUser),
                if (assistantLong)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _expandedLong = !_expandedLong),
                      child: Text(
                        _expandedLong
                            ? 'Mostrar menos'
                            : 'Mostrar más (${bodyRaw.length} chars)',
                        style: const TextStyle(
                          color: CursorTheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                if (userCollapsible && !_expandedLong)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Clic para expandir',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<Widget> _buildBodySegments(
    BuildContext context,
    String shown,
    bool isUser,
  ) {
    final styleSheet = MarkdownStyleSheet(
      p: TextStyle(
        color: isUser ? Colors.white : CursorTheme.textPrimary,
        fontSize: 13,
        height: 1.55,
      ),
      em: TextStyle(
        color: isUser ? Colors.white70 : const Color(0xFF8B8B8B),
        fontSize: 12,
        fontStyle: FontStyle.normal,
        fontWeight: FontWeight.w400,
        height: 1.35,
        letterSpacing: 0.1,
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
      code: TextStyle(
        color: isUser ? Colors.white : const Color(0xFFE6E6E6),
        backgroundColor:
            isUser ? Colors.black26 : const Color(0xFF2B2D31),
        fontFamily: 'Menlo',
        fontSize: 12,
        height: 1.35,
      ),
      codeblockDecoration: BoxDecoration(
        color: CursorTheme.codeBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: CursorTheme.codeBorder.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      blockquote: TextStyle(
        color: isUser ? Colors.white70 : const Color(0xFF8E8E93),
        fontSize: 12,
        fontStyle: FontStyle.normal,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CursorTheme.border.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
      ),
      listBullet: TextStyle(
        color: isUser ? Colors.white : CursorTheme.textPrimary,
      ),
    );

    final widgets = <Widget>[];
    final parts = shown.split('```');
    for (var i = 0; i < parts.length; i++) {
      final segment = parts[i];
      if (i.isOdd) {
        // Bloque ```lang\ncode``` → tarjeta colapsada compacta estilo Cursor.
        final firstNl = segment.indexOf('\n');
        final lang = firstNl >= 0 ? segment.substring(0, firstNl).trim() : '';
        final code = firstNl >= 0 ? segment.substring(firstNl + 1) : segment;
        if (code.trim().isNotEmpty || lang.isNotEmpty) {
          widgets.add(_CompactCodeBlock(code: code, language: lang));
        }
        continue;
      }

      final prose = segment.trim();
      if (prose.isEmpty) continue;
      widgets.add(
        _SafeMarkdownBody(
          data: _sanitizeMarkdownForBubble(prose),
          fallbackText: _cleanFallbackText(prose),
          isUser: isUser,
          styleSheet: styleSheet,
          builders: const {},
        ),
      );
    }
    return widgets;
  }

  static String _cleanFallbackText(String text) {
    return text.replaceAllMapped(
      RegExp(r'\\([_*`\[\]])'),
      (m) => m.group(1)!,
    );
  }

  /// Separa los pasos técnicos iniciales (`• Thought briefly...`) del texto
  /// conversacional para mostrarlos en una tarjeta compacta aparte.
  static ({List<String> steps, String body}) _splitTimelineAndBody(
    String raw,
  ) {
    final lines = raw.split('\n');
    final steps = <String>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (steps.isEmpty) {
          i++;
          continue;
        }
        // Una línea vacía seguida de más pasos `• ...` sigue siendo timeline.
        if (i + 1 < lines.length && lines[i + 1].trim().startsWith('• ')) {
          i++;
          continue;
        }
        i++;
        break;
      }

      if (trimmed.startsWith('• ') || trimmed.startsWith('Applying ')) {
        // Soportar mensajes viejos donde varios pasos venían en 1 línea con ' · '.
        final segments = trimmed
            .split(RegExp(r'\s+·\s+(?=[A-Z]|Applying|Thought|Searching|Exploring|Explored|Editing|Edited|Running|Ran|Analyze|Failed|Waiting|Completed)'))
            .map((s) => s.replaceFirst(RegExp(r'^•\s*'), '').trim())
            .where((s) => s.isNotEmpty)
            .toList();
        for (final seg in segments) {
          steps.add(_cleanFallbackText(seg));
        }
        i++;
        // Consumir línea de detalle indentada si existe.
        if (i < lines.length &&
            lines[i].startsWith('  ') &&
            !lines[i].trim().startsWith('•')) {
          final detail = _cleanFallbackText(lines[i].trim());
          if (detail.isNotEmpty && steps.isNotEmpty) {
            steps[steps.length - 1] = '${steps.last} — $detail';
          }
          i++;
        }
        continue;
      }
      break;
    }

    if (steps.isEmpty) {
      return (steps: const <String>[], body: raw);
    }
    final body = lines.sublist(i).join('\n').trimLeft();
    return (steps: steps, body: body);
  }

  /// Evita énfasis markdown roto (p.ej. rutas `foo_bar.dart` / `_inlines`).
  ///
  /// Fuera de fences ```…``` e inline `…`, escapa `_` y `*` huérfanos sin
  /// romper `file_name.dart` dentro de backticks.
  static String _sanitizeMarkdownForBubble(String input) {
    final parts = input.split('```');
    final out = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      if (i.isOdd) {
        out.write('```');
        out.write(parts[i]);
        out.write('```');
        continue;
      }
      // Preservar backticks simples `...` sin escapar sus `_` internos.
      final inlineParts = parts[i].split('`');
      for (var j = 0; j < inlineParts.length; j++) {
        if (j.isOdd && j + 1 < inlineParts.length) {
          out.write('`');
          out.write(inlineParts[j]);
          out.write('`');
        } else if (j.isOdd) {
          // Backtick sin cerrar al final (streaming): escaparlo.
          out.write('\\`');
          out.write(_escapeRiskyInlineMarkers(inlineParts[j]));
        } else {
          out.write(_escapeRiskyInlineMarkers(inlineParts[j]));
        }
      }
    }
    return out.toString();
  }

  static String _escapeRiskyInlineMarkers(String text) {
    // 1) Escapar todos los _ no escapados (rutas, snake_case, cursiva rota).
    var t = text.replaceAllMapped(
      RegExp(r'(?<!\\)_'),
      (_) => '\\_',
    );
    // 2) Escapar * sueltos que no formen **bold** válido (p. ej. `*/` o `**sin cerrar`).
    t = t.replaceAllMapped(RegExp(r'\*\*([^*\n]+)\*\*|\*'), (m) {
      final s = m.group(0)!;
      if (s.startsWith('**') && s.endsWith('**') && s.length > 4) return s;
      return '\\*';
    });
    return t;
  }
}

/// Markdown a prueba de asserts (`_inlines.isEmpty`) de flutter_markdown.
///
/// Parsea con [MarkdownBuilder] en try/catch: si el AST deja inlines abiertos,
/// muestra texto plano en vez de tumbar toda la app.
class _SafeMarkdownBody extends StatefulWidget {
  final String data;
  final String fallbackText;
  final bool isUser;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;

  const _SafeMarkdownBody({
    required this.data,
    required this.fallbackText,
    required this.isUser,
    required this.styleSheet,
    required this.builders,
  });

  @override
  State<_SafeMarkdownBody> createState() => _SafeMarkdownBodyState();
}

class _SafeMarkdownBodyState extends State<_SafeMarkdownBody>
    implements MarkdownBuilderDelegate {
  List<Widget> _children = const [];
  bool _useFallback = false;
  final List<GestureRecognizer> _recognizers = [];
  String? _parsedData;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parseIfNeeded(force: true);
  }

  @override
  void didUpdateWidget(covariant _SafeMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.styleSheet != widget.styleSheet) {
      _parseIfNeeded(force: true);
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _parseIfNeeded({bool force = false}) {
    if (!force && _parsedData == widget.data && !_useFallback) return;
    _disposeRecognizers();
    try {
      final fallbackStyle = MarkdownStyleSheet.fromTheme(Theme.of(context));
      final styleSheet = fallbackStyle.merge(widget.styleSheet);
      final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      );
      final lines = const LineSplitter().convert(widget.data);
      final nodes = document.parseLines(lines);
      // flutter_markdown 0.6.x: si selectable=true y onSelectionChanged es
      // null, al arrastrar el mouse hace onSelectionChanged!(...) y tumba
      // toda la app (_TypeError). Siempre pasar un no-op.
      final builder = MarkdownBuilder(
        delegate: this,
        selectable: true,
        styleSheet: styleSheet,
        imageDirectory: null,
        imageBuilder: null,
        checkboxBuilder: null,
        bulletBuilder: null,
        builders: widget.builders,
        paddingBuilders: const {},
        fitContent: true,
        listItemCrossAxisAlignment:
            MarkdownListItemCrossAxisAlignment.baseline,
        onSelectionChanged: (_, __, ___) {},
        onTapText: () {},
        softLineBreak: false,
      );
      final built = builder.build(nodes);
      _children = built;
      _useFallback = false;
      _parsedData = widget.data;
    } catch (e, st) {
      debugPrint('⚠️ Markdown seguro → fallback ($e)\n$st');
      _children = const [];
      _useFallback = true;
      _parsedData = widget.data;
    }
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final target = (href != null && href.trim().isNotEmpty) ? href.trim() : text.trim();
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        unawaited(_openExternalLink(target));
      };
    _recognizers.add(recognizer);
    return recognizer;
  }

  Future<void> _openExternalLink(String raw) async {
    if (raw.isEmpty) return;
    final hasScheme = raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('mailto:');
    final normalized = hasScheme
        ? raw
        : (raw.contains('.') && !raw.startsWith('/'))
            ? 'https://$raw'
            : raw;
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'mailto')) {
      return;
    }
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        AppToast.show(context, message: 'No se pudo abrir: $normalized');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, message: 'No se pudo abrir el enlace');
      }
    }
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) {
    final cleaned = code.replaceAll(RegExp(r'\n$'), '');
    return TextSpan(style: styleSheet.code, text: cleaned);
  }

  @override
  Widget build(BuildContext context) {
    if (_useFallback) {
      return SelectableText(
        widget.fallbackText,
        style: TextStyle(
          color: widget.isUser ? Colors.white : CursorTheme.textPrimary,
          fontSize: 13,
          height: 1.55,
        ),
      );
    }
    if (_children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _children,
    );
  }
}

class _UserActionBar extends StatelessWidget {
  final bool isCancelled;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onResend;

  const _UserActionBar({
    required this.isCancelled,
    required this.onCopy,
    this.onEdit,
    this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: CursorTheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: CursorTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconAction(
            icon: Icons.copy_outlined,
            tooltip: 'Copiar',
            onTap: onCopy,
          ),
          if (onEdit != null)
            _IconAction(
              icon: Icons.edit_outlined,
              tooltip: 'Editar',
              onTap: onEdit!,
            ),
          if (onResend != null)
            _IconAction(
              icon: Icons.refresh,
              tooltip: isCancelled ? 'Reenviar' : 'Reenviar desde aquí',
              color: isCancelled ? Colors.orangeAccent : null,
              onTap: onResend!,
            ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              icon,
              size: 14,
              color: color ?? CursorTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueTaskButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ContinueTaskButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: CursorTheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: CursorTheme.border),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_arrow_rounded,
                size: 15,
                color: CursorTheme.primary,
              ),
              SizedBox(width: 4),
              Text(
                'Continuar tarea',
                style: TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renderiza solo bloques ```fenced``` como tarjeta con botón copiar.
/// Los backticks simples (`inline`) los deja MarkdownBody con estilo `code`.
class FencedCodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // <pre><code class="language-xxx">...</code></pre>
    String language = '';
    var code = element.textContent;
    if (element.children != null) {
      for (final child in element.children!) {
        if (child is md.Element && child.tag == 'code') {
          language =
              child.attributes['class']?.replaceAll('language-', '') ?? '';
          code = child.textContent;
          break;
        }
      }
    }
    return _CompactCodeBlock(code: code, language: language);
  }
}

/// @deprecated Usar [FencedCodeBlockBuilder]. Conservado por compatibilidad.
class CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent;
    final language =
        element.attributes['class']?.replaceAll('language-', '') ?? '';
    final isFenced =
        language.isNotEmpty || code.contains('\n') || code.length > 80;
    if (!isFenced) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: CursorTheme.codeBackground.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          code,
          style: const TextStyle(
            color: CursorTheme.codeText,
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.35,
          ),
        ),
      );
    }
    return _CompactCodeBlock(code: code, language: language);
  }
}

class _CompactCodeBlock extends StatefulWidget {
  final String code;
  final String language;

  const _CompactCodeBlock({required this.code, required this.language});

  @override
  State<_CompactCodeBlock> createState() => _CompactCodeBlockState();
}

class _CompactCodeBlockState extends State<_CompactCodeBlock> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final trimmed = widget.code.trimRight();
    final lines = trimmed.isEmpty ? const <String>[] : trimmed.split('\n');
    final collapsible = lines.length > 2;
    final showCode = !collapsible || _isExpanded;
    final langLabel =
        widget.language.isEmpty ? 'código' : widget.language.toLowerCase();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1B1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CursorTheme.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: collapsible
                ? () => setState(() => _isExpanded = !_isExpanded)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.code_rounded,
                    size: 14,
                    color: CursorTheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    lines.isEmpty
                        ? langLabel
                        : '$langLabel · ${lines.length} ${lines.length == 1 ? 'línea' : 'líneas'}',
                    style: const TextStyle(
                      color: CursorTheme.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (collapsible)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isExpanded ? 'Ocultar' : 'Ver código',
                            style: const TextStyle(
                              color: CursorTheme.primary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Icon(
                            _isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 15,
                            color: CursorTheme.primary,
                          ),
                        ],
                      ),
                    ),
                  IconButton(
                    tooltip: 'Copiar código',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.code));
                      AppToast.show(context, message: 'Código copiado');
                    },
                    icon: const Icon(Icons.copy_outlined, size: 13),
                    color: CursorTheme.textSecondary,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showCode) ...[
            const Divider(height: 1, color: CursorTheme.border),
            Padding(
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                trimmed,
                style: const TextStyle(
                  color: CursorTheme.codeText,
                  fontFamily: 'Menlo',
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta compacta con las acciones y archivos tocados por el agente.
/// Mantiene la conversación limpia y deja expandir los detalles al hacer clic.
class _AgentTimelineCard extends StatefulWidget {
  final List<String> steps;
  final bool hasAnswerBody;
  final ValueChanged<String>? onOpenFile;

  const _AgentTimelineCard({
    required this.steps,
    required this.hasAnswerBody,
    this.onOpenFile,
  });

  @override
  State<_AgentTimelineCard> createState() => _AgentTimelineCardState();
}

class _AgentTimelineCardState extends State<_AgentTimelineCard> {
  bool _expanded = false;

  static final RegExp _editedFileRe = RegExp(
    r'^(?:Edited|Created|Wrote|Editing|Writing|Creating|Explored|Exploring)\s+([^\s]+?)(?:\s+([+-]\d+\s+[+-]\d+))?$',
  );

  List<({String fullPath, String fileName, String? stats, bool isEdit})>
      _extractFileBadges() {
    final byPath = <String,
        ({String fullPath, String fileName, String? stats, bool isEdit})>{};
    for (final step in widget.steps) {
      final m = _editedFileRe.firstMatch(step.trim());
      if (m == null) continue;
      final fullPath = m.group(1)!;
      if (fullPath == 'proyecto' ||
          fullPath == 'file' ||
          fullPath.startsWith('http')) {
        continue;
      }
      final isEdit = step.startsWith('Edited') ||
          step.startsWith('Created') ||
          step.startsWith('Wrote') ||
          step.startsWith('Editing') ||
          step.startsWith('Writing') ||
          step.startsWith('Creating');
      final stats = m.group(2);
      final name = fullPath.split('/').last;
      final prev = byPath[fullPath];
      // Preferir el estado de edición sobre lectura.
      if (prev == null || (isEdit && !prev.isEdit) || stats != null) {
        byPath[fullPath] = (
          fullPath: fullPath,
          fileName: name,
          stats: stats ?? prev?.stats,
          isEdit: isEdit || (prev?.isEdit ?? false),
        );
      }
    }
    return byPath.values.toList();
  }

  IconData _iconForStep(String step) {
    final s = step.toLowerCase();
    if (s.startsWith('edited') ||
        s.startsWith('editing') ||
        s.startsWith('created') ||
        s.startsWith('writing')) {
      return Icons.edit_outlined;
    }
    if (s.startsWith('explored') || s.startsWith('exploring')) {
      return Icons.description_outlined;
    }
    if (s.startsWith('searching') || s.startsWith('searched')) {
      return Icons.search_rounded;
    }
    if (s.startsWith('running') || s.startsWith('ran')) {
      return Icons.terminal_rounded;
    }
    if (s.startsWith('analyze')) return Icons.check_circle_outline;
    if (s.startsWith('failed')) return Icons.error_outline;
    return Icons.bolt_rounded;
  }

  String? _filePathInStep(String step) {
    final m = _editedFileRe.firstMatch(step.trim());
    if (m == null) return null;
    final p = m.group(1)!;
    return (p == 'proyecto' || p == 'file') ? null : p;
  }

  @override
  Widget build(BuildContext context) {
    final badges = _extractFileBadges();
    final editedBadges = badges.where((b) => b.isEdit).toList();
    final shownBadges = editedBadges.isNotEmpty ? editedBadges : badges;
    final latestStep = widget.steps.isNotEmpty ? widget.steps.last : '';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1D20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CursorTheme.border.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    widget.hasAnswerBody
                        ? Icons.check_circle_outline
                        : Icons.auto_awesome,
                    size: 13,
                    color: widget.hasAnswerBody
                        ? const Color(0xFF3FB950)
                        : CursorTheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.hasAnswerBody
                          ? '${widget.steps.length} ${widget.steps.length == 1 ? 'acción realizada' : 'acciones realizadas'}'
                          : latestStep,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CursorTheme.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _expanded ? 'Ocultar' : 'Detalles',
                    style: const TextStyle(
                      color: CursorTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 15,
                    color: CursorTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (shownBadges.isNotEmpty && !_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final b in shownBadges.take(4))
                    InkWell(
                      onTap: widget.onOpenFile != null
                          ? () => widget.onOpenFile!(b.fullPath)
                          : null,
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25262B),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: CursorTheme.border.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              b.isEdit
                                  ? Icons.edit_note_rounded
                                  : Icons.insert_drive_file_outlined,
                              size: 13,
                              color: b.isEdit
                                  ? CursorTheme.primary
                                  : CursorTheme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              b.fileName,
                              style: const TextStyle(
                                color: CursorTheme.textPrimary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (b.stats != null) ...[
                              const SizedBox(width: 5),
                              Text(
                                b.stats!,
                                style: const TextStyle(
                                  color: Color(0xFF3FB950),
                                  fontSize: 11,
                                  fontFamily: 'Menlo',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (_expanded) ...[
            const Divider(height: 1, color: CursorTheme.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final step in widget.steps)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: InkWell(
                        onTap: () {
                          final p = _filePathInStep(step);
                          if (p != null) widget.onOpenFile?.call(p);
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(
                                _iconForStep(step),
                                size: 12,
                                color: CursorTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                step,
                                style: const TextStyle(
                                  color: Color(0xFFA0A0A5),
                                  fontSize: 11.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Columna de tarjetas en vivo (diff / shell) estilo Cursor.
class _CursorLiveStepsColumn extends StatelessWidget {
  final List<AgentLiveStep> steps;
  final bool hasAnswerBody;
  final ValueChanged<String>? onOpenFile;

  const _CursorLiveStepsColumn({
    required this.steps,
    required this.hasAnswerBody,
    this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _CursorLiveStepCard(
            step: steps[i],
            onOpenFile: onOpenFile,
          ),
        ],
        if (hasAnswerBody && steps.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '${steps.length} ${steps.length == 1 ? 'acción' : 'acciones'}',
            style: const TextStyle(
              color: CursorTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _CursorLiveStepCard extends StatefulWidget {
  final AgentLiveStep step;
  final ValueChanged<String>? onOpenFile;

  const _CursorLiveStepCard({
    required this.step,
    this.onOpenFile,
  });

  @override
  State<_CursorLiveStepCard> createState() => _CursorLiveStepCardState();
}

class _CursorLiveStepCardState extends State<_CursorLiveStepCard> {
  /// Recogida por defecto: el lápiz / header abre el diff (ahorra espacio).
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    // Mientras corre, se ve el progreso; al terminar queda recogida.
    _expanded = widget.step.running;
  }

  @override
  void didUpdateWidget(covariant _CursorLiveStepCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Al pasar de running → listo: recoger (el usuario abre con clic).
    if (oldWidget.step.running && !widget.step.running && _expanded) {
      _expanded = false;
    }
    // Si sigue corriendo y llega el preview, mantener abierta.
    if (widget.step.running && !_expanded) {
      _expanded = true;
    }
  }

  bool get _hasBody =>
      widget.step.previewLines.isNotEmpty ||
      (widget.step.output != null && widget.step.output!.trim().isNotEmpty);

  bool get _isFileEdit =>
      widget.step.kind == AgentLiveStepKind.edit ||
      widget.step.kind == AgentLiveStepKind.create;

  IconData get _headerIcon {
    switch (widget.step.kind) {
      case AgentLiveStepKind.edit:
      case AgentLiveStepKind.create:
        return Icons.edit_outlined;
      case AgentLiveStepKind.shell:
        return Icons.terminal_rounded;
      case AgentLiveStepKind.search:
        return Icons.search_rounded;
      case AgentLiveStepKind.explore:
        return Icons.description_outlined;
      case AgentLiveStepKind.browser:
        return Icons.open_in_new_rounded;
      case AgentLiveStepKind.thought:
        return Icons.psychology_alt_outlined;
      case AgentLiveStepKind.status:
        return Icons.bolt_rounded;
    }
  }

  void _onHeaderTap() {
    final step = widget.step;
    final path = step.filePath;

    if (_hasBody) {
      final willExpand = !_expanded;
      setState(() => _expanded = willExpand);
      // Al abrir un edit: también abre el archivo en Code (el diff del chat).
      if (willExpand &&
          _isFileEdit &&
          path != null &&
          path.isNotEmpty &&
          widget.onOpenFile != null) {
        widget.onOpenFile!(path);
      }
      return;
    }

    if (path != null && path.isNotEmpty && widget.onOpenFile != null) {
      widget.onOpenFile!(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final stats = step.statsLabel;
    final showDiff = _isFileEdit;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1D20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CursorTheme.border.withValues(alpha: 0.7),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: (_hasBody ||
                    (step.filePath != null && widget.onOpenFile != null))
                ? _onHeaderTap
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    step.running ? Icons.hourglass_top_rounded : _headerIcon,
                    size: 14,
                    color: step.running
                        ? CursorTheme.primary
                        : CursorTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      showDiff ? step.fileName : step.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CursorTheme.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (stats != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      stats,
                      style: const TextStyle(
                        color: Color(0xFF3FB950),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Menlo',
                      ),
                    ),
                  ],
                  if (step.running) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ] else if (_hasBody) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 16,
                      color: CursorTheme.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded && step.command != null && step.command!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text(
                step.command!,
                style: const TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 11,
                  fontFamily: 'Menlo',
                ),
              ),
            ),
          if (_expanded && step.previewLines.isNotEmpty) ...[
            const Divider(height: 1, color: CursorTheme.border),
            Container(
              color: const Color(0xFF141416),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in step.previewLines)
                    _DiffPreviewRow(line: line),
                ],
              ),
            ),
          ],
          if (_expanded &&
              step.output != null &&
              step.output!.trim().isNotEmpty) ...[
            const Divider(height: 1, color: CursorTheme.border),
            Container(
              color: const Color(0xFF141416),
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                step.output!,
                style: const TextStyle(
                  color: Color(0xFFA0A0A5),
                  fontSize: 11,
                  fontFamily: 'Menlo',
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiffPreviewRow extends StatelessWidget {
  final AgentLiveStepLine line;

  const _DiffPreviewRow({required this.line});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (line.mark) {
      case '+':
        bg = const Color(0xFF1B3A24);
        fg = const Color(0xFFA5D6A7);
        break;
      case '-':
        bg = const Color(0xFF3A1B1B);
        fg = const Color(0xFFEF9A9A);
        break;
      default:
        bg = Colors.transparent;
        fg = const Color(0xFF8B8B90);
    }
    return ColoredBox(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 14,
              child: Text(
                line.mark.trim().isEmpty ? ' ' : line.mark,
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontFamily: 'Menlo',
                  height: 1.35,
                ),
              ),
            ),
            Expanded(
              child: Text(
                line.text,
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontFamily: 'Menlo',
                  height: 1.35,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
