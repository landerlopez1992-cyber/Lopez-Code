import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/message.dart';
import '../models/agent_live_step.dart';
import '../models/context_mention.dart';
import '../models/chat_checkpoint.dart';
import '../services/openai_service.dart';
import '../services/credit_service.dart';
import '../services/settings_service.dart';
import '../services/project_service.dart';
import '../services/chat_storage_service.dart';
import '../services/advanced_debugging_service.dart';
import '../services/project_type_detector.dart';
import '../services/context_builder_service.dart';
import '../services/checkpoint_service.dart';
import '../services/project_platform_support.dart';
import '../widgets/message_bubble.dart';
import '../widgets/cursor_chat_input.dart';
import '../widgets/cursor_theme.dart';
import '../widgets/voryxel_brand_logo.dart';
import '../widgets/context_autocomplete_overlay.dart';
import '../widgets/documentation_selector.dart';
import '../widgets/checkpoint_banner_widget.dart';
import '../widgets/error_confirmation_dialog.dart';
import '../services/debug_console_service.dart';
import '../services/platform_service.dart';
import '../services/agent_activity_service.dart';
import '../models/pending_action.dart';
import '../services/conversation_memory_service.dart';
import '../services/smart_context_manager.dart';
import '../services/task_orchestrator_service.dart';
import '../services/project_analyzer_service.dart';
import '../services/auto_execution_service.dart';
import 'settings_screen.dart';

// Custom painter para el icono de código (corchetes angulares <>)
// Ajustado para tamaño pequeño profesional (20x20) con esquinas redondeadas
// Mismo que en message_bubble.dart - mantener consistencia
class RobotIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth =
          1.8 // Más delgado para tamaño pequeño
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Tamaño de los corchetes ajustado para 20x20
    final bracketSize = size.width * 0.22; // 22% del ancho
    final bracketHeight = size.height * 0.35; // 35% de la altura
    final spacing = size.width * 0.12; // Espacio entre corchetes

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

class ChatScreen extends StatefulWidget {
  final String? chatId;
  final String? projectPath;

  /// Archivo abierto en el editor (Code tab), si existe.
  final String? activeFilePath;
  final String? activeFileContent;

  /// Abre la pestaña Code (y opcionalmente el archivo del error) sin usar IA.
  final VoidCallback? onViewCode;

  /// Cuando el agente toca un archivo: abrir/refrescar el editor en vivo.
  /// [line] = línea 1-based donde el agente está editando.
  final void Function(String path, {int? line})? onAgentOpenFile;

  final Function(GlobalKey<_ChatScreenState>)?
  onScreenCreated; // Callback para registrar el GlobalKey

  const ChatScreen({
    super.key,
    this.chatId,
    this.projectPath,
    this.activeFilePath,
    this.activeFileContent,
    this.onViewCode,
    this.onAgentOpenFile,
    this.onScreenCreated,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];
  bool _isLoading = false;
  String _loadingStatus = '';
  bool _isErrorReportDraft = false; // Mensaje precargado de errores
  bool _nextTurnIsFixWithAI = false; // Turno lanzado desde "Arreglar con IA"
  String? _currentFileOperation; // 'creando', 'editando', 'leyendo'
  String? _currentFilePath;
  OpenAIService? _openAIService;
  List<String> _selectedImages = [];
  String? _selectedFilePath;
  late String _currentSessionId;
  String? _lastProjectPath;
  // Historial exacto enviado a OpenAI, incluyendo assistant tool_calls y
  // resultados role=tool. Se conserva mientras el agente está pausado.
  final List<Map<String, dynamic>> _apiMessages = [];

  /// 20 pasos con pub get / compilación no caben en 2 min.
  static const Duration _agentTurnTimeout = Duration(minutes: 10);
  List<String> _selectedDocumentation =
      []; // URLs de documentación seleccionadas
  bool _isSending = false; // ✅ FIX: Protección contra envíos duplicados
  bool _pendingActionsShown =
      false; // ✅ FIX: Evitar mensajes duplicados de confirmación
  int? _streamingAssistantMessageIndex;
  String _streamingAssistantText = '';
  /// Timeline de pasos del Agent Loop (visible en la burbuja del asistente).
  String _agentTimelineBuffer = '';
  /// Tarjetas estilo Cursor (diff / shell) en vivo durante el turno.
  final List<AgentLiveStep> _agentLiveSteps = [];

  /// Checkpoint del turno Agent (auto-apply) — se muestra en CheckpointBanner.
  ChatCheckpoint? _turnCheckpoint;

  // Mentions @ / slash commands /
  final List<ContextMention> _activeMentions = [];
  String _inputText = '';
  int _cursorOffset = 0;
  bool _autocompleteActive = false;
  ChatAgentMode _chatMode = ChatAgentMode.agent;

  // Run and Debug — Web Preview por defecto (como selector de foto 1)
  String _selectedPlatform = 'web';
  bool _isRunning = false;
  bool _isDebugging = false;
  Process? _runningProcess; // Proceso en ejecución (para poder detenerlo)
  Timer? _startupTimeout; // Timeout para detectar si el proceso no inicia
  Timer? _startupTimeoutDebug; // Timeout para modo debug
  final DebugConsoleService _debugService = DebugConsoleService();
  final PlatformService _platformService = PlatformService();

  @override
  void initState() {
    super.initState();
    _currentSessionId =
        widget.chatId ?? DateTime.now().millisecondsSinceEpoch.toString();
    // Escuchar cambios en la plataforma
    _platformService.addListener(_onPlatformChanged);
    _messageController.addListener(_onMessageInputChanged);
    _initialize();
  }

  void _onMessageInputChanged() {
    final text = _messageController.text;
    final rawCursor = _messageController.selection.baseOffset;
    final cursor = rawCursor < 0 ? text.length : rawCursor.clamp(0, text.length);
    final query = ContextAutocompleteOverlay.detectQuery(text, cursor);
    if (!mounted) return;
    final changed = text != _inputText ||
        cursor != _cursorOffset ||
        query.isActive != _autocompleteActive;
    if (!changed) return;
    setState(() {
      _inputText = text;
      _cursorOffset = cursor;
      _autocompleteActive = query.isActive;
    });
  }

  String? get _effectiveActiveFilePath =>
      widget.activeFilePath ?? _selectedFilePath;

  Future<String?> _loadActiveFileContent() async {
    if (widget.activeFileContent != null &&
        widget.activeFileContent!.isNotEmpty) {
      return widget.activeFileContent;
    }
    final path = _effectiveActiveFilePath;
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        const maxChars = 30000;
        if (content.length > maxChars) {
          return '${content.substring(0, maxChars)}\n… [truncated]';
        }
        return content;
      }
    } catch (_) {}
    return null;
  }

  void _onMentionSelected(
    ContextMention mention,
    ContextAutocompleteQuery query,
  ) {
    final text = _messageController.text;
    final range = query.replacementRange;
    final start = range.start.clamp(0, text.length);
    final end = range.end.clamp(start, text.length);
    final insertion = '${mention.label} ';
    final newText = text.replaceRange(start, end, insertion);
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
    setState(() {
      if (!_activeMentions.any((m) => m.id == mention.id)) {
        _activeMentions.add(mention);
      }
      _autocompleteActive = false;
    });
  }

  void _onSlashCommandSelected(
    SlashCommand command,
    String expandedPrompt,
    ContextAutocompleteQuery query,
  ) {
    _messageController.value = TextEditingValue(
      text: expandedPrompt,
      selection: TextSelection.collapsed(offset: expandedPrompt.length),
    );
    setState(() {
      _autocompleteActive = false;
    });
  }

  void _removeMention(ContextMention mention) {
    setState(() {
      _activeMentions.removeWhere((m) => m.id == mention.id);
    });
  }

  Widget _buildActiveMentionChips() {
    if (_activeMentions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _activeMentions.map((mention) {
            return Container(
              padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
              decoration: BoxDecoration(
                color: CursorTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: CursorTheme.primary.withOpacity(0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mention.label,
                    style: const TextStyle(
                      color: CursorTheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  InkWell(
                    onTap: () => _removeMention(mention),
                    borderRadius: BorderRadius.circular(10),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: CursorTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _onPlatformChanged() {
    if (mounted) {
      setState(() {
        _selectedPlatform = _platformService.selectedPlatform;
        print(
          '🔧 ChatScreen._onPlatformChanged: Plataforma actualizada a: $_selectedPlatform',
        );
      });
    }
  }

  /// Método público para precargar un mensaje desde fuera (Debug Console)
  /// Precarga el mensaje en el input, pero NO lo envía automáticamente
  void sendExternalMessage(String message) {
    if (!mounted || message.isEmpty) return;

    try {
      // Usar un microtask para evitar problemas de estado
      Future.microtask(() {
        if (!mounted) return;

        setState(() {
          _messageController.text = message;
          _isErrorReportDraft = true;
          // NO llamar a _sendMessage() automáticamente
          // El usuario debe presionar el botón de enviar
        });

        // Hacer scroll al final para que el usuario vea el mensaje precargado
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          try {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          } catch (e) {
            print('⚠️ Error al hacer scroll: $e');
          }
        });
      });
    } catch (e) {
      print('❌ Error en sendExternalMessage: $e');
    }
  }

  bool _isNoMobileDeviceError(String errorMessage) {
    final lower = errorMessage.toLowerCase();
    return lower.contains('no se encontró dispositivo') &&
        (lower.contains('android') || lower.contains('ios'));
  }

  /// Cambia a Web y lanza el Preview interno (web-server + WebView).
  void runOnWebPreview() {
    if (!mounted) return;
    _platformService.setPlatform('web');
    setState(() => _selectedPlatform = 'web');
    _debugService.addDebugConsole(
      '🌐 Cambiando a Web Preview e iniciando flutter run…',
    );
    unawaited(_handleRun());
  }

  /// Recorta logs enormes para que el chat no se llene de miles de líneas.
  String _compactErrorForChat(String raw, {int maxChars = 3500}) {
    final text = raw.trim();
    if (text.length <= maxChars) return text;
    final lines = text.split('\n');
    final important = <String>[];
    for (final line in lines) {
      final l = line.toLowerCase();
      if (l.contains('error') ||
          l.contains('failed') ||
          l.contains('exception') ||
          l.contains('could not find')) {
        important.add(line);
      }
    }
    final head = lines.take(25).join('\n');
    final tail = lines.length > 30
        ? lines.sublist(lines.length - 30).join('\n')
        : '';
    final focus = important.take(40).join('\n');
    return '$head\n\n… [${text.length - maxChars} chars omitidos] …\n\n'
        '--- errores relevantes ---\n$focus\n\n--- final ---\n$tail';
  }

  /// Envía al chat (modo Agent) un error de compilación para auto-reparación.
  void fixCompilationErrorWithAI(String errorMessage) {
    if (!mounted || errorMessage.trim().isEmpty) return;
    final compact = _compactErrorForChat(errorMessage);
    final noDevice = _isNoMobileDeviceError(errorMessage);
    final selector = _platformService.selectedPlatform.toLowerCase();
    final previewTarget = selector.startsWith('ios') ? 'ios' : 'android';
    final prompt = noDevice
        ? '''
La ejecución falló porque no hay emulador nativo. NO cambies el selector a Web.
1) Mantén la plataforma del usuario. Si pidió Android/iOS nativo, usa Preview: ide_control(set_platform: "$previewTarget") solo si hace falta, luego ide_control(run_app).
2) Android/iOS (Preview) ya muestran la app en el marco de teléfono (NO es "pasar a Web").
3) Solo usa Web si el selector del IDE ya es Web o el usuario lo pidió.
No preguntes confirmación: actúa ahora.

Error:
$compact
'''.trim()
        : '''
La compilación/ejecución falló. Diagnostica la causa raíz EXACTA del Error/Output abajo y aplica la solución automáticamente.
1) Empieza con read_console_logs (mira Output, no adivines).
2) Si el error es un flag CLI inválido (p. ej. "Could not find an option named …"), NO te pierdas arreglando widget_test: reintenta ide_control(run_app) / compile_project.
3) Solo usa flutter analyze para errores de código del proyecto relacionados con ese fallo.
4) NO cambies el selector a Web. Respeta la plataforma elegida por el usuario (${ProjectPlatformSupport.humanLabel(selector.isEmpty ? 'android' : selector)}).
No preguntes: actúa. Prioriza el error del Output sobre tests colaterales.

Error:
$compact
'''.trim();
    setState(() {
      _chatMode = ChatAgentMode.agent;
      _messageController.text = prompt;
      _isErrorReportDraft = false;
      _nextTurnIsFixWithAI = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_sendMessage());
      }
    });
  }

  /// Valida que la plataforma elegida exista en el proyecto; si no, auto-cambia.
  Future<String> _ensureCompatiblePlatform({
    required String projectPath,
    required String requestedPlatform,
  }) async {
    await _platformService.refreshFromProject(projectPath);
    final supported = _platformService.supportedPlatforms;
    final requested = requestedPlatform.toLowerCase();

    // android_native / ios_native → válidos si existe carpeta android/ o ios/
    if (ProjectPlatformSupport.isSupportedVariant(requested, supported)) {
      return requested;
    }

    final preferred =
        ProjectPlatformSupport.preferPlatform(supported) ?? 'android';
    final hint = ProjectPlatformSupport.missingFolderHint(
      requested,
      supported,
    );

    _platformService.setPlatform(preferred);
    if (mounted) {
      setState(() => _selectedPlatform = preferred);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$hint\n→ Ejecutando en ${ProjectPlatformSupport.humanLabel(preferred)}.',
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 5),
        ),
      );
    }
    return preferred;
  }

  Future<void> _initialize() async {
    // Sincronizar plataforma con PlatformService
    // Si el servicio no tiene plataforma, establecer 'macos' como predeterminada
    if (_platformService.selectedPlatform.isEmpty) {
      _platformService.setPlatform('macos');
    }
    _selectedPlatform = _platformService.selectedPlatform;
    print(
      '🔧 ChatScreen._initialize: Plataforma sincronizada: $_selectedPlatform',
    );

    // Resetear estado cuando cambia el proyecto
    final projectPath =
        widget.projectPath ?? await ProjectService.getProjectPath();
    if (_lastProjectPath != projectPath) {
      setState(() {
        _messages.clear();
        _isLoading = false;
        _loadingStatus = '';
        _currentFileOperation = null;
        _currentFilePath = null;
        _selectedImages.clear();
        _selectedFilePath = null;
        _apiMessages.clear();
      });
      _lastProjectPath = projectPath;
    }

    // Cargar API key y reinicializar servicio
    await _loadOpenAIService();

    // Cargar conversación
    await _loadConversation();

    print('✅ ChatScreen inicializado correctamente');
  }

  Future<void> _loadOpenAIService() async {
    final apiKey = await SettingsService.getApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      // getSelectedModel migra defaults viejos → gpt-4.1
      final selectedModel = await SettingsService.getSelectedModel();
      _openAIService?.dispose();
      final service = OpenAIService(apiKey: apiKey, model: selectedModel);
      service.onIdeControl = _handleIdeControlFromAgent;
      setState(() {
        _openAIService = service;
      });
      print('✅ OpenAI Service inicializado con modelo: $selectedModel');
    }
  }

  /// Sincroniza barra superior + Preview cuando el agente llama ide_control.
  Future<String> _handleIdeControlFromAgent(
    String action, {
    Map<String, dynamic>? args,
  }) async {
    final normalized = action.trim().toLowerCase();
    switch (normalized) {
      case 'set_platform':
        final platform = (args?['platform'] as String? ?? '').toLowerCase();
        const allowed = {
          'android',
          'android_native',
          'ios',
          'ios_native',
          'web',
          'macos',
        };
        if (!allowed.contains(platform)) {
          return 'Error: platform inválida. Usa android, android_native, '
              'ios, ios_native, web o macos.';
        }
        _platformService.setPlatform(platform);
        if (mounted) {
          setState(() => _selectedPlatform = platform);
        }
        _debugService.addDebugConsole('🎛️ IDE: plataforma → $platform');
        return '✅ Plataforma del IDE → $platform (dropdown sincronizado)';

      case 'run_app':
        // No pisar el dropdown aquí. Para cambiar plataforma: set_platform.
        // Esperar resultado real (compilación lista o fallo) antes de responder.
        _debugService.addDebugConsole(
          '▶️ IDE: run_app (${_platformService.selectedPlatform})',
        );
        return await _runAppAndWaitForResult();

      case 'hot_restart':
        await _handleHotRestart();
        return '✅ Hot Restart enviado (barra superior / Preview)';

      case 'stop_app':
        await _handleStop();
        return '✅ Stop — proceso detenido y Preview limpiado';

      default:
        return 'Error: action desconocida "$action". '
            'Usa set_platform | run_app | hot_restart | stop_app.';
    }
  }

  Future<void> _loadConversation() async {
    try {
      final projectPath =
          widget.projectPath ?? await ProjectService.getProjectPath();
      if (projectPath == null || projectPath.isEmpty) return;

      final messagesJson = await ChatStorageService.loadAgentMessages(
        _currentSessionId,
      );
      if (messagesJson.isNotEmpty) {
        setState(() {
          _messages.clear();
          _messages.addAll(messagesJson.map((m) => Message.fromJson(m)));
        });
        // Tras layout: ir al final (última conversación), no quedarse arriba.
        _scrollToLatestConversation(force: true);
      }
    } catch (e) {
      print('⚠️ Error al cargar conversación: $e');
    }
  }

  Future<void> _saveConversation() async {
    try {
      final projectPath =
          widget.projectPath ?? await ProjectService.getProjectPath();
      if (projectPath == null) return;

      final messagesJson = _messages.map((m) => m.toJson()).toList();
      await ChatStorageService.saveAgentMessages(
        _currentSessionId,
        messagesJson,
        projectPath: projectPath,
      );
    } catch (e) {
      print('⚠️ Error al guardar conversación: $e');
    }
  }

  /// [keepBubble]: conserva la burbuja de progreso (p. ej. tras Accept).
  /// [clearTimeline]: reinicia el historial de pasos visibles.
  void _beginStreamingResponse({
    bool keepBubble = false,
    bool clearTimeline = true,
  }) {
    if (!keepBubble) {
      _streamingAssistantMessageIndex = null;
    }
    _streamingAssistantText = '';
    if (clearTimeline) {
      _agentTimelineBuffer = '';
      _agentLiveSteps.clear();
    }
  }

  String _statusForPendingAction(PendingAction action) {
    final path = action.arguments['file_path'] as String? ??
        action.arguments['folder_path'] as String? ??
        action.arguments['command'] as String? ??
        '';
    switch (action.functionName) {
      case 'list_files':
        return 'Exploring project files';
      case 'grep_search':
        return 'Searching codebase';
      case 'read_file':
        return 'Exploring ${path.isEmpty ? 'file' : path}';
      case 'compile_project':
        return 'Running flutter run';
      case 'execute_command':
        return 'Running ${path.isEmpty ? 'command' : path}';
      case 'edit_file':
        return 'Editing ${path.isEmpty ? 'file' : path}';
      case 'write_file':
        return 'Writing ${path.isEmpty ? 'file' : path}';
      case 'create_file':
        return 'Creating ${path.isEmpty ? 'file' : path}';
      default:
        return 'Running ${action.functionName}';
    }
  }

  /// Escapa markdown inline que dispara asserts de flutter_markdown (_inlines).
  String _escapeMarkdownInline(String raw) {
    return raw
        .replaceAll('\\', '\\\\')
        .replaceAll('_', '\\_')
        .replaceAll('*', '\\*')
        .replaceAll('`', '\\`')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]');
  }

  void _handleStepProgress(
    String statusText, {
    String? detail,
    AgentLiveStep? card,
  }) {
    if (!mounted || statusText.trim().isEmpty) return;
    // Timeline Cursor: sin prefijos emoji ni HR markdown (---).
    final cleanStatus = statusText
        .replaceAll(RegExp(r'^[^\w\./()\-]+'), '')
        .trim();
    // Pasos internos del loop / modelo: solo en el spinner, no en la burbuja.
    if (cleanStatus.startsWith('Continuing')) {
      setState(() => _loadingStatus = 'Working');
      return;
    }
    if (detail != null && detail.trim().startsWith('model=')) detail = null;
    // Guardar texto limpio sin escapes (\_) para que las tarjetas del chat
    // muestren rutas reales (authentication_widget.dart).
    final line = (detail != null && detail.isNotEmpty)
        ? '• $cleanStatus\n  $detail'
        : '• $cleanStatus';
    setState(() {
      _loadingStatus = cleanStatus;
      _agentTimelineBuffer = _agentTimelineBuffer.isEmpty
          ? line
          : '$_agentTimelineBuffer\n$line';
      if (card != null) {
        // Sustituir tarjeta "running" del mismo archivo/comando por la final.
        final existing = _agentLiveSteps.indexWhere((s) {
          if (!s.running) return false;
          if (card.filePath != null &&
              card.filePath!.isNotEmpty &&
              s.filePath == card.filePath) {
            return true;
          }
          if (card.command != null &&
              card.command!.isNotEmpty &&
              s.command == card.command) {
            return true;
          }
          return s.kind == card.kind && s.title == card.title;
        });
        if (existing >= 0) {
          _agentLiveSteps[existing] = card;
        } else {
          _agentLiveSteps.add(card);
        }
      }
      final content = _streamingAssistantText.isNotEmpty
          ? '$_agentTimelineBuffer\n\n$_streamingAssistantText'
          : _agentTimelineBuffer;
      final streamedMessage = Message(
        role: 'assistant',
        content: content,
        timestamp: DateTime.now(),
        liveSteps: List<AgentLiveStep>.from(_agentLiveSteps),
      );
      final index = _streamingAssistantMessageIndex;
      if (index != null && index >= 0 && index < _messages.length) {
        _messages[index] = streamedMessage;
      } else {
        _messages.add(streamedMessage);
        _streamingAssistantMessageIndex = _messages.length - 1;
      }
    });
    // Streaming en vivo: siempre al final (force).
    _scrollToLatestConversation(force: true);
  }

  void _handleStreamChunk(String partialText) {
    if (!mounted || partialText == _streamingAssistantText) return;
    setState(() {
      _streamingAssistantText = partialText;
      final content = _agentTimelineBuffer.isNotEmpty
          ? '$_agentTimelineBuffer\n\n$partialText'
          : partialText;
      final streamedMessage = Message(
        role: 'assistant',
        content: content,
        timestamp: DateTime.now(),
        liveSteps: _agentLiveSteps.isEmpty
            ? null
            : List<AgentLiveStep>.from(_agentLiveSteps),
      );
      final index = _streamingAssistantMessageIndex;
      if (index != null && index >= 0 && index < _messages.length) {
        _messages[index] = streamedMessage;
      } else {
        _messages.add(streamedMessage);
        _streamingAssistantMessageIndex = _messages.length - 1;
      }
    });
    _scrollToLatestConversation(force: true);
  }

  void _showCompilationFailureDialog(String errorMessage) {
    if (!mounted) return;
    final offerWeb = _isNoMobileDeviceError(errorMessage);
    ErrorConfirmationDialog.show(
      context: context,
      title: 'Compilación fallida',
      message: errorMessage,
      showViewErrorsButton: true,
      onViewErrors: () {
        _debugService.showOutputTab();
      },
      showFixWithAIButton: true,
      onFixWithAI: () {
        fixCompilationErrorWithAI(errorMessage);
      },
      showViewCodeButton: true,
      onViewCode: () {
        widget.onViewCode?.call();
      },
      showRunOnWebButton: offerWeb,
      onRunOnWeb: offerWeb ? runOnWebPreview : null,
    );
  }

  /// Status chip + abrir Code en vivo cuando el agente edita/lee archivos.
  /// Apaga el banner "Agente trabajando…" del editor / explorador.
  void _clearAgentWorkingIndicator() {
    AgentActivityService().clear();
    widget.onAgentOpenFile?.call('');
  }

  void _handleAgentFileOperation(
    String operation,
    String filePath, {
    int? line,
  }) {
    if (!mounted) return;
    setState(() {
      _currentFileOperation = operation;
      _currentFilePath = filePath;
    });

    final path = filePath.trim();
    final activity = AgentActivityService();

    // Siempre publicar estado global (compile / pub get / edit / …).
    switch (operation) {
      case 'compilando':
        activity.setBusy('Compilando y lanzando…', operation: operation);
        return;
      case 'ejecutando':
        activity.setBusy(
          'Ejecutando comando',
          operation: operation,
          detail: path.length > 48 ? '${path.substring(0, 48)}…' : path,
        );
        return;
      case 'listando':
        activity.setBusy('Explorando archivos del proyecto', operation: operation);
        return;
      case 'buscando':
        activity.setBusy('Buscando en el código', operation: operation, detail: path);
        return;
      case 'dispositivos':
        activity.setBusy('Comprobando dispositivos Flutter', operation: operation);
        return;
      case 'logs':
        activity.setBusy('Leyendo Output / Problems', operation: operation);
        return;
      case 'ide':
        activity.setBusy('Controlando el IDE', operation: operation, detail: path);
        return;
      case 'descargando':
      case 'navegando':
        activity.setBusy(
          operation == 'navegando' ? 'Navegando' : 'Descargando',
          operation: operation,
          detail: path,
        );
        return;
      case 'creando':
        // Carpeta o archivo aún inexistente: banner, sin abrir editor aún.
        if (path.isEmpty || path == 'proyecto') {
          activity.setBusy('Creando…', operation: operation);
          return;
        }
        activity.setActive(path, line: line ?? 1, operation: operation);
        return;
      case 'editando':
      case 'leyendo':
      case 'archivo_actualizado':
      case 'inspeccionando imagen':
        if (path.isEmpty ||
            path == 'proyecto' ||
            path == 'console' ||
            path.startsWith('http')) {
          activity.setBusy('Trabajando…', operation: operation);
          return;
        }
        activity.setActive(path, line: line, operation: operation);
        if (operation != 'inspeccionando imagen') {
          widget.onAgentOpenFile?.call(path, line: line);
        }
        return;
      default:
        if (path.isNotEmpty &&
            path != 'proyecto' &&
            !path.startsWith('http')) {
          activity.setActive(path, line: line, operation: operation);
        } else {
          activity.setBusy(
            'Trabajando…',
            operation: operation,
            detail: path.isEmpty ? null : path,
          );
        }
    }
  }

  /// Editar mensaje del usuario (estilo Cursor): carga en el composer y
  /// elimina ese mensaje y todo lo posterior del hilo.
  void _editUserMessageAt(int index) {
    if (index < 0 || index >= _messages.length) return;
    final msg = _messages[index];
    if (msg.role != 'user') return;

    setState(() {
      _messageController.text = msg.content;
      _messageController.selection = TextSelection.collapsed(
        offset: msg.content.length,
      );
      if (msg.imageUrls != null && msg.imageUrls!.isNotEmpty) {
        _selectedImages = List<String>.from(msg.imageUrls!);
      } else {
        _selectedImages.clear();
      }
      _selectedFilePath = msg.filePath;
      _messages.removeRange(index, _messages.length);
      _apiMessages.clear();
      _pendingActionsShown = false;
      _streamingAssistantMessageIndex = null;
      _streamingAssistantText = '';
      _agentTimelineBuffer = '';
      _agentLiveSteps.clear();
    });
    _scrollToBottom();
  }

  /// Reenviar desde un mensaje del usuario: trunca el hilo y vuelve a enviar.
  void _resendUserMessageAt(int index) {
    if (index < 0 || index >= _messages.length) return;
    final msg = _messages[index];
    if (msg.role != 'user') return;

    final content = msg.content;
    final images = msg.imageUrls != null
        ? List<String>.from(msg.imageUrls!)
        : <String>[];
    final filePath = msg.filePath;

    setState(() {
      _messages.removeRange(index, _messages.length);
      _apiMessages.clear();
      _pendingActionsShown = false;
      _streamingAssistantMessageIndex = null;
      _streamingAssistantText = '';
      _agentTimelineBuffer = '';
      _agentLiveSteps.clear();
      _messageController.text = content;
      _selectedImages = images;
      _selectedFilePath = filePath;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_sendMessage());
    });
  }

  bool _finalizeStreamingResponse(
    String finalText, {
    ChatCheckpoint? checkpoint,
  }) {
    final index = _streamingAssistantMessageIndex;
    if (index == null || index < 0 || index >= _messages.length) return false;
    final content = _agentTimelineBuffer.isNotEmpty &&
            !finalText.contains(_agentTimelineBuffer)
        ? '$_agentTimelineBuffer\n\n$finalText'
        : finalText;
    final steps = List<AgentLiveStep>.from(_agentLiveSteps);
    setState(() {
      _messages[index] = Message(
        role: 'assistant',
        content: content,
        timestamp: DateTime.now(),
        checkpoint: checkpoint,
        liveSteps: steps.isEmpty ? null : steps,
      );
      _streamingAssistantMessageIndex = null;
      _streamingAssistantText = '';
      _agentTimelineBuffer = '';
      _agentLiveSteps.clear();
      _loadingStatus = '';
    });
    return true;
  }

  Future<void> _createTurnCheckpoint(
    List<String> filePaths, {
    required String? projectPath,
    String? label,
  }) async {
    if (projectPath == null || projectPath.isEmpty || filePaths.isEmpty) {
      return;
    }
    if (_turnCheckpoint != null) return; // un checkpoint por turno
    try {
      final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
      _turnCheckpoint = await CheckpointService.createCheckpoint(
        projectPath: projectPath,
        label: label ?? 'Antes de aplicar ${filePaths.length} cambio(s)',
        filePaths: filePaths,
        messageId: messageId,
      );
      print(
        '📌 Checkpoint auto-apply: ${_turnCheckpoint!.checkpointId} '
        '(${filePaths.length} archivo(s))',
      );
    } catch (e) {
      print('⚠️ No se pudo crear checkpoint: $e');
    }
  }

  /// Rutas afectadas por mutaciones de archivo (para checkpoint).
  List<String> _extractAffectedFilePaths(List<PendingAction> actions) {
    const mutating = {'edit_file', 'write_file', 'create_file'};
    final paths = <String>[];
    final seen = <String>{};

    void addPath(String? raw) {
      final path = raw?.trim() ?? '';
      if (path.isEmpty) return;
      if (seen.add(path)) paths.add(path);
    }

    for (final action in actions) {
      if (!mutating.contains(action.functionName)) continue;
      addPath(action.arguments['file_path'] as String?);
      for (final file in action.affectedFiles) {
        addPath(file);
      }
    }
    return paths;
  }

  Future<void> _sendMessage() async {
    final hasText = _messageController.text.trim().isNotEmpty;
    final hasImages = _selectedImages.isNotEmpty;

    // Lock huérfano: un return temprano dejó _isSending=true y bloqueaba
    // Return / el botón de enviar para siempre (UI sigue en azul, no en stop).
    if (_isSending && !_isLoading) {
      print('⚠️ Liberando lock de envío huérfano (_isSending sin _isLoading)');
      _isSending = false;
    }

    // ✅ FIX: Protección contra envíos duplicados y carga infinita
    if ((!hasText && !hasImages) || _isLoading || _isSending) {
      print(
        '⚠️ Intento de envío bloqueado: hasText=$hasText hasImages=$hasImages '
        '_isLoading=$_isLoading _isSending=$_isSending',
      );
      return;
    }

    _isSending = true; // ✅ Marcar como enviando

    void releaseSendLock() {
      _isSending = false;
    }

    // ✅ FIX: Inicializar saldo si no existe (solo la primera vez)
    try {
      final currentBalance = await CreditService.getBalance();
      print('💰 Saldo actual: \$${currentBalance.toStringAsFixed(2)}');
    } catch (e) {
      print('⚠️ No se pudo leer saldo: $e');
    }

    if (_openAIService == null) {
      try {
        await _loadOpenAIService();
        if (_openAIService == null) {
          releaseSendLock();
          // Sin API Key el envío abría Configuración “en silencio” y parecía
          // un bug de navegación. Avisamos y luego abrimos settings.
          if (mounted) {
            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: CursorTheme.surface,
                title: const Text(
                  'Falta la API Key',
                  style: TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                content: const Text(
                  'Para enviar mensajes al agente necesitas guardar tu '
                  'API Key de OpenAI en Configuración.\n\n'
                  'Pégala, pulsa “Guardar API Key” y vuelve a enviar.',
                  style: TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Ir a Configuración'),
                  ),
                ],
              ),
            );
          }
          _openSettings();
          return;
        }
      } catch (e) {
        print('❌ Error al inicializar OpenAI Service: $e');
        releaseSendLock();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo iniciar el agente: $e'),
              backgroundColor: Colors.red.shade800,
            ),
          );
        }
        return;
      }
    }

    final projectPath =
        widget.projectPath ?? await ProjectService.getProjectPath();
    if (projectPath == null || projectPath.isEmpty) {
      releaseSendLock();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No hay proyecto cargado. Por favor carga un proyecto primero.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final imagesToSend = List<String>.from(_selectedImages);
    final filePathToSend = _selectedFilePath;

    String userMessage = _messageController.text.trim().isEmpty
        ? (hasImages ? 'Analiza esta imagen y describe lo que ves' : '')
        : _messageController.text.trim();

    final bool isErrorReport =
        _isErrorReportDraft ||
        userMessage.contains('Errores de Compilación/Ejecución');
    final bool forceFullModel = _nextTurnIsFixWithAI;
    _nextTurnIsFixWithAI = false;

    // Si es un reporte de errores, limitar tamaño para evitar bloqueos
    if (isErrorReport && userMessage.length > 6000) {
      userMessage =
          '${userMessage.substring(0, 6000)}\n\n...[Errores truncados para evitar bloqueo]';
    }

    // Snapshot de menciones @ para UI limpia + payload enriquecido
    final mentionsSnapshot = List<ContextMention>.from(_activeMentions);
    final mentionLabels = mentionsSnapshot.map((m) => m.label).toList();
    final displayUserMessage = mentionLabels.isEmpty
        ? userMessage
        : '$userMessage\n\n${mentionLabels.join(' ')}';

    _messageController.clear();
    if (mounted) {
      setState(() {
        _activeMentions.clear();
        _autocompleteActive = false;
        _isErrorReportDraft = false;
      });
    }

    try {
      // Obtener projectPath antes de usarlo
      final currentProjectPath =
          widget.projectPath ?? await ProjectService.getProjectPath();

      if (mounted) {
        setState(() {
          _loadingStatus = 'Construyendo contexto optimizado...';
        });
      }

      final activeFilePath = _effectiveActiveFilePath;
      final activeFileContent = await _loadActiveFileContent();

      // Agent = tools ON; Ask = solo lectura de contexto, sin tools
      final bool allowTools =
          _chatMode == ChatAgentMode.agent && !isErrorReport;
      final bool autoApplyEdits = allowTools;

      // En modo Agent no necesitamos el contexto pesado duplicado de SmartContextManager.
      ContextBundle contextBundle;
      if (allowTools) {
        contextBundle = ContextBundle(
          content: userMessage,
          estimatedTokens: SmartContextManager.estimateTokens(userMessage),
          metadata: {'agentMinimal': true},
        );
      } else {
        try {
          contextBundle =
              await SmartContextManager.buildOptimizedContext(
                userMessage: userMessage,
                projectPath: currentProjectPath ?? '',
                sessionId: _currentSessionId,
                selectedFiles: _selectedFilePath != null
                    ? [_selectedFilePath!]
                    : null,
                includeDocumentation: SmartContextManager.needsDocumentation(
                  userMessage,
                ),
                includeHistory: true,
                includeProjectStructure: SmartContextManager.needsFullContext(
                  userMessage,
                ),
                analyzeBeforeActing: false,
              ).timeout(
                const Duration(seconds: 10),
                onTimeout: () => ContextBundle(
                  content: userMessage,
                  estimatedTokens: SmartContextManager.estimateTokens(
                    userMessage,
                  ),
                  metadata: {'timeout': true},
                ),
              );
        } catch (e) {
          contextBundle = ContextBundle(
            content: userMessage,
            estimatedTokens: SmartContextManager.estimateTokens(userMessage),
            metadata: {'error': e.toString()},
          );
        }
      }

      print(
        '📊 Contexto: ${contextBundle.summary}, ${contextBundle.estimatedTokens} tokens',
      );

      if (mounted) {
        setState(() {
          _loadingStatus =
              'Pensando en la solución... (${contextBundle.estimatedTokens} tokens)';
        });
      }

      // Guardar mensaje en memoria persistente
      await ConversationMemoryService.addMessage(
        role: 'user',
        content: displayUserMessage,
        sessionId: _currentSessionId,
        metadata: {
          'hasImages': imagesToSend.isNotEmpty,
          'hasFiles': _selectedFilePath != null,
          'mentions': mentionLabels,
        },
      );

      // Payload a la API: en modo Agent el system prompt + rules + workspace +
      // historial ya los arma OpenAIService; evitar duplicar SmartContextManager.
      String enhancedMessage =
          allowTools ? userMessage : contextBundle.content;
      if (mentionsSnapshot.isNotEmpty ||
          (activeFilePath != null &&
              activeFilePath.isNotEmpty &&
              activeFileContent != null)) {
        enhancedMessage = await ContextBuilderService.enrichPromptWithMentions(
          rawMessage: userMessage,
          mentions: mentionsSnapshot,
          projectPath: currentProjectPath ?? '',
          activeFilePath: activeFilePath,
          activeFileContent: activeFileContent,
        );
      }

      // System prompt lo construye OpenAIService en modo Agent.
      final systemPrompt = '';

      // Acotar historial enviado (últimos 12 mensajes, máx 1500 chars en viejos)
      // para no rebasar el TPM (429) de OpenAI en sesiones largas.
      final historySlice = _messages.length > 12
          ? _messages.sublist(_messages.length - 12)
          : _messages;
      final conversationHistory = historySlice.map((msg) {
        var text = msg.content;
        if (text.length > 1500) {
          text = '${text.substring(0, 900)}\n…[recortado]…\n'
              '${text.substring(text.length - 500)}';
        }
        return {'role': msg.role, 'content': text};
      }).toList();

      // fileContent ya no se usa - el contexto está optimizado
      final fileContent = null; // Para compatibilidad con código existente
      _turnCheckpoint = null;

      // Captura adjunta en modo Agent: el modelo debe ACTUAR sobre el código,
      // no describir la imagen ni pedir al usuario que pegue el widget.
      final bool imageAgentTurn = allowTools && imagesToSend.isNotEmpty;
      if (imageAgentTurn) {
        enhancedMessage = '$enhancedMessage\n\n'
            '<image_task>\n'
            'La captura adjunta es contexto para una tarea sobre ESTE proyecto. '
            'Si muestra un fallo visual (franja "OVERFLOWED BY N PIXELS", texto '
            'cortado, widget descuadrado) o el usuario pide corregir algo que '
            'se ve en ella:\n'
            '1. Lee los textos visibles en la captura (botones, títulos, '
            'etiquetas) y búscalos con grep_search para localizar el archivo '
            'y el widget exactos.\n'
            '2. Abre ese archivo con read_file.\n'
            '3. Corrige con edit_file y verifica el resultado.\n'
            'No pidas al usuario que pegue o muestre el código: búscalo tú. '
            'No respondas con una lista genérica de causas posibles.\n'
            '</image_task>';
      }

      // ✅ Todas las peticiones (incl. run/debug/compilar) pasan por el Agent Loop.
      // El agente explora plataformas y elige dispositivo; no hay bypass local.

      // ✅ FIX CRÍTICO: UI muestra mensaje limpio + labels de menciones
      final userMsg = Message(
        role: 'user',
        content: displayUserMessage,
        timestamp: DateTime.now(),
        imageUrls: imagesToSend.isNotEmpty ? imagesToSend : null,
        filePath: filePathToSend,
      );

      if (mounted) {
        setState(() {
          _messages.add(userMsg);
          _selectedImages.clear();
          _selectedFilePath = null;
          _isLoading = true;
          _loadingStatus = 'Thought briefly';
        });
        _scrollToBottom();
      }

      // ✅ NUEVO: Verificar saldo antes de enviar
      final estimatedTokens = contextBundle.estimatedTokens;
      // Obtener modelo actual
      final currentModel = _openAIService?.model ?? SettingsService.defaultModel;
      // Costo aproximado por token (ajustar según modelo)
      final costPerToken = currentModel.contains('gpt-4o')
          ? 0.00001
          : 0.000002; // gpt-4o es más caro

      final hasBalance = await CreditService.hasEnoughBalance(
        estimatedTokens,
        costPerToken,
      );
      if (!hasBalance) {
        final balance = await CreditService.getBalance();
        final estimatedCost = CreditService.getEstimatedCost(
          estimatedTokens,
          costPerToken,
        );
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSending = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '💰 Saldo insuficiente. Tienes \$${balance.toStringAsFixed(2)}, necesitas \$${estimatedCost.toStringAsFixed(2)}',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Auto routing: gpt-4.1-mini por defecto cuando Auto está ON.
      final autoMode = await SettingsService.getAutoMode();

      // ✅ FIX: Agregar timeout para evitar cuelgues
      _beginStreamingResponse();
      final response = await _openAIService!
          .sendMessage(
            message: enhancedMessage,
            imagePaths: imagesToSend.isNotEmpty ? imagesToSend : null,
            conversationHistory: conversationHistory,
            fileContent: fileContent,
            systemPrompt: systemPrompt.isNotEmpty ? systemPrompt : null,
            projectPath:
                currentProjectPath, // CRÍTICO: Necesario para Function Calling
            activeFilePath: activeFilePath,
            activeFileContent: activeFileContent,
            allowTools: allowTools,
            autoApplyEdits: autoApplyEdits,
            autoMode: autoMode,
            // Con captura adjunta, Auto escala a gpt-4.1: el mini tiende a
            // describir la imagen en vez de usar herramientas.
            forceFullModel: forceFullModel || imageAgentTurn,
            onBeforeAutoEdits: autoApplyEdits
                ? (paths) => _createTurnCheckpoint(
                      paths,
                      projectPath: currentProjectPath,
                    )
                : null,
            // Agent+autoApply: PendingActions solo para comandos no seguros.
            apiMessages: _apiMessages,
            onTokensUsed: (tokens) async {
              // ✅ Descontar créditos cuando se usan tokens
              final deducted = await CreditService.deductCredits(
                tokens,
                costPerToken,
                model: currentModel,
                note: allowTools ? 'Agent' : 'Ask',
              );
              if (!deducted) {
                print('⚠️ No se pudieron descontar créditos');
              } else {
                final newBalance = await CreditService.getBalance();
                print(
                  '💰 Créditos descontados. Saldo restante: \$${newBalance.toStringAsFixed(2)}',
                );
                // Actualizar UI si es necesario
                if (mounted) {
                  setState(() {}); // Forzar rebuild para actualizar contador
                }
              }
            },
            onFileOperation: allowTools ? _handleAgentFileOperation : null,
            onPendingActions:
                allowTools ? _handlePendingActionsFromService : null,
            onStreamChunk: _handleStreamChunk,
            onStepProgress: _handleStepProgress,
            onIdeControl: _handleIdeControl,
          )
          .timeout(
            _agentTurnTimeout,
            onTimeout: () {
              throw TimeoutException(
                'La solicitud tardó demasiado. Intenta de nuevo con un mensaje más corto.',
              );
            },
          );

      // ✅ FIX: Evitar duplicado de "Esperando confirmación" cuando ya se mostró la tarjeta
      if (_pendingActionsShown &&
          response.trim().toLowerCase().startsWith(
            'esperando tu confirmación',
          )) {
        _clearAgentWorkingIndicator();
        return;
      }

      final turnCp = _turnCheckpoint;
      final assistantMsg = Message(
        role: 'assistant',
        content: response,
        timestamp: DateTime.now(),
        checkpoint: turnCp,
      );
      final finalizedStream = _finalizeStreamingResponse(
        response,
        checkpoint: turnCp,
      );

      // Guardar respuesta del asistente en memoria persistente
      await ConversationMemoryService.addMessage(
        role: 'assistant',
        content: response,
        sessionId: _currentSessionId,
      );

      if (mounted) {
        setState(() {
          if (!finalizedStream) {
            _messages.add(assistantMsg);
          } else if (turnCp != null) {
            final idx = _messages.lastIndexWhere(
              (m) => m.role == 'assistant',
            );
            if (idx >= 0 && _messages[idx].checkpoint == null) {
              _messages[idx] = _messages[idx].copyWith(checkpoint: turnCp);
            }
          }
          _markLastAssistantContinuable();
          _isLoading = false;
          _loadingStatus = '';
          _currentFileOperation = null;
          _currentFilePath = null;
          _isErrorReportDraft = false;
          _isSending = false; // ✅ FIX: Limpiar flag de envío
        });
        _clearAgentWorkingIndicator();
        await _saveConversation();
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        final friendly = _formatReadableError(e);
        setState(() {
          _isLoading = false;
          _loadingStatus = '';
          _currentFileOperation = null;
          _currentFilePath = null;
          _isErrorReportDraft = false;
          _isSending = false;
          final finalized = _finalizeStreamingResponse(friendly);
          if (!finalized) {
            _messages.add(
              Message(
                role: 'assistant',
                content: friendly,
                timestamp: DateTime.now(),
              ),
            );
          }
        });
        _clearAgentWorkingIndicator();
        unawaited(_saveConversation());
        _scrollToBottom();
      }
    } finally {
      // ✅ FIX: Asegurar que siempre se limpie el flag de envío
      if (mounted) {
        _isSending = false;
      }
    }
  }

  void _handlePendingActionsFromService(
    List<Map<String, dynamic>> pendingActionsList,
  ) {
    if (!mounted) return;

    final pendingActions = pendingActionsList.map((action) {
      return PendingAction(
        id: action['id'] as String,
        functionName: action['functionName'] as String,
        arguments: Map<String, dynamic>.from(action['arguments']),
        description: action['description'] as String,
        timestamp: action['timestamp'] != null
            ? DateTime.parse(action['timestamp'] as String)
            : DateTime.now(),
        toolCallId: action['toolCallId'] as String?,
        reasoning: action['reasoning'] as String?,
        diff: action['diff'] as String?,
        oldContent: action['oldContent'] as String?,
        newContent: action['newContent'] as String?,
      );
    }).toList();

    setState(() {
      _isLoading = false;
      _pendingActionsShown = true;
      _messages.add(
        Message(
          role: 'assistant',
          content:
              'Esperando tu confirmación para ejecutar ${pendingActions.length} acción(es).',
          timestamp: DateTime.now(),
          pendingActions: pendingActions,
        ),
      );
    });
    _scrollToBottom();
  }

  // Manejar aceptación de acciones desde la tarjeta del chat
  Future<void> _handleAcceptActions(
    List<PendingAction> actions,
    int messageIndex,
  ) async {
    print('✅ Aceptando ${actions.length} acciones desde el chat');

    // Remover el mensaje con acciones pendientes y agregar timeline de progreso
    if (mounted) {
      setState(() {
        _messages.removeAt(messageIndex);
        _messages.insert(
          messageIndex,
          Message(
            role: 'assistant',
            content: 'Applying ${actions.length} change(s)',
            timestamp: DateTime.now(),
          ),
        );
        _streamingAssistantMessageIndex = messageIndex;
        _streamingAssistantText = '';
        _agentTimelineBuffer = 'Applying ${actions.length} change(s)';
        _agentLiveSteps.clear();
        _isLoading = true;
        _loadingStatus = 'Applying ${actions.length} change(s)';
        _pendingActionsShown = false;
      });
      _scrollToBottom();
    }

    await _executeConfirmedActions(actions);
  }

  // Informar cada rechazo al modelo como resultado role=tool y reanudar.
  Future<void> _handleRejectActions(
    List<PendingAction> actions,
    int messageIndex,
  ) async {
    print('❌ Rechazando acciones desde el chat');

    if (mounted) {
      setState(() {
        _messages.removeAt(messageIndex);
        _messages.insert(
          messageIndex,
          Message(
            role: 'assistant',
            content: '❌ Acciones canceladas por el usuario.',
            timestamp: DateTime.now(),
          ),
        );
        _isLoading = true;
        _pendingActionsShown = false;
      });
      _scrollToBottom();
    }

    await _executeConfirmedActions(actions, rejected: true);
  }

  Future<void> _executeConfirmedActions(
    List<PendingAction> acceptedActions, {
    bool rejected = false,
  }) async {
    if (_openAIService == null) return;
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _loadingStatus = rejected
          ? 'Informando acciones rechazadas...'
          : 'Ejecutando acciones confirmadas...';
    });

    try {
      final projectPath =
          widget.projectPath ?? await ProjectService.getProjectPath();

      // Checkpoint automático ANTES de mutar archivos (time-travel).
      if (!rejected) {
        final affectedPaths = _extractAffectedFilePaths(acceptedActions);
        await _createTurnCheckpoint(
          affectedPaths,
          projectPath: projectPath,
        );
      }
      final turnCheckpoint = _turnCheckpoint;

      for (final action in acceptedActions) {
        if (!rejected) {
          _handleStepProgress(_statusForPendingAction(action));
        }
        final result = rejected
            ? 'Error: Acción rechazada por el usuario'
            : await _openAIService!.executeSingleTool(
                action.functionName,
                action.arguments,
                projectPath,
                onFileOperation: _handleAgentFileOperation,
              );

        if (!rejected) {
          final failed = result.startsWith('❌') ||
              result.startsWith('Error') ||
              result.toLowerCase().contains('errores de compilación');
          _handleStepProgress(
            failed
                ? 'Failed ${action.functionName}'
                : 'Completed ${action.functionName}',
          );
        }

        _apiMessages.add({
          'role': 'tool',
          'tool_call_id': action.toolCallId ?? action.id,
          'name': action.functionName,
          'content': result,
        });
      }

      // Conservar la burbuja de progreso; no borrar la timeline de Apply.
      _beginStreamingResponse(keepBubble: true, clearTimeline: false);
      final autoMode = await SettingsService.getAutoMode();
      final effectiveModel = autoMode
          ? (_openAIService!.lastAutoModel ?? _openAIService!.model)
          : _openAIService!.model;
      final response = await _openAIService!
          .continueAgentLoop(
            messages: _apiMessages,
            model: effectiveModel,
            projectPath: projectPath,
            autoApplyEdits: _chatMode == ChatAgentMode.agent,
            autoMode: autoMode,
            activeFilePath: _effectiveActiveFilePath,
            resetReadFiles: false,
            onBeforeAutoEdits: _chatMode == ChatAgentMode.agent
                ? (paths) => _createTurnCheckpoint(
                      paths,
                      projectPath: projectPath,
                    )
                : null,
            onPendingActions: _handlePendingActionsFromService,
            onFileOperation: _handleAgentFileOperation,
            onStreamChunk: _handleStreamChunk,
            onStepProgress: _handleStepProgress,
            onIdeControl: _handleIdeControl,
          )
          .timeout(
            _agentTurnTimeout,
            onTimeout: () {
              throw TimeoutException(
                'La solicitud tardó demasiado. Intenta de nuevo con un mensaje más corto.',
              );
            },
          );

      // El loop se pausó otra vez y el callback ya insertó una nueva tarjeta.
      if (_pendingActionsShown &&
          response.toLowerCase().startsWith('esperando tu confirmación')) {
        _clearAgentWorkingIndicator();
        return;
      }

      final assistantMsg = Message(
        role: 'assistant',
        content: response,
        timestamp: DateTime.now(),
        checkpoint: turnCheckpoint,
      );
      final finalizedStream = _finalizeStreamingResponse(
        response,
        checkpoint: turnCheckpoint,
      );

      // Guardar respuesta del asistente en memoria persistente
      await ConversationMemoryService.addMessage(
        role: 'assistant',
        content: response,
        sessionId: _currentSessionId,
      );

      if (mounted) {
        setState(() {
          if (!finalizedStream) {
            _messages.add(assistantMsg);
          } else if (turnCheckpoint != null) {
            // Asegurar checkpoint en el mensaje streameado finalizado.
            final idx = _messages.lastIndexWhere(
              (m) => m.role == 'assistant' && m.content == response,
            );
            if (idx >= 0 && _messages[idx].checkpoint == null) {
              _messages[idx] =
                  _messages[idx].copyWith(checkpoint: turnCheckpoint);
            }
          }
          _markLastAssistantContinuable();
          _isLoading = false;
          _loadingStatus = '';
          _currentFileOperation = null;
          _currentFilePath = null;
          _pendingActionsShown = false;
        });
        _clearAgentWorkingIndicator();
        await _saveConversation();
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        final friendly = _formatReadableError(e);
        setState(() {
          _isLoading = false;
          _loadingStatus = '';
          final finalized = _finalizeStreamingResponse(friendly);
          if (!finalized) {
            _messages.add(
              Message(
                role: 'assistant',
                content: friendly,
                timestamp: DateTime.now(),
              ),
            );
          }
        });
        _clearAgentWorkingIndicator();
        _scrollToBottom();
      }
    }
  }

  String _formatReadableError(Object e) {
    if (e is TimeoutException) {
      return '⏱️ La solicitud tardó demasiado. Intenta con un mensaje más corto o verifica tu conexión.';
    }
    var raw = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    final lower = raw.toLowerCase();
    if (lower.contains('solicitud cancelada')) {
      return '⏸️ Solicitud cancelada por el usuario.';
    }
    if (lower.contains('timeout') && !lower.contains('openai')) {
      return '⏱️ La solicitud tardó demasiado. Intenta con un mensaje más corto.';
    }
    if (lower.contains('socketexception') ||
        lower.contains('no se pudo conectar a openai')) {
      return '🌐 Error de conexión con OpenAI. Verifica tu internet e intenta de nuevo.';
    }
    // Si viene JSON crudo de OpenAI, extraer error.message legible.
    final jsonStart = raw.indexOf('{');
    if (jsonStart >= 0 && raw.contains('"error"')) {
      try {
        final decoded = jsonDecode(raw.substring(jsonStart));
        if (decoded is Map && decoded['error'] is Map) {
          final err = decoded['error'] as Map;
          final msg = err['message']?.toString() ?? '';
          final code = err['code']?.toString() ?? '';
          if (msg.isNotEmpty) {
            return '⚠️ OpenAI${code.isNotEmpty ? ' ($code)' : ''}: $msg';
          }
        }
      } catch (_) {}
    }
    return '⚠️ $raw';
  }

  /// Llamar dentro de setState tras finalizar un turno del agente.
  void _markLastAssistantContinuable() {
    if (_openAIService?.lastRunHitIterationLimit != true) return;
    final idx = _messages.lastIndexWhere((m) => m.role == 'assistant');
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(canContinueTask: true);
    }
  }

  /// Reanuda otros [OpenAIService.defaultMaxIterations] pasos del agente.
  Future<void> _continueAgentTask(int messageIndex) async {
    if (_openAIService == null || _isLoading || _isSending) return;
    if (messageIndex >= 0 && messageIndex < _messages.length) {
      setState(() {
        _messages[messageIndex] =
            _messages[messageIndex].copyWith(canContinueTask: false);
      });
    }

    // Tras reiniciar la app no hay historial API: reenviar como mensaje.
    if (_apiMessages.isEmpty) {
      _messageController.text = OpenAIService.continueTaskPrompt;
      await _sendMessage();
      return;
    }

    final projectPath =
        widget.projectPath ?? await ProjectService.getProjectPath();
    _apiMessages.add({
      'role': 'user',
      'content': OpenAIService.continueTaskPrompt,
    });
    _turnCheckpoint = null;
    setState(() {
      _isLoading = true;
      _loadingStatus = 'Continuing task';
      _pendingActionsShown = false;
      _beginStreamingResponse();
    });
    _scrollToBottom();

    try {
      final autoMode = await SettingsService.getAutoMode();
      final effectiveModel = autoMode
          ? (_openAIService!.lastAutoModel ?? _openAIService!.model)
          : _openAIService!.model;
      final response = await _openAIService!
          .continueAgentLoop(
            messages: _apiMessages,
            model: effectiveModel,
            projectPath: projectPath,
            autoApplyEdits: _chatMode == ChatAgentMode.agent,
            autoMode: autoMode,
            activeFilePath: _effectiveActiveFilePath,
            resetReadFiles: false,
            onBeforeAutoEdits: _chatMode == ChatAgentMode.agent
                ? (paths) => _createTurnCheckpoint(
                      paths,
                      projectPath: projectPath,
                    )
                : null,
            onPendingActions: _handlePendingActionsFromService,
            onFileOperation: _handleAgentFileOperation,
            onStreamChunk: _handleStreamChunk,
            onStepProgress: _handleStepProgress,
            onIdeControl: _handleIdeControl,
          )
          .timeout(_agentTurnTimeout);

      if (_pendingActionsShown &&
          response.toLowerCase().startsWith('esperando tu confirmación')) {
        _clearAgentWorkingIndicator();
        return;
      }

      final turnCheckpoint = _turnCheckpoint;
      final finalizedStream = _finalizeStreamingResponse(
        response,
        checkpoint: turnCheckpoint,
      );
      await ConversationMemoryService.addMessage(
        role: 'assistant',
        content: response,
        sessionId: _currentSessionId,
      );
      if (!mounted) return;
      setState(() {
        if (!finalizedStream) {
          _messages.add(
            Message(
              role: 'assistant',
              content: response,
              timestamp: DateTime.now(),
              checkpoint: turnCheckpoint,
            ),
          );
        }
        _markLastAssistantContinuable();
        _isLoading = false;
        _loadingStatus = '';
        _currentFileOperation = null;
        _currentFilePath = null;
      });
      _clearAgentWorkingIndicator();
      await _saveConversation();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final friendly = _formatReadableError(e);
      setState(() {
        _isLoading = false;
        _loadingStatus = '';
        final finalized = _finalizeStreamingResponse(friendly);
        if (!finalized) {
          _messages.add(
            Message(
              role: 'assistant',
              content: friendly,
              timestamp: DateTime.now(),
            ),
          );
        }
        if (messageIndex >= 0 && messageIndex < _messages.length) {
          _messages[messageIndex] =
              _messages[messageIndex].copyWith(canContinueTask: true);
        }
      });
      _clearAgentWorkingIndicator();
      _scrollToBottom();
    }
  }

  /// Mata el runner local (HTML/Node/etc). Con runInShell el shell puede
  /// morir y dejar python http.server zombie → "Address already in use".
  Future<void> _killLocalRunner({int? preferredPort}) async {
    final process = _runningProcess;
    _runningProcess = null;
    if (process != null) {
      try {
        process.kill(ProcessSignal.sigterm);
        await process.exitCode.timeout(
          const Duration(milliseconds: 800),
          onTimeout: () {
            try {
              process.kill(ProcessSignal.sigkill);
            } catch (_) {}
            return -1;
          },
        );
      } catch (_) {
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    }
    if (preferredPort != null) {
      await ProjectTypeDetector.killProcessOnPort(preferredPort);
    }
    // Puerto histórico de HTML estático
    await ProjectTypeDetector.killProcessOnPort(8000);
  }

  void _stopRequest() {
    print('🛑 Deteniendo petición...');

    // ✅ FIX: Cancelar petición HTTP / stream SSE
    _openAIService?.cancelRequest();

    // Detener flutter run real vía DebugConsoleService
    unawaited(_debugService.requestStop());

    // ✅ FIX: Detener proceso local (runners no-Flutter) si existe
    unawaited(_killLocalRunner());

    // ✅ NUEVO: Marcar último mensaje del usuario como cancelado
    if (_messages.isNotEmpty && _messages.last.role == 'user') {
      final lastMessage = _messages.last;
      final cancelledMessage = Message(
        role: lastMessage.role,
        content: lastMessage.content,
        timestamp: lastMessage.timestamp,
        imageUrls: lastMessage.imageUrls,
        codeBlock: lastMessage.codeBlock,
        filePath: lastMessage.filePath,
        pendingActions: lastMessage.pendingActions,
        isCancelled: true, // ✅ Marcar como cancelado
      );
      _messages[_messages.length - 1] = cancelledMessage;
    }

    // ✅ FIX: Limpiar TODO el estado para evitar cuelgues
    if (mounted) {
      setState(() {
        _isLoading = false;
        _loadingStatus = '';
        _currentFileOperation = null;
        _currentFilePath = null;
        _isRunning = false;
        _isDebugging = false;
        _isSending = false; // ✅ FIX: Limpiar flag de envío
        _isErrorReportDraft = false;
      });
    }

    _debugService.setRunning(false);
    _debugService.setCompilationProgress(0.0, 'Detenido');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Operación cancelada'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.orange,
        ),
      );
    }

    print('✅ Estado limpiado correctamente');
  }

  void _scrollToBottom() {
    _scrollToLatestConversation();
  }

  /// Lleva el chat al final (última conversación). Reintenta tras layout
  /// porque al abrir la app el ListView aún no tiene maxScrollExtent.
  void _scrollToLatestConversation({bool force = false}) {
    void tryScroll({required bool animate}) {
      if (!mounted || !_scrollController.hasClients) return;
      try {
        final pos = _scrollController.position;
        final target = pos.maxScrollExtent;
        if (target <= 0) return;
        // Si el usuario subió a leer historial, no forzar (salvo force=true).
        if (!force && (target - pos.pixels) > 120) return;
        if (!force && (target - pos.pixels).abs() < 8) return;
        // En streaming preferir jumpTo (animateTo se atrasa con muchos chunks).
        if (animate && !force) {
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(target);
        }
      } catch (e) {
        print('⚠️ Error en _scrollToLatestConversation: $e');
      }
    }

    // Frame 1: layout inicial · Frame 2: alturas de burbujas · delay: imágenes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tryScroll(animate: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        tryScroll(animate: !force);
        Future<void>.delayed(const Duration(milliseconds: 80), () {
          tryScroll(animate: false);
        });
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          tryScroll(animate: false);
        });
      });
    });
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage().timeout(
        const Duration(seconds: 60),
        onTimeout: () => <XFile>[],
      );

      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images.map((img) => img.path));
        });
      }
    } catch (e) {
      print('❌ Error al seleccionar imagen: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFilePath = result.files.single.path!;
        });
      }
    } catch (e) {
      print('❌ Error al seleccionar archivo: $e');
    }
  }

  // Métodos de Run and Debug
  /// Verifica qué archivos faltan en el proyecto para poder ejecutarlo
  Future<List<String>> _checkMissingProjectFiles(String projectPath) async {
    final missingFiles = <String>[];

    // Verificar archivos clave para diferentes tipos de proyectos
    final keyFiles = {
      'pubspec.yaml': 'Flutter',
      'package.json': 'Node.js/React/Next.js/Vue',
      'main.py': 'Python',
      'app.py': 'Python/Flask',
      'requirements.txt': 'Python',
      'manage.py': 'Django',
      'go.mod': 'Go',
      'Cargo.toml': 'Rust',
      'pom.xml': 'Maven (Java)',
      'build.gradle': 'Gradle (Java)',
      'index.html': 'HTML estático',
    };

    for (final entry in keyFiles.entries) {
      final file = File('$projectPath/${entry.key}');
      if (!await file.exists()) {
        missingFiles.add('${entry.key} (${entry.value})');
      }
    }

    return missingFiles;
  }

  String _runningPreviewLabel(String platform, {bool debug = false}) {
    final suffix = debug ? ' (DEBUG)' : '';
    if (platform.toLowerCase() == 'web') {
      return 'Aplicación web ejecutándose$suffix';
    }
    return '${ProjectPlatformSupport.humanLabel(platform)} ejecutándose$suffix';
  }

  /// Ejecuta `_handleRun` desde el agente y espera el resultado REAL de la
  /// compilación (app lista o fallo con el output de error).
  Future<String> _runAppAndWaitForResult() async {
    var runExited = false;
    final runFuture = _handleRun(showFailureDialog: false);
    unawaited(runFuture.whenComplete(() => runExited = true));

    // Dar tiempo a que _handleRun limpie logs y arranque flutter run.
    await Future.delayed(const Duration(milliseconds: 250));

    final plat = _platformService.selectedPlatform;
    final deadline = DateTime.now().add(const Duration(seconds: 120));

    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return 'Error: ventana cerrada durante la compilación.';

      final outSnapshot = List<String>.from(_debugService.output);
      final isReadyLine = outSnapshot.any((line) {
        final l = line.toLowerCase();
        return l.contains('is being served at') ||
            l.contains('serving at http') ||
            l.contains('flutter run key commands') ||
            l.contains('to hot reload') ||
            l.contains('an observatory debugger') ||
            l.contains('dart vm service is listening') ||
            l.contains('application finished launching');
      });

      if (!runExited &&
          _debugService.isRunning &&
          (AdvancedDebuggingService.supportsHotReload ||
              isReadyLine ||
              (_debugService.compilationProgress >= 1.0 &&
                  (_debugService.compilationStatus
                          .toLowerCase()
                          .contains('ejecut') ||
                      _debugService.compilationStatus
                          .toLowerCase()
                          .contains('served'))))) {
        final url = _debugService.appUrl;
        return '✅ App compilada y ejecutándose en $plat'
            '${url != null && url.isNotEmpty ? ' ($url)' : ''}.';
      }

      if (runExited) {
        final rawOut = outSnapshot.join('\n');
        final status = _debugService.compilationStatus;
        final lowerOut = rawOut.toLowerCase();
        final failed = !_debugService.isRunning ||
            status.contains('❌') ||
            lowerOut.contains('failed to compile') ||
            lowerOut.contains('error:') ||
            lowerOut.contains('no se encontró dispositivo');
        if (!failed && isReadyLine) {
          return '✅ App ejecutada en $plat.';
        }
        final compact = _compactErrorForChat(
          rawOut.isNotEmpty ? rawOut : status,
        );
        return '''
❌ La compilación/ejecución falló en $plat.

Output:
$compact

Si el error está dentro de .pub-cache, NO repitas flutter clean/pub get: fija la versión exacta sin ^ en pubspec.yaml o ejecuta flutter pub cache repair.
'''.trim();
      }

      await Future.delayed(const Duration(milliseconds: 400));
    }

    final compact = _compactErrorForChat(_debugService.output.join('\n'));
    return '⏱️ Timeout esperando compilación en $plat (120s).\n\nOutput:\n$compact';
  }

  Future<void> _handleRun({bool showFailureDialog = true}) async {
    try {
      // Obtener projectPath con logging detallado
      final widgetProjectPath = widget.projectPath;
      final serviceProjectPath = await ProjectService.getProjectPath();
      final projectPath = widgetProjectPath ?? serviceProjectPath;

      print('🔍 ChatScreen._handleRun: VERIFICACIÓN DE PROYECTO');
      print('   widget.projectPath: $widgetProjectPath');
      print('   ProjectService.getProjectPath(): $serviceProjectPath');
      print('   projectPath final a usar: $projectPath');

      if (projectPath == null || projectPath.isEmpty) {
        print('❌ ChatScreen._handleRun: NO HAY PROYECTO');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay proyecto cargado'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Verificar que el directorio existe
      final projectDir = Directory(projectPath);
      if (!await projectDir.exists()) {
        print('❌ ChatScreen._handleRun: EL DIRECTORIO NO EXISTE: $projectPath');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('El proyecto no existe: $projectPath'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // DETECCIÓN UNIVERSAL DE TIPO DE PROYECTO (como Cursor IDE)
      print('🔍 Detectando tipo de proyecto...');
      final projectType = await ProjectTypeDetector.detectProjectType(
        projectPath,
      );

      if (projectType == ProjectType.unknown) {
        print(
          '❌ ChatScreen._handleRun: TIPO DE PROYECTO DESCONOCIDO: $projectPath',
        );

        // ✅ FIX: Verificar archivos faltantes y ofrecer sugerencias inteligentes
        final missingFiles = await _checkMissingProjectFiles(projectPath);

        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSending = false;
          });

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: CursorTheme.surface,
              title: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.orange,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Proyecto incompleto',
                      style: TextStyle(color: CursorTheme.textPrimary),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No se pudo detectar el tipo de proyecto porque faltan archivos necesarios.',
                      style: TextStyle(color: CursorTheme.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    if (missingFiles.isNotEmpty) ...[
                      Text(
                        'Archivos faltantes:',
                        style: const TextStyle(
                          color: CursorTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...missingFiles.map(
                        (file) => Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning,
                                color: Colors.orange,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  file,
                                  style: TextStyle(
                                    color: CursorTheme.textSecondary,
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.lightbulb_outline,
                                color: Colors.blue,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Sugerencia',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pide al agente que cree la estructura completa del proyecto. Por ejemplo:\n\n'
                            '"Crea un proyecto Flutter completo para la calculadora con pubspec.yaml y main.dart"',
                            style: TextStyle(
                              color: CursorTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Entendido',
                    style: TextStyle(color: CursorTheme.primary),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }

      final projectTypeName = ProjectTypeDetector.getProjectTypeName(
        projectType,
      );
      final projectTypeIcon = ProjectTypeDetector.getProjectTypeIcon(
        projectType,
      );
      print('✅ Tipo de proyecto: $projectTypeIcon $projectTypeName');

      // Obtener comando de ejecución para el tipo de proyecto
      final runCommand = await ProjectTypeDetector.getRunCommand(
        projectPath,
        projectType,
        isDebug: false,
      );

      print('🚀 Comando a ejecutar: $runCommand');
      print('   Requiere dispositivo: ${runCommand.requiresDevice}');

      // Configurar estado de ejecución
      setState(() {
        _isRunning = true;
        _isDebugging = false;
      });

      _debugService.setRunning(true);
      _debugService.resetCompilationProgress();
      _debugService.setCompilationProgress(
        0.05,
        'Iniciando $projectTypeName...',
      );
      // Abrir Debug Console en Output para logs en vivo
      _debugService.clearAll();
      _debugService.showOutputTab();

      // Obtener nombre del proyecto
      final projectName = projectPath.split('/').last;
      print('✅ ChatScreen._handleRun: Proyecto válido encontrado');
      print('   Nombre del proyecto: $projectName');
      print('   Tipo: $projectTypeIcon $projectTypeName');
      print('   Ruta del proyecto: $projectPath');

      // Detectar URL para proyectos web
      String? detectedUrl;

      // ✅ BANDERA: Detectar si hay error de soporte web
      bool hasWebSupportError = false;

      // Para Flutter, usar el sistema existente con dispositivos
      if (projectType == ProjectType.flutter) {
        // Sincronizar plataforma antes de ejecutar
        _selectedPlatform = _platformService.selectedPlatform;
        print('🚀 Ejecutando Flutter en plataforma: $_selectedPlatform');
        print(
          '🔧 PlatformService.selectedPlatform: ${_platformService.selectedPlatform}',
        );

        // Validar carpetas del proyecto (macos/, web/, ios/, android/)
        final requestedPlatform = _selectedPlatform.isNotEmpty
            ? _selectedPlatform
            : (_platformService.selectedPlatform.isNotEmpty
                ? _platformService.selectedPlatform
                : 'macos');
        final platformToUse = await _ensureCompatiblePlatform(
          projectPath: projectPath,
          requestedPlatform: requestedPlatform,
        );
        print('✅ Usando plataforma: $platformToUse');
        print('   _selectedPlatform: $_selectedPlatform');
        print(
          '   _platformService.selectedPlatform: ${_platformService.selectedPlatform}',
        );
        _debugService.setCompilationProgress(
          0.08,
          'Preparando ${ProjectPlatformSupport.humanLabel(platformToUse)}...',
        );

        // Web → web-server + Preview WebView interno (nunca Chrome externo).
        // SIEMPRE debug: Hot Reload/Restart y DWDS requieren JIT; release
        // rompe los botones ⚡/🔄 y muestra "missing or invalid authentication code".
        final result = await AdvancedDebuggingService.runFlutterApp(
          projectPath: projectPath,
          platform: platformToUse,
          mode: 'debug',
          useWebServer: true,
          onOutput: (line) async {
            _debugService.ingestProcessLine(line);
            _maybeCaptureVmServiceUri(line);

            print('📥 Flutter output: $line');

            // ✅ DETECCIÓN ESPECIAL: Proyecto sin soporte web
            if (line.contains(
                  'This application is not configured to build on the web',
                ) ||
                line.contains(
                  'To add web support to a project, run `flutter create .`',
                ) ||
                (line.contains('PathNotFoundException') &&
                    line.contains('web/') &&
                    line.contains('No such file or directory'))) {
              print('🔴 Error detectado: Proyecto sin soporte web');
              hasWebSupportError =
                  true; // ✅ Marcar que hay error de soporte web

              // ✅ EJECUTAR SOLUCIÓN AUTOMÁTICAMENTE (como Cursor)
              _debugService.addOutput(
                '\n⚠️ PROYECTO SIN SOPORTE WEB DETECTADO\n',
              );
              _debugService.addOutput(
                '🔧 Agregando soporte web automáticamente...\n\n',
              );

              // Ejecutar flutter create . automáticamente
              try {
                _debugService.addOutput('📝 Ejecutando: flutter create .\n');
                final createResult = await Process.run('flutter', [
                  'create',
                  '.',
                ], workingDirectory: projectPath);

                if (createResult.exitCode == 0) {
                  _debugService.addOutput(
                    '✅ Soporte web agregado exitosamente!\n',
                  );
                  _debugService.addOutput(
                    '🔄 Intentando compilar de nuevo...\n\n',
                  );

                  // ✅ REINTENTAR COMPILACIÓN AUTOMÁTICAMENTE
                  hasWebSupportError = false; // Resetear flag

                  // Mostrar mensaje de éxito
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '✅ Soporte web agregado. Reintentando compilación...',
                        ),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                } else {
                  _debugService.addOutput('❌ Error al agregar soporte web:\n');
                  _debugService.addOutput('${createResult.stderr}\n');
                  _debugService.addProblem('Error ejecutando flutter create');

                  // Detener proceso
                  setState(() {
                    _isRunning = false;
                  });
                  _debugService.setRunning(false);
                  _debugService.setAppUrl(null);
                  _debugService.setCompilationProgress(
                    0.0,
                    'Error: No se pudo agregar soporte web',
                  );
                }
              } catch (e) {
                _debugService.addOutput(
                  '❌ Error al ejecutar flutter create: $e\n',
                );
                _debugService.addProblem('Error: $e');

                // Detener proceso
                setState(() {
                  _isRunning = false;
                });
                _debugService.setRunning(false);
                _debugService.setAppUrl(null);
                _debugService.setCompilationProgress(
                  0.0,
                  'Error al agregar soporte web',
                );
              }

              // No marcar como error crítico adicional, es un problema del proyecto, no de la app
              // Ya se agregó a problemas arriba, así que no procesamos más esta línea
            } else {
              // Detectar errores (solo si no es el error de soporte web)
              final lowerLine = line.toLowerCase();
              if (RegExp(
                    r'\.dart:\d+:\d+:\s*(error|warning):',
                  ).hasMatch(line) ||
                  (lowerLine.contains('error:') &&
                      !lowerLine.contains('no error')) ||
                  (lowerLine.contains('failed') &&
                      !lowerLine.contains('no devices found')) ||
                  lowerLine.contains('undefined name') ||
                  lowerLine.contains('undefined class') ||
                  lowerLine.contains('undefined method') ||
                  lowerLine.contains('undefined getter') ||
                  lowerLine.contains('syntax error') ||
                  (lowerLine.contains('cannot') &&
                      (lowerLine.contains('find') ||
                          lowerLine.contains('resolve')))) {
                _debugService.addProblem(line);
                print('🔴 Error detectado: $line');
              }
            }

            // Fase / progreso en vivo desde stdout
            _debugService.updateProgressFromFlutterLine(line);

            // URL Preview: web + Android/iOS (Preview) vía web-server
            final embedsPreview = platformToUse == 'web' ||
                platformToUse == 'android' ||
                platformToUse == 'ios';
            if (embedsPreview) {
              print('🔍 Buscando URL Preview ($platformToUse): "$line"');

              // Solo URL de la APP (web-server). NUNCA DevTools → Preview.
              RegExpMatch? urlMatch = RegExp(
                r'(?:is being served at|serving at|Serving at)\s*(https?://[^\s]+)',
                caseSensitive: false,
              ).firstMatch(line);
              if (urlMatch != null) {
                final candidate = urlMatch.group(1)!.trim();
                if (DebugConsoleService.isPreviewAppUrl(candidate)) {
                  detectedUrl = candidate;
                  _debugService.setAppUrl(detectedUrl);
                  print('🌐 ✅ URL Preview (served at): $detectedUrl');
                  if (mounted) {
                    setState(() {
                      _isRunning = true;
                    });
                  }
                  _debugService.setRunning(true);
                  _debugService.setCompilationProgress(
                    1.0,
                    'Aplicación web en Preview',
                  );
                }
              } else if (line.toLowerCase().contains('devtools') &&
                  line.toLowerCase().contains('available at')) {
                // DevTools → VM Service, no Preview.
                final dt = RegExp(
                  r'available at:\s*(https?://[^\s]+)',
                  caseSensitive: false,
                ).firstMatch(line);
                if (dt != null) {
                  _debugService.setVmServiceUri(dt.group(1)!.trim());
                  print('🧩 DevTools/VM (no Preview): ${dt.group(1)}');
                }
              } else if (!line.toLowerCase().contains('devtools') &&
                  !line.toLowerCase().contains('vm service') &&
                  !line.toLowerCase().contains('observatory')) {
                // http://127.0.0.1:PORT sin query de DevTools
                urlMatch = RegExp(
                  r'http://(localhost|127\.0\.0\.1):(\d+)\b',
                ).firstMatch(line);
                if (urlMatch != null) {
                  final host = urlMatch.group(1)!;
                  final port = urlMatch.group(2)!;
                  final candidate = 'http://$host:$port';
                  if (DebugConsoleService.isPreviewAppUrl(candidate)) {
                    detectedUrl = candidate;
                    _debugService.setAppUrl(detectedUrl);
                    print('🌐 ✅ URL Preview: $detectedUrl');
                    if (mounted) {
                      setState(() {
                        _isRunning = true;
                      });
                    }
                    _debugService.setRunning(true);
                    _debugService.setCompilationProgress(
                      1.0,
                      _runningPreviewLabel(platformToUse),
                    );
                  }
                }
              }

              // ✅ También detectar cuando Chrome se abre (indica que la app está lista)
              // PERO solo si NO hay error de soporte web
              if (!hasWebSupportError &&
                  line.contains('Chrome') &&
                  (line.contains('Launching') || line.contains('Starting'))) {
                // Si no se detectó URL aún, usar localhost:8080 como fallback (puerto común de Flutter web)
                if (detectedUrl == null) {
                  detectedUrl = 'http://localhost:8080';
                  _debugService.setAppUrl(detectedUrl);
                  print(
                    '🌐 ✅ URL establecida por defecto (Chrome detectado): $detectedUrl',
                  );
                  if (mounted) {
                    setState(() {
                      _isRunning = true;
                    });
                  }
                  _debugService.setRunning(true);
                  _debugService.setCompilationProgress(
                    1.0,
                    _runningPreviewLabel(platformToUse),
                  );
                }
              }
            }
          },
          onError: (error) {
            _debugService.addProblem(error.toString());
            _debugService.setCompilationProgress(0.0, 'Error en compilación');
          },
        );

        // ✅ NO establecer URL final si hay error de soporte web
        if (!hasWebSupportError && detectedUrl != null) {
          _debugService.setAppUrl(detectedUrl);
          print('🌐 URL final establecida: $detectedUrl');
        } else if (hasWebSupportError) {
          _debugService.setAppUrl(null);
          print(
            '🚫 NO estableciendo URL final: Error de soporte web detectado',
          );
        }

        // Preview embebido (web / android / ios) conserva appUrl en el WebView.
        final embedsOk = platformToUse == 'web' ||
            platformToUse == 'android' ||
            platformToUse == 'ios';
        if (embedsOk && result.success) {
          print('✅ Preview $platformToUse OK — manteniendo URL / _isRunning');
          if (mounted) {
            setState(() {
              _isRunning = true;
            });
          }
          _debugService.setRunning(true);
          _debugService.setCompilationProgress(
            1.0,
            platformToUse == 'web'
                ? 'Aplicación web ejecutándose'
                : '${ProjectPlatformSupport.humanLabel(platformToUse)} en Preview',
          );
        } else if (result.success) {
          print(
            '✅ Flutter $platformToUse en dispositivo/emulador nativo',
          );
          if (mounted) {
            setState(() {
              _isRunning = true;
            });
          }
          _debugService.setRunning(true);
          // Nativo externo: no hay WebView URL
          if (!embedsOk) {
            _debugService.setAppUrl(null);
          }
          _debugService.setCompilationProgress(
            1.0,
            'Aplicación ejecutándose en ${platformToUse.toUpperCase()}',
          );
        } else {
          final errorMessage = result.errors.isNotEmpty
              ? result.errors.join('\n')
              : 'La compilación falló. Revisa el Debug Console para más detalles.';
          final isNoDeviceError =
              errorMessage.contains('No se encontró dispositivo disponible') ||
              errorMessage.contains(
                'No se encontró dispositivo para la plataforma',
              );
          final isAndroidOrIOS =
              platformToUse.toLowerCase() == 'android' ||
              platformToUse.toLowerCase() == 'ios';

          if (isAndroidOrIOS && isNoDeviceError) {
            final tip = platformToUse.toLowerCase() == 'android'
                ? 'Abre Android Studio → Device Manager e inicia un emulador AVD, '
                    'luego pulsa Run otra vez. (Voryxel Code ya no cambia solo a Web.)'
                : 'Abre el Simulador iOS desde Xcode y vuelve a pulsar Run. '
                    '(Voryxel Code ya no cambia solo a Web.)';
            _debugService.addDebugConsole(
              '📱 No hay dispositivo $platformToUse disponible.',
            );
            _debugService.addDebugConsole('💡 $tip');
            _debugService.setCompilationProgress(
              0.0,
              'Sin dispositivo $platformToUse — inicia el emulador',
            );
          }

          if (mounted) {
            setState(() {
              _isRunning = false;
            });
          }
          _debugService.setRunning(false);
          _debugService.setAppUrl(null);
          _debugService.setCompilationProgress(0.0, errorMessage);
        }

        if (!result.success && mounted && showFailureDialog) {
          final errorMessage = result.errors.isNotEmpty
              ? result.errors.join('\n')
              : 'La compilación falló. Revisa el Debug Console para más detalles.';
          _showCompilationFailureDialog(errorMessage);
        }
      } else {
        // EJECUCIÓN UNIVERSAL para otros lenguajes
        print(
          '🎯 Ejecutando comando personalizado: ${runCommand.command} ${runCommand.args.join(' ')}',
        );

        // Detectar si es un proceso de servidor de larga duración
        final isLongRunningServer =
            projectType == ProjectType.fastapi ||
            projectType == ProjectType.django ||
            projectType == ProjectType.flask ||
            projectType == ProjectType.nodejs ||
            projectType == ProjectType.react ||
            projectType == ProjectType.nextjs ||
            projectType == ProjectType.vue ||
            projectType == ProjectType.vite ||
            projectType == ProjectType.html ||
            runCommand.command.contains('uvicorn') ||
            runCommand.command.contains('gunicorn') ||
            runCommand.command.contains('runserver') ||
            runCommand.args.contains('http.server') ||
            runCommand.command.contains('npm') &&
                (runCommand.args.contains('start') ||
                    runCommand.args.contains('dev')) ||
            runCommand.command.contains('yarn') &&
                (runCommand.args.contains('start') ||
                    runCommand.args.contains('dev'));

        try {
          // Evitar "Address already in use" por servidor HTML zombie.
          await _killLocalRunner();

          final process = await Process.start(
            runCommand.command,
            runCommand.args,
            workingDirectory: runCommand.workingDirectory,
            // HTML: sin shell para que Stop mate a python (no un zsh huérfano).
            runInShell: projectType != ProjectType.html,
            environment: runCommand.environment,
          );

          // Guardar referencia al proceso para poder detenerlo
          _runningProcess = process;

          _debugService.addOutput(
            '$projectTypeIcon Ejecutando: ${runCommand.description}',
          );
          _debugService.addOutput(
            '📁 Directorio: ${runCommand.workingDirectory}',
          );
          _debugService.addOutput(
            '🚀 Comando: ${runCommand.command} ${runCommand.args.join(' ')}',
          );
          _debugService.addOutput('');
          _debugService.setCompilationProgress(0.2, 'Ejecutando...');

          // Variables para rastrear el estado del proceso
          bool hasReceivedOutput = false;
          bool urlDetected = false; // Flag para detectar URL solo una vez

          // HTML estático: python imprime "Serving HTTP on ::" (IPv6), no
          // "localhost" → el Preview se quedaba en "Esperando URL… 20%".
          if (projectType == ProjectType.html) {
            var port = '8000';
            for (final arg in runCommand.args) {
              if (RegExp(r'^\d+$').hasMatch(arg)) {
                port = arg;
                break;
              }
            }
            detectedUrl = 'http://127.0.0.1:$port';
            urlDetected = true;
            _debugService.setAppUrl(detectedUrl);
            _debugService.setCompilationProgress(
              1.0,
              'Página web en Preview ✅',
            );
            _debugService.setRunning(true);
            _debugService.addOutput('🌐 Preview → $detectedUrl');
            if (mounted) setState(() => _isRunning = true);
          }

          // Verificar si ya hay una URL establecida (por si acaso)
          if (_debugService.appUrl != null &&
              _debugService.appUrl!.isNotEmpty) {
            urlDetected = true;
            detectedUrl = _debugService.appUrl;
            print('🌐 URL ya establecida previamente: $detectedUrl');
          }

          // Limpiar timeout anterior si existe
          if (_startupTimeout != null) {
            _startupTimeout!.cancel();
            _startupTimeout = null;
          }

          // Escuchar stdout
          process.stdout.transform(utf8.decoder).listen((data) {
            hasReceivedOutput = true;
            if (_startupTimeout != null) {
              _startupTimeout!.cancel();
              _startupTimeout = null;
            }

            print('📥 STDOUT recibido (${data.length} chars)');

            for (var line in data.split('\n')) {
              if (line.trim().isEmpty) continue;
              _debugService.ingestProcessLine(line);

              print('🔍 Analizando línea STDOUT: "$line"');

              // Detectar URL SOLO UNA VEZ y solo en mensajes específicos de inicio de servidor
              // NO detectar en logs de peticiones HTTP (GET, POST, etc)
              // También verificar si ya hay una URL establecida en el servicio
              if (!urlDetected &&
                  (_debugService.appUrl == null ||
                      _debugService.appUrl!.isEmpty)) {
                final lowerLine = line.toLowerCase();

                // Solo buscar URL si la línea contiene indicadores claros de inicio de servidor
                // Y NO contiene indicadores de peticiones HTTP
                final isServerStartupMessage =
                    (lowerLine.contains('uvicorn running on') ||
                    lowerLine.contains('starting development server at') ||
                    lowerLine.contains('server running on') ||
                    lowerLine.contains('serving on') ||
                    lowerLine.contains('serving http') ||
                    lowerLine.contains('listening on'));
                final httpServerPort = RegExp(
                  r'serving http on .+ port (\d+)',
                  caseSensitive: false,
                ).firstMatch(line);

                final isHttpRequestLog =
                    lowerLine.contains('get ') ||
                    lowerLine.contains('post ') ||
                    lowerLine.contains('put ') ||
                    lowerLine.contains('delete ') ||
                    lowerLine.contains('" 200 ') ||
                    lowerLine.contains('" 404 ') ||
                    lowerLine.contains('" 500 ');

                if (isServerStartupMessage && !isHttpRequestLog) {
                  print(
                    '✅ Línea contiene indicador de inicio de servidor (no es log de petición)',
                  );

                  if (httpServerPort != null) {
                    final port = httpServerPort.group(1);
                    detectedUrl = 'http://127.0.0.1:$port';
                    _debugService.setAppUrl(detectedUrl);
                    urlDetected = true;
                    _debugService.setCompilationProgress(
                      1.0,
                      'Página web en Preview ✅',
                    );
                    print(
                      '🌐 ✅ URL python http.server → $detectedUrl',
                    );
                  } else if (line.contains('0.0.0.0:')) {
                    final portMatch = RegExp(
                      r'0\.0\.0\.0:(\d+)',
                    ).firstMatch(line);
                    if (portMatch != null) {
                      final port = portMatch.group(1);
                      detectedUrl = 'http://localhost:$port';
                      _debugService.setAppUrl(detectedUrl);
                      urlDetected = true;
                      print(
                        '🌐 ✅✅✅ URL DETECTADA EN STDOUT: 0.0.0.0:$port -> $detectedUrl (detección bloqueada para futuras líneas)',
                      );
                    }
                  } else if (line.contains('localhost:')) {
                    final portMatch = RegExp(
                      r'localhost:(\d+)',
                    ).firstMatch(line);
                    if (portMatch != null) {
                      final port = portMatch.group(1);
                      detectedUrl = 'http://localhost:$port';
                      _debugService.setAppUrl(detectedUrl);
                      urlDetected = true;
                      print(
                        '🌐 ✅✅✅ URL DETECTADA EN STDOUT: localhost:$port -> $detectedUrl (detección bloqueada)',
                      );
                    }
                  } else if (line.contains('127.0.0.1:')) {
                    final portMatch = RegExp(
                      r'127\.0\.0\.1:(\d+)',
                    ).firstMatch(line);
                    if (portMatch != null) {
                      final port = portMatch.group(1);
                      detectedUrl = 'http://127.0.0.1:$port';
                      _debugService.setAppUrl(detectedUrl);
                      urlDetected = true;
                      print(
                        '🌐 ✅✅✅ URL DETECTADA EN STDOUT: 127.0.0.1:$port -> $detectedUrl (detección bloqueada)',
                      );
                    }
                  }
                } else if (!isServerStartupMessage &&
                    !isHttpRequestLog &&
                    line.contains(':') &&
                    RegExp(r'\d+').hasMatch(line)) {
                  print(
                    '⚠️ Línea ignorada: no es mensaje de inicio de servidor ni petición HTTP',
                  );
                }
              }

              // Actualizar progreso basado en palabras clave
              final lowerLine = line.toLowerCase();
              if (lowerLine.contains('uvicorn running on') ||
                  lowerLine.contains('application startup complete')) {
                // La URL ya fue establecida cuando se detectó, no es necesario establecerla de nuevo
                // Esto evita notificaciones innecesarias que podrían causar múltiples aperturas del navegador
                _debugService.setCompilationProgress(
                  1.0,
                  'Servidor ejecutándose ✅',
                );
                _debugService.setRunning(true);
                print(
                  '✅ Servidor listo con URL: ${detectedUrl ?? "pendiente"}',
                );
                if (mounted) {
                  setState(() {
                    _isRunning = true; // Mantener en ejecución para servidores
                  });
                }
              } else if (lowerLine.contains('started server process')) {
                _debugService.setCompilationProgress(
                  0.8,
                  'Iniciando servidor...',
                );
              } else if (lowerLine.contains(
                'waiting for application startup',
              )) {
                _debugService.setCompilationProgress(
                  0.9,
                  'Preparando aplicación...',
                );
              } else if (lowerLine.contains('server') &&
                  (lowerLine.contains('running') ||
                      lowerLine.contains('started'))) {
                _debugService.setCompilationProgress(
                  1.0,
                  'Servidor ejecutándose',
                );
                _debugService.setRunning(true);
                if (mounted) {
                  setState(() {
                    _isRunning = true;
                  });
                }
              } else if (lowerLine.contains('listening') ||
                  lowerLine.contains('ready')) {
                _debugService.setCompilationProgress(0.9, 'Servidor listo');
                _debugService.setRunning(true);
                if (mounted) {
                  setState(() {
                    _isRunning = true;
                  });
                }
              } else if (lowerLine.contains('compil')) {
                _debugService.setCompilationProgress(0.5, 'Compilando...');
              } else if (lowerLine.contains('build')) {
                _debugService.setCompilationProgress(0.6, 'Construyendo...');
              }
            }
          });

          // Escuchar stderr
          process.stderr.transform(utf8.decoder).listen((data) {
            hasReceivedOutput = true;
            if (_startupTimeout != null) {
              _startupTimeout!.cancel();
              _startupTimeout = null;
            }

            print('📥 STDERR recibido (${data.length} chars)');

            for (var line in data.split('\n')) {
              if (line.trim().isEmpty) continue;
              _debugService.ingestProcessLine(line);

              print('🔍 Analizando línea STDERR: "$line"');

              // IMPORTANTE: Uvicorn envía sus logs INFO a stderr!
              // Detectar URL SOLO UNA VEZ en mensajes específicos de inicio de servidor
              // También verificar si ya hay una URL establecida en el servicio
              if (!urlDetected &&
                  (_debugService.appUrl == null ||
                      _debugService.appUrl!.isEmpty)) {
                final lowerLine = line.toLowerCase();

                // Solo buscar URL si la línea contiene indicadores claros de inicio de servidor
                // Y NO contiene indicadores de peticiones HTTP
                final isServerStartupMessage =
                    (lowerLine.contains('uvicorn running on') ||
                    lowerLine.contains('starting development server at') ||
                    lowerLine.contains('server running on') ||
                    lowerLine.contains('serving on') ||
                    lowerLine.contains('serving http') ||
                    lowerLine.contains('listening on'));
                final httpServerPort = RegExp(
                  r'serving http on .+ port (\d+)',
                  caseSensitive: false,
                ).firstMatch(line);

                final isHttpRequestLog =
                    lowerLine.contains('get ') ||
                    lowerLine.contains('post ') ||
                    lowerLine.contains('put ') ||
                    lowerLine.contains('delete ') ||
                    lowerLine.contains('" 200 ') ||
                    lowerLine.contains('" 404 ') ||
                    lowerLine.contains('" 500 ');

                if (isServerStartupMessage && !isHttpRequestLog) {
                  print(
                    '✅ Línea STDERR contiene indicador de inicio de servidor (no es log de petición)',
                  );

                  if (line.contains('0.0.0.0:')) {
                    final portMatch = RegExp(
                      r'0\.0\.0\.0:(\d+)',
                    ).firstMatch(line);
                    if (portMatch != null) {
                      final port = portMatch.group(1);
                      detectedUrl = 'http://localhost:$port';
                      _debugService.setAppUrl(detectedUrl);
                      urlDetected = true;
                      print(
                        '🌐 ✅✅✅ URL DETECTADA EN STDERR: 0.0.0.0:$port -> $detectedUrl (detección bloqueada)',
                      );
                    }
                  } else if (line.contains('localhost:')) {
                    final portMatch = RegExp(
                      r'localhost:(\d+)',
                    ).firstMatch(line);
                    if (portMatch != null) {
                      final port = portMatch.group(1);
                      detectedUrl = 'http://localhost:$port';
                      _debugService.setAppUrl(detectedUrl);
                      urlDetected = true;
                      print(
                        '🌐 ✅✅✅ URL detectada EN STDERR (localhost): $detectedUrl (detección bloqueada)',
                      );
                    }
                  } else if (line.contains('127.0.0.1:')) {
                    final portMatch = RegExp(
                      r'127\.0\.0\.1:(\d+)',
                    ).firstMatch(line);
                    if (portMatch != null) {
                      final port = portMatch.group(1);
                      detectedUrl = 'http://127.0.0.1:$port';
                      _debugService.setAppUrl(detectedUrl);
                      urlDetected = true;
                      print(
                        '🌐 ✅✅✅ URL detectada EN STDERR (127.0.0.1): $detectedUrl (detección bloqueada)',
                      );
                    }
                  }
                }
              }

              // Detectar errores críticos que impiden el inicio
              final lowerLine = line.toLowerCase();
              if (lowerLine.contains('error') ||
                  lowerLine.contains('failed') ||
                  lowerLine.contains('cannot') ||
                  lowerLine.contains('not found') ||
                  lowerLine.contains('command not found') ||
                  lowerLine.contains('no such file')) {
                _debugService.addProblem(line);

                // Si es un error crítico, detener el proceso
                if (lowerLine.contains('command not found') ||
                    lowerLine.contains('no such file') ||
                    lowerLine.contains('cannot find')) {
                  print('❌ Error crítico detectado, deteniendo proceso...');
                  if (mounted) {
                    setState(() {
                      _isRunning = false;
                    });
                  }
                  _debugService.setRunning(false);
                  _debugService.setCompilationProgress(
                    0.0,
                    'Error: Comando no encontrado',
                  );

                  // Intentar terminar el proceso
                  try {
                    process.kill();
                    _runningProcess = null;
                  } catch (e) {
                    print('⚠️ Error al terminar proceso: $e');
                  }

                  if (mounted) {
                    showDialog(
                      context: context,
                      builder: (context) => ErrorConfirmationDialog(
                        title: 'Error de ejecución',
                        message:
                            'No se pudo ejecutar el comando:\n\n$line\n\nVerifica que el comando existe y está instalado.',
                        showViewErrorsButton: true,
                        onViewErrors: () {
                          _debugService.openPanel();
                        },
                  showViewCodeButton: true,
                  onViewCode: () {
                    widget.onViewCode?.call();
                  },
                      ),
                    );
                  }
                }
              }
            }
          });

          if (isLongRunningServer) {
            // Para servidores de larga duración, esperar a confirmar que inició

            // Timeout de 30 segundos para detectar si el proceso no inicia
            _startupTimeout = Timer(const Duration(seconds: 30), () {
              if (!hasReceivedOutput && mounted) {
                print(
                  '⚠️ Timeout: El proceso no ha producido output después de 30 segundos',
                );
                _debugService.addProblem(
                  '⚠️ Timeout: El proceso no ha producido output después de 30 segundos',
                );
                _debugService.setCompilationProgress(
                  0.0,
                  'Error: Timeout al iniciar',
                );

                setState(() {
                  _isRunning = false;
                });
                _debugService.setRunning(false);

                try {
                  process.kill();
                  _runningProcess = null;
                } catch (e) {
                  print('⚠️ Error al terminar proceso: $e');
                }

                showDialog(
                  context: context,
                  builder: (context) => ErrorConfirmationDialog(
                    title: 'Error de inicio',
                    message:
                        'El servidor no ha iniciado después de 30 segundos.\n\n'
                        'Posibles causas:\n'
                        '• El comando no existe o no está instalado\n'
                        '• Faltan dependencias\n'
                        '• Error en la configuración\n\n'
                        'Revisa el Debug Console para más detalles.',
                    showViewErrorsButton: true,
                    onViewErrors: () {
                      _debugService.openPanel();
                    },
                  showViewCodeButton: true,
                  onViewCode: () {
                    widget.onViewCode?.call();
                  },
                  ),
                );
              }
            });

            // Monitorear si el proceso termina inesperadamente
            process.exitCode.then((exitCode) {
              if (_startupTimeout != null) {
                _startupTimeout!.cancel();
                _startupTimeout = null;
              }

              print('⚠️ Proceso terminó con código: $exitCode');
              _runningProcess = null;

              if (mounted) {
                setState(() {
                  _isRunning = false;
                });
              }

              _debugService.setRunning(false);

              if (exitCode != 0 && mounted) {
                showDialog(
                  context: context,
                  builder: (context) => ErrorConfirmationDialog(
                    title: 'Servidor detenido',
                    message:
                        'El servidor terminó inesperadamente con código: $exitCode\n\nRevisa el Debug Console para más detalles.',
                    showViewErrorsButton: true,
                    onViewErrors: () {
                      _debugService.openPanel();
                    },
                  showViewCodeButton: true,
                  onViewCode: () {
                    widget.onViewCode?.call();
                  },
                  ),
                );
              }
            });
          } else {
            // Para procesos que deben terminar, esperar el código de salida
            final exitCode = await process.exitCode;
            _runningProcess = null;

            if (mounted) {
              setState(() {
                _isRunning = false;
              });
            }

            _debugService.setRunning(false);
            _debugService.setCompilationProgress(
              1.0,
              exitCode == 0 ? 'Completado' : 'Error',
            );

            if (exitCode != 0 && mounted) {
              showDialog(
                context: context,
                builder: (context) => ErrorConfirmationDialog(
                  title: 'Ejecución fallida',
                  message:
                      'El proceso terminó con código de error: $exitCode\n\nRevisa el Debug Console para más detalles.',
                  showViewErrorsButton: true,
                  onViewErrors: () {
                    _debugService.openPanel();
                  },
                  showViewCodeButton: true,
                  onViewCode: () {
                    widget.onViewCode?.call();
                  },
                ),
              );
            }
          }
        } catch (e) {
          print('❌ Error al ejecutar comando: $e');
          _debugService.addProblem('Error: $e');
          _debugService.setCompilationProgress(0.0, 'Error en ejecución');
          _runningProcess = null;

          if (mounted) {
            setState(() {
              _isRunning = false;
            });
            _debugService.setRunning(false);

            showDialog(
              context: context,
              builder: (context) => ErrorConfirmationDialog(
                title: 'Error de ejecución',
                message:
                    'No se pudo ejecutar el proyecto:\n\n$e\n\nAsegúrate de que las dependencias están instaladas:\n'
                    '${_getSuggestedCommand(projectType)}',
                showViewErrorsButton: true,
                onViewErrors: () {
                  _debugService.openPanel();
                },
                  showViewCodeButton: true,
                  onViewCode: () {
                    widget.onViewCode?.call();
                  },
              ),
            );
          }
        }
      }
    } catch (e) {
      print('❌ Error general en _handleRun: $e');
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
        _debugService.setRunning(false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al ejecutar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Método auxiliar para sugerir comandos de instalación
  String _getSuggestedCommand(ProjectType type) {
    switch (type) {
      case ProjectType.python:
      case ProjectType.django:
      case ProjectType.fastapi:
      case ProjectType.flask:
        return '• Python: pip install -r requirements.txt';
      case ProjectType.nodejs:
      case ProjectType.react:
      case ProjectType.nextjs:
      case ProjectType.vue:
      case ProjectType.vite:
        return '• Node.js: npm install';
      case ProjectType.golang:
        return '• Go: go mod download';
      case ProjectType.rust:
        return '• Rust: cargo build';
      default:
        return '• Verifica la documentación del proyecto';
    }
  }

  Future<void> _handleDebug() async {
    try {
      // Obtener projectPath con logging detallado
      final widgetProjectPath = widget.projectPath;
      final serviceProjectPath = await ProjectService.getProjectPath();
      final projectPath = widgetProjectPath ?? serviceProjectPath;

      print('🔍 ChatScreen._handleDebug: VERIFICACIÓN DE PROYECTO');
      print('   widget.projectPath: $widgetProjectPath');
      print('   ProjectService.getProjectPath(): $serviceProjectPath');
      print('   projectPath final a usar: $projectPath');

      if (projectPath == null || projectPath.isEmpty) {
        print('❌ ChatScreen._handleDebug: NO HAY PROYECTO');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay proyecto cargado'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Verificar que el directorio existe
      final projectDir = Directory(projectPath);
      if (!await projectDir.exists()) {
        print(
          '❌ ChatScreen._handleDebug: EL DIRECTORIO NO EXISTE: $projectPath',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('El proyecto no existe: $projectPath'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // DETECCIÓN UNIVERSAL DE TIPO DE PROYECTO (como Cursor IDE)
      print('🔍 Detectando tipo de proyecto...');
      final projectType = await ProjectTypeDetector.detectProjectType(
        projectPath,
      );

      if (projectType == ProjectType.unknown) {
        print(
          '❌ ChatScreen._handleDebug: TIPO DE PROYECTO DESCONOCIDO: $projectPath',
        );

        // ✅ FIX: Verificar archivos faltantes y ofrecer sugerencias
        final missingFiles = await _checkMissingProjectFiles(projectPath);

        if (mounted) {
          setState(() {
            _isLoading = false;
            _isSending = false;
          });

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: CursorTheme.surface,
              title: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.orange,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Proyecto incompleto',
                      style: TextStyle(color: CursorTheme.textPrimary),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No se pudo detectar el tipo de proyecto porque faltan archivos necesarios.',
                      style: TextStyle(color: CursorTheme.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    if (missingFiles.isNotEmpty) ...[
                      Text(
                        'Archivos faltantes:',
                        style: const TextStyle(
                          color: CursorTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...missingFiles.map(
                        (file) => Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning,
                                color: Colors.orange,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  file,
                                  style: TextStyle(
                                    color: CursorTheme.textSecondary,
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.lightbulb_outline,
                                color: Colors.blue,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Sugerencia',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pide al agente que cree la estructura completa del proyecto. Por ejemplo:\n\n'
                            '"Crea un proyecto Flutter completo con pubspec.yaml y main.dart"',
                            style: TextStyle(
                              color: CursorTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Entendido',
                    style: TextStyle(color: CursorTheme.primary),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }

      final projectTypeName = ProjectTypeDetector.getProjectTypeName(
        projectType,
      );
      final projectTypeIcon = ProjectTypeDetector.getProjectTypeIcon(
        projectType,
      );
      print('✅ Tipo de proyecto: $projectTypeIcon $projectTypeName');

      // Obtener comando de ejecución para el tipo de proyecto (modo debug)
      final runCommand = await ProjectTypeDetector.getRunCommand(
        projectPath,
        projectType,
        isDebug: true,
      );

      print('🚀 Comando a ejecutar (DEBUG): $runCommand');
      print('   Requiere dispositivo: ${runCommand.requiresDevice}');

      // Configurar estado de ejecución
      setState(() {
        _isRunning = true;
        _isDebugging = true;
      });

      _debugService.setRunning(true);
      _debugService.resetCompilationProgress();
      _debugService.setCompilationProgress(
        0.05,
        'Iniciando $projectTypeName (DEBUG)...',
      );
      // Abrir Debug Console en Output para logs en vivo
      _debugService.clearAll();
      _debugService.showOutputTab();

      // Obtener nombre del proyecto
      final projectName = projectPath.split('/').last;
      print('✅ ChatScreen._handleDebug: Proyecto válido encontrado');
      print('   Nombre del proyecto: $projectName');
      print('   Tipo: $projectTypeIcon $projectTypeName');
      print('   Ruta del proyecto: $projectPath');
      print('   Modo: DEBUG');

      // Detectar URL para proyectos web
      String? detectedUrl;

      // Para Flutter, usar el sistema existente con dispositivos
      if (projectType == ProjectType.flutter) {
        // Sincronizar plataforma antes de ejecutar
        _selectedPlatform = _platformService.selectedPlatform;
        print(
          '🚀 Ejecutando Flutter en plataforma (DEBUG): $_selectedPlatform',
        );
        print(
          '🔧 PlatformService.selectedPlatform: ${_platformService.selectedPlatform}',
        );

        final requestedPlatform = _selectedPlatform.isNotEmpty
            ? _selectedPlatform
            : (_platformService.selectedPlatform.isNotEmpty
                ? _platformService.selectedPlatform
                : 'macos');
        final platformToUse = await _ensureCompatiblePlatform(
          projectPath: projectPath,
          requestedPlatform: requestedPlatform,
        );
        print('✅ Usando plataforma (DEBUG): $platformToUse');
        print('   _selectedPlatform: $_selectedPlatform');
        print(
          '   _platformService.selectedPlatform: ${_platformService.selectedPlatform}',
        );
        _debugService.setCompilationProgress(
          0.08,
          'Preparando ${ProjectPlatformSupport.humanLabel(platformToUse)} (DEBUG)...',
        );

        // Web → web-server + Preview WebView interno (nunca Chrome externo).
        final result = await AdvancedDebuggingService.runFlutterApp(
          projectPath: projectPath,
          platform: platformToUse,
          mode: 'debug',
          useWebServer: true,
          onOutput: (line) {
            _debugService.ingestProcessLine(line);
            _maybeCaptureVmServiceUri(line);

            print('📥 Flutter output (DEBUG): $line');

            // Detectar errores
            final lowerLine = line.toLowerCase();
            if (RegExp(r'\.dart:\d+:\d+:\s*(error|warning):').hasMatch(line) ||
                (lowerLine.contains('error:') &&
                    !lowerLine.contains('no error')) ||
                (lowerLine.contains('failed') &&
                    !lowerLine.contains('no devices found')) ||
                lowerLine.contains('undefined name') ||
                lowerLine.contains('undefined class') ||
                lowerLine.contains('undefined method') ||
                lowerLine.contains('undefined getter') ||
                lowerLine.contains('syntax error') ||
                (lowerLine.contains('cannot') &&
                    (lowerLine.contains('find') ||
                        lowerLine.contains('resolve')))) {
              _debugService.addProblem(line);
              print('🔴 Error detectado: $line');
            }

            // Fase / progreso en vivo desde stdout
            _debugService.updateProgressFromFlutterLine(line);

            final embedsPreviewDebug = platformToUse == 'web' ||
                platformToUse == 'android' ||
                platformToUse == 'ios';
            if (embedsPreviewDebug) {
              print(
                '🔍 Buscando URL Preview ($platformToUse DEBUG): "$line"',
              );

              RegExpMatch? urlMatch = RegExp(
                r'(?:is being served at|serving at|Serving at)\s*(https?://[^\s]+)',
                caseSensitive: false,
              ).firstMatch(line);
              if (urlMatch != null) {
                final candidate = urlMatch.group(1)!.trim();
                if (DebugConsoleService.isPreviewAppUrl(candidate)) {
                  detectedUrl = candidate;
                  _debugService.setAppUrl(detectedUrl);
                  print('🌐 ✅ URL Preview (served at DEBUG): $detectedUrl');
                  if (mounted) {
                    setState(() {
                      _isRunning = true;
                      _isDebugging = true;
                    });
                  }
                  _debugService.setRunning(true);
                  _debugService.setCompilationProgress(
                    1.0,
                    'Aplicación web en Preview (DEBUG)',
                  );
                }
              } else if (line.toLowerCase().contains('devtools') &&
                  line.toLowerCase().contains('available at')) {
                final dt = RegExp(
                  r'available at:\s*(https?://[^\s]+)',
                  caseSensitive: false,
                ).firstMatch(line);
                if (dt != null) {
                  _debugService.setVmServiceUri(dt.group(1)!.trim());
                  print('🧩 DevTools/VM DEBUG (no Preview): ${dt.group(1)}');
                }
              } else if (!line.toLowerCase().contains('devtools') &&
                  !line.toLowerCase().contains('vm service') &&
                  !line.toLowerCase().contains('observatory')) {
                urlMatch = RegExp(
                  r'http://(localhost|127\.0\.0\.1):(\d+)\b',
                ).firstMatch(line);
                if (urlMatch != null) {
                  final host = urlMatch.group(1)!;
                  final port = urlMatch.group(2)!;
                  final candidate = 'http://$host:$port';
                  if (DebugConsoleService.isPreviewAppUrl(candidate)) {
                    detectedUrl = candidate;
                    _debugService.setAppUrl(detectedUrl);
                    print('🌐 ✅ URL Preview DEBUG: $detectedUrl');
                    if (mounted) {
                      setState(() {
                        _isRunning = true;
                        _isDebugging = true;
                      });
                    }
                    _debugService.setRunning(true);
                    _debugService.setCompilationProgress(
                      1.0,
                      _runningPreviewLabel(platformToUse, debug: true),
                    );
                  }
                }
              }

              // También detectar cuando Chrome se abre (indica que la app está lista)
              if (line.contains('Chrome') &&
                  (line.contains('Launching') || line.contains('Starting'))) {
                // Si no se detectó URL aún, usar localhost:8080 como fallback (puerto común de Flutter web)
                if (detectedUrl == null) {
                  detectedUrl = 'http://localhost:8080';
                  _debugService.setAppUrl(detectedUrl);
                  print(
                    '🌐 ✅ URL establecida por defecto (Chrome detectado): $detectedUrl',
                  );
                  if (mounted) {
                    setState(() {
                      _isRunning = true;
                      _isDebugging = true;
                    });
                  }
                  _debugService.setRunning(true);
                  _debugService.setCompilationProgress(
                    1.0,
                    _runningPreviewLabel(platformToUse, debug: true),
                  );
                }
              }
            }
          },
          onError: (error) {
            _debugService.addProblem(error.toString());
            _debugService.setCompilationProgress(0.0, 'Error en compilación');
          },
        );

        if (detectedUrl != null) {
          _debugService.setAppUrl(detectedUrl);
          print('🌐 URL final establecida (DEBUG): $detectedUrl');
        }

        final embedsOkDebug = platformToUse == 'web' ||
            platformToUse == 'android' ||
            platformToUse == 'ios';
        if (embedsOkDebug && result.success) {
          print('✅ Preview $platformToUse OK (DEBUG)');
          if (mounted) {
            setState(() {
              _isRunning = true;
              _isDebugging = true;
            });
          }
          _debugService.setRunning(true);
          _debugService.setCompilationProgress(
            1.0,
            platformToUse == 'web'
                ? 'Aplicación web ejecutándose (DEBUG)'
                : '${ProjectPlatformSupport.humanLabel(platformToUse)} en Preview (DEBUG)',
          );
        } else if (result.success) {
          print(
            '✅ Flutter $platformToUse en dispositivo/emulador (DEBUG)',
          );
          if (mounted) {
            setState(() {
              _isRunning = true;
              _isDebugging = true;
            });
          }
          _debugService.setRunning(true);
          if (!embedsOkDebug) {
            _debugService.setAppUrl(null);
          }
          _debugService.setCompilationProgress(
            1.0,
            'Aplicación ejecutándose en ${platformToUse.toUpperCase()} (DEBUG)',
          );
        } else {
          final errorMessage = result.errors.isNotEmpty
              ? result.errors.join('\n')
              : 'La compilación falló. Revisa el Debug Console para más detalles.';
          final isNoDeviceError =
              errorMessage.contains('No se encontró dispositivo disponible') ||
              errorMessage.contains(
                'No se encontró dispositivo para la plataforma',
              );
          final isAndroidOrIOS =
              platformToUse.toLowerCase() == 'android' ||
              platformToUse.toLowerCase() == 'ios';

          if (isAndroidOrIOS && isNoDeviceError) {
            final tip = platformToUse.toLowerCase() == 'android'
                ? 'Abre Android Studio → Device Manager e inicia un emulador AVD, '
                    'luego pulsa Debug otra vez. (Voryxel Code ya no cambia solo a Web.)'
                : 'Abre el Simulador iOS desde Xcode y vuelve a pulsar Debug. '
                    '(Voryxel Code ya no cambia solo a Web.)';
            _debugService.addDebugConsole(
              '📱 No hay dispositivo $platformToUse disponible (DEBUG).',
            );
            _debugService.addDebugConsole('💡 $tip');
            _debugService.setCompilationProgress(
              0.0,
              'Sin dispositivo $platformToUse — inicia el emulador',
            );
          }

          if (mounted) {
            setState(() {
              _isRunning = false;
              _isDebugging = false;
            });
          }
          _debugService.setRunning(false);
          _debugService.setAppUrl(null);
          _debugService.setCompilationProgress(1.0, errorMessage);
        }

        if (!result.success && mounted) {
          final errorMessage = result.errors.isNotEmpty
              ? result.errors.join('\n')
              : 'La compilación falló. Revisa el Debug Console para más detalles.';
          _showCompilationFailureDialog(errorMessage);
        }
      } else {
        // EJECUCIÓN UNIVERSAL para otros lenguajes (modo debug)
        print(
          '🎯 Ejecutando comando personalizado (DEBUG): ${runCommand.command} ${runCommand.args.join(' ')}',
        );

        // Detectar si es un proceso de servidor de larga duración
        final isLongRunningServer =
            projectType == ProjectType.fastapi ||
            projectType == ProjectType.django ||
            projectType == ProjectType.flask ||
            projectType == ProjectType.nodejs ||
            projectType == ProjectType.react ||
            projectType == ProjectType.nextjs ||
            projectType == ProjectType.vue ||
            projectType == ProjectType.vite ||
            projectType == ProjectType.html ||
            runCommand.command.contains('uvicorn') ||
            runCommand.command.contains('gunicorn') ||
            runCommand.command.contains('runserver') ||
            runCommand.args.contains('http.server') ||
            runCommand.command.contains('npm') &&
                (runCommand.args.contains('start') ||
                    runCommand.args.contains('dev')) ||
            runCommand.command.contains('yarn') &&
                (runCommand.args.contains('start') ||
                    runCommand.args.contains('dev'));

        try {
          await _killLocalRunner();

          final process = await Process.start(
            runCommand.command,
            runCommand.args,
            workingDirectory: runCommand.workingDirectory,
            runInShell: projectType != ProjectType.html,
            environment: runCommand.environment,
          );

          // Guardar referencia al proceso para poder detenerlo
          _runningProcess = process;

          _debugService.addOutput(
            '$projectTypeIcon Ejecutando (DEBUG): ${runCommand.description}',
          );
          _debugService.addOutput(
            '📁 Directorio: ${runCommand.workingDirectory}',
          );
          _debugService.addOutput(
            '🚀 Comando: ${runCommand.command} ${runCommand.args.join(' ')}',
          );
          _debugService.addOutput('');
          _debugService.setCompilationProgress(0.2, 'Ejecutando (DEBUG)...');

          // Variables para rastrear el estado del proceso
          bool hasReceivedOutputDebug = false;
          bool urlDetectedDebug = false; // Flag para detectar URL solo una vez

          if (projectType == ProjectType.html) {
            var port = '8000';
            for (final arg in runCommand.args) {
              if (RegExp(r'^\d+$').hasMatch(arg)) {
                port = arg;
                break;
              }
            }
            detectedUrl = 'http://127.0.0.1:$port';
            urlDetectedDebug = true;
            _debugService.setAppUrl(detectedUrl);
            _debugService.setCompilationProgress(
              1.0,
              'Página web en Preview ✅',
            );
            _debugService.setRunning(true);
            _debugService.addOutput('🌐 Preview → $detectedUrl');
            if (mounted) setState(() => _isRunning = true);
          }

          // Verificar si ya hay una URL establecida (por si acaso)
          if (_debugService.appUrl != null &&
              _debugService.appUrl!.isNotEmpty) {
            urlDetectedDebug = true;
            detectedUrl = _debugService.appUrl;
            print('🌐 URL ya establecida previamente (DEBUG): $detectedUrl');
          }

          // Limpiar timeout anterior si existe
          if (_startupTimeoutDebug != null) {
            _startupTimeoutDebug!.cancel();
            _startupTimeoutDebug = null;
          }

          // Escuchar stdout
          process.stdout.transform(utf8.decoder).listen((data) {
            hasReceivedOutputDebug = true;
            if (_startupTimeoutDebug != null) {
              _startupTimeoutDebug!.cancel();
              _startupTimeoutDebug = null;
            }

            print(
              '📥 STDOUT recibido (${data.length} chars): "${data.substring(0, data.length > 100 ? 100 : data.length)}..."',
            );

            for (var line in data.split('\n')) {
              if (line.trim().isEmpty) continue;
              _debugService.ingestProcessLine(line);

              print('🔍 Analizando línea STDOUT: "$line"');

              // Detectar URLs en el output SOLO UNA VEZ
              // Método simple y directo: buscar 0.0.0.0:PORT y convertir a localhost
              // También verificar si ya hay una URL establecida
              if (!urlDetectedDebug &&
                  (_debugService.appUrl == null ||
                      _debugService.appUrl!.isEmpty)) {
                if (line.contains('0.0.0.0:')) {
                  print(
                    '✅ Línea contiene "0.0.0.0:" - intentando extraer puerto...',
                  );
                  final portMatch = RegExp(
                    r'0\.0\.0\.0:(\d+)',
                  ).firstMatch(line);
                  if (portMatch != null) {
                    final port = portMatch.group(1);
                    detectedUrl = 'http://localhost:$port';
                    _debugService.setAppUrl(detectedUrl);
                    urlDetectedDebug = true;
                    print(
                      '🌐 ✅✅✅ URL DETECTADA (DEBUG STDOUT): 0.0.0.0:$port -> $detectedUrl (detección bloqueada)',
                    );
                  } else {
                    print('❌ No se pudo extraer puerto de: "$line"');
                  }
                } else if (line.contains('localhost:')) {
                  print(
                    '✅ Línea contiene "localhost:" - intentando extraer puerto...',
                  );
                  final portMatch = RegExp(r'localhost:(\d+)').firstMatch(line);
                  if (portMatch != null) {
                    final port = portMatch.group(1);
                    detectedUrl = 'http://localhost:$port';
                    _debugService.setAppUrl(detectedUrl);
                    urlDetectedDebug = true;
                    print(
                      '🌐 ✅✅✅ URL detectada (DEBUG STDOUT localhost): $detectedUrl (detección bloqueada)',
                    );
                  }
                } else if (line.contains('127.0.0.1:')) {
                  print(
                    '✅ Línea contiene "127.0.0.1:" - intentando extraer puerto...',
                  );
                  final portMatch = RegExp(
                    r'127\.0\.0\.1:(\d+)',
                  ).firstMatch(line);
                  if (portMatch != null) {
                    final port = portMatch.group(1);
                    detectedUrl = 'http://127.0.0.1:$port';
                    _debugService.setAppUrl(detectedUrl);
                    urlDetectedDebug = true;
                    print(
                      '🌐 ✅✅✅ URL detectada (DEBUG STDOUT 127.0.0.1): $detectedUrl (detección bloqueada)',
                    );
                  }
                }
              }

              // Actualizar progreso basado en palabras clave
              final lowerLine = line.toLowerCase();
              if (lowerLine.contains('uvicorn running on') ||
                  lowerLine.contains('application startup complete')) {
                // Asegurar que la URL esté establecida antes de marcar como completo
                if (detectedUrl != null && detectedUrl!.isNotEmpty) {
                  _debugService.setAppUrl(detectedUrl);
                  print(
                    '🌐 ✅ URL confirmada al detectar servidor listo (DEBUG): $detectedUrl',
                  );
                }
                _debugService.setCompilationProgress(
                  1.0,
                  'Servidor ejecutándose (DEBUG) ✅',
                );
                _debugService.setRunning(true);
                print(
                  '✅ Servidor DEBUG listo con URL: ${detectedUrl ?? "pendiente"}',
                );
                if (mounted) {
                  setState(() {
                    _isRunning = true;
                    _isDebugging = true;
                  });
                }
              } else if (lowerLine.contains('started server process')) {
                _debugService.setCompilationProgress(
                  0.8,
                  'Iniciando servidor (DEBUG)...',
                );
              } else if (lowerLine.contains(
                'waiting for application startup',
              )) {
                _debugService.setCompilationProgress(
                  0.9,
                  'Preparando aplicación (DEBUG)...',
                );
              } else if (lowerLine.contains('server') &&
                  (lowerLine.contains('running') ||
                      lowerLine.contains('started'))) {
                _debugService.setCompilationProgress(
                  1.0,
                  'Servidor ejecutándose (DEBUG)',
                );
                _debugService.setRunning(true);
                if (mounted) {
                  setState(() {
                    _isRunning = true;
                    _isDebugging = true;
                  });
                }
              } else if (lowerLine.contains('listening') ||
                  lowerLine.contains('ready')) {
                _debugService.setCompilationProgress(
                  0.9,
                  'Servidor listo (DEBUG)',
                );
                _debugService.setRunning(true);
                if (mounted) {
                  setState(() {
                    _isRunning = true;
                    _isDebugging = true;
                  });
                }
              } else if (lowerLine.contains('compil')) {
                _debugService.setCompilationProgress(0.5, 'Compilando...');
              } else if (lowerLine.contains('build')) {
                _debugService.setCompilationProgress(0.6, 'Construyendo...');
              }
            }
          });

          // Escuchar stderr
          process.stderr.transform(utf8.decoder).listen((data) {
            hasReceivedOutputDebug = true;
            if (_startupTimeoutDebug != null) {
              _startupTimeoutDebug!.cancel();
              _startupTimeoutDebug = null;
            }

            print(
              '📥 STDERR recibido (${data.length} chars): "${data.substring(0, data.length > 100 ? 100 : data.length)}..."',
            );

            for (var line in data.split('\n')) {
              if (line.trim().isEmpty) continue;
              _debugService.ingestProcessLine(line);

              print('🔍 Analizando línea STDERR: "$line"');

              // IMPORTANTE: Uvicorn envía sus logs INFO a stderr, no stdout!
              // Detectar URLs en el output de stderr también SOLO UNA VEZ
              // También verificar si ya hay una URL establecida
              if (!urlDetectedDebug &&
                  (_debugService.appUrl == null ||
                      _debugService.appUrl!.isEmpty)) {
                if (line.contains('0.0.0.0:')) {
                  print(
                    '✅ Línea STDERR contiene "0.0.0.0:" - intentando extraer puerto...',
                  );
                  final portMatch = RegExp(
                    r'0\.0\.0\.0:(\d+)',
                  ).firstMatch(line);
                  if (portMatch != null) {
                    final port = portMatch.group(1);
                    detectedUrl = 'http://localhost:$port';
                    _debugService.setAppUrl(detectedUrl);
                    urlDetectedDebug = true;
                    print(
                      '🌐 ✅✅✅ URL DETECTADA EN STDERR (DEBUG): 0.0.0.0:$port -> $detectedUrl (detección bloqueada)',
                    );
                  } else {
                    print('❌ No se pudo extraer puerto de STDERR: "$line"');
                  }
                } else if (line.contains('localhost:')) {
                  print(
                    '✅ Línea STDERR contiene "localhost:" - intentando extraer puerto...',
                  );
                  final portMatch = RegExp(r'localhost:(\d+)').firstMatch(line);
                  if (portMatch != null) {
                    final port = portMatch.group(1);
                    detectedUrl = 'http://localhost:$port';
                    _debugService.setAppUrl(detectedUrl);
                    urlDetectedDebug = true;
                    print(
                      '🌐 ✅✅✅ URL detectada EN STDERR (DEBUG localhost): $detectedUrl (detección bloqueada)',
                    );
                  }
                } else if (line.contains('127.0.0.1:')) {
                  print(
                    '✅ Línea STDERR contiene "127.0.0.1:" - intentando extraer puerto...',
                  );
                  final portMatch = RegExp(
                    r'127\.0\.0\.1:(\d+)',
                  ).firstMatch(line);
                  if (portMatch != null) {
                    final port = portMatch.group(1);
                    detectedUrl = 'http://127.0.0.1:$port';
                    _debugService.setAppUrl(detectedUrl);
                    urlDetectedDebug = true;
                    print(
                      '🌐 ✅✅✅ URL detectada EN STDERR (DEBUG 127.0.0.1): $detectedUrl (detección bloqueada)',
                    );
                  }
                }
              }

              // Detectar errores críticos que impiden el inicio
              final lowerLine = line.toLowerCase();
              if (lowerLine.contains('error') ||
                  lowerLine.contains('failed') ||
                  lowerLine.contains('cannot') ||
                  lowerLine.contains('not found') ||
                  lowerLine.contains('command not found') ||
                  lowerLine.contains('no such file')) {
                _debugService.addProblem(line);

                // Si es un error crítico, detener el proceso
                if (lowerLine.contains('command not found') ||
                    lowerLine.contains('no such file') ||
                    lowerLine.contains('cannot find')) {
                  print(
                    '❌ Error crítico detectado (DEBUG), deteniendo proceso...',
                  );
                  if (mounted) {
                    setState(() {
                      _isRunning = false;
                      _isDebugging = false;
                    });
                  }
                  _debugService.setRunning(false);
                  _debugService.setCompilationProgress(
                    0.0,
                    'Error: Comando no encontrado',
                  );

                  // Intentar terminar el proceso
                  try {
                    process.kill();
                    _runningProcess = null;
                  } catch (e) {
                    print('⚠️ Error al terminar proceso: $e');
                  }

                  if (mounted) {
                    showDialog(
                      context: context,
                      builder: (context) => ErrorConfirmationDialog(
                        title: 'Error de ejecución',
                        message:
                            'No se pudo ejecutar el comando:\n\n$line\n\nVerifica que el comando existe y está instalado.',
                        showViewErrorsButton: true,
                        onViewErrors: () {
                          _debugService.openPanel();
                        },
                  showViewCodeButton: true,
                  onViewCode: () {
                    widget.onViewCode?.call();
                  },
                      ),
                    );
                  }
                }
              }
            }
          });

          if (isLongRunningServer) {
            // Para servidores de larga duración, esperar a confirmar que inició

            // Timeout de 30 segundos para detectar si el proceso no inicia
            _startupTimeoutDebug = Timer(const Duration(seconds: 30), () {
              if (!hasReceivedOutputDebug && mounted) {
                print(
                  '⚠️ Timeout (DEBUG): El proceso no ha producido output después de 30 segundos',
                );
                _debugService.addProblem(
                  '⚠️ Timeout: El proceso no ha producido output después de 30 segundos',
                );
                _debugService.setCompilationProgress(
                  0.0,
                  'Error: Timeout al iniciar',
                );

                setState(() {
                  _isRunning = false;
                  _isDebugging = false;
                });
                _debugService.setRunning(false);

                try {
                  process.kill();
                  _runningProcess = null;
                } catch (e) {
                  print('⚠️ Error al terminar proceso: $e');
                }

                showDialog(
                  context: context,
                  builder: (context) => ErrorConfirmationDialog(
                    title: 'Error de inicio',
                    message:
                        'El servidor no ha iniciado después de 30 segundos.\n\n'
                        'Posibles causas:\n'
                        '• El comando no existe o no está instalado\n'
                        '• Faltan dependencias\n'
                        '• Error en la configuración\n\n'
                        'Revisa el Debug Console para más detalles.',
                    showViewErrorsButton: true,
                    onViewErrors: () {
                      _debugService.openPanel();
                    },
                  showViewCodeButton: true,
                  onViewCode: () {
                    widget.onViewCode?.call();
                  },
                  ),
                );
              }
            });

            // Monitorear si el proceso termina inesperadamente
            process.exitCode.then((exitCode) {
              if (_startupTimeoutDebug != null) {
                _startupTimeoutDebug!.cancel();
                _startupTimeoutDebug = null;
              }

              print('⚠️ Proceso terminó con código: $exitCode');
              _runningProcess = null;

              if (mounted) {
                setState(() {
                  _isRunning = false;
                  _isDebugging = false;
                });
              }

              _debugService.setRunning(false);

              if (exitCode != 0 && mounted) {
                showDialog(
                  context: context,
                  builder: (context) => ErrorConfirmationDialog(
                    title: 'Servidor detenido',
                    message:
                        'El servidor terminó inesperadamente con código: $exitCode\n\nRevisa el Debug Console para más detalles.',
                    showViewErrorsButton: true,
                    onViewErrors: () {
                      _debugService.openPanel();
                    },
                  showViewCodeButton: true,
                  onViewCode: () {
                    widget.onViewCode?.call();
                  },
                  ),
                );
              }
            });
          } else {
            // Para procesos que deben terminar, esperar el código de salida
            final exitCode = await process.exitCode;
            _runningProcess = null;

            if (mounted) {
              setState(() {
                _isRunning = false;
                _isDebugging = false;
              });
            }

            _debugService.setRunning(false);
            _debugService.setCompilationProgress(
              1.0,
              exitCode == 0 ? 'Completado (DEBUG)' : 'Error',
            );

            if (exitCode != 0 && mounted) {
              showDialog(
                context: context,
                builder: (context) => ErrorConfirmationDialog(
                  title: 'Ejecución fallida',
                  message:
                      'El proceso terminó con código de error: $exitCode\n\nRevisa el Debug Console para más detalles.',
                  showViewErrorsButton: true,
                  onViewErrors: () {
                    _debugService.openPanel();
                  },
                  showViewCodeButton: true,
                  onViewCode: () {
                    widget.onViewCode?.call();
                  },
                ),
              );
            }
          }
        } catch (e) {
          print('❌ Error al ejecutar comando: $e');
          _debugService.addProblem('Error: $e');
          _debugService.setCompilationProgress(0.0, 'Error en ejecución');
          _runningProcess = null;

          if (mounted) {
            setState(() {
              _isRunning = false;
              _isDebugging = false;
            });
            _debugService.setRunning(false);

            showDialog(
              context: context,
              builder: (context) => ErrorConfirmationDialog(
                title: 'Error de ejecución',
                message:
                    'No se pudo ejecutar el proyecto:\n\n$e\n\nAsegúrate de que las dependencias están instaladas:\n'
                    '${_getSuggestedCommand(projectType)}',
                showViewErrorsButton: true,
                onViewErrors: () {
                  _debugService.openPanel();
                },
                  showViewCodeButton: true,
                  onViewCode: () {
                    widget.onViewCode?.call();
                  },
              ),
            );
          }
        }
      }
    } catch (e) {
      print('❌ Error general en _handleDebug: $e');
      if (mounted) {
        setState(() {
          _isRunning = false;
          _isDebugging = false;
        });
        _debugService.setRunning(false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al ejecutar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _maybeCaptureVmServiceUri(String line) {
    final lowerLine = line.toLowerCase();
    if (!(lowerLine.contains('vm service') ||
        lowerLine.contains('dart vm service') ||
        lowerLine.contains('observatory'))) {
      return;
    }

    final match = RegExp(r'((?:http|ws)://[^\s]+)').firstMatch(line);
    if (match != null) {
      final uri = match.group(1)!.trim();
      _debugService.setVmServiceUri(uri);
    }
  }

  Future<void> _handleStop() async {
    // Limpiar timeouts
    if (_startupTimeout != null) {
      _startupTimeout!.cancel();
      _startupTimeout = null;
    }
    if (_startupTimeoutDebug != null) {
      _startupTimeoutDebug!.cancel();
      _startupTimeoutDebug = null;
    }

    // Detener proceso Flutter real (AdvancedDebuggingService) + UI
    await _debugService.requestStop();

    // Detener proceso local (runners no-Flutter) — SIGKILL + liberar :8000
    await _killLocalRunner();
    _debugService.setAppUrl(null);
    _debugService.setCompilationProgress(0.0, '');
    _debugService.setRunning(false);

    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _isDebugging = false;
    });
  }

  Future<void> _handleRestart() async {
    await _handleStop();
    await Future.delayed(const Duration(milliseconds: 500));
    if (_isDebugging) {
      await _handleDebug();
    } else {
      await _handleRun();
    }
  }

  /// Hot Reload (⚡) — stdin `r` al flutter run activo (solo debug).
  Future<void> _handleHotReload() async {
    _debugService.showOutputTab();
    var ok = await _debugService.requestHotReload();
    if (!ok && _runningProcess != null) {
      try {
        _runningProcess!.stdin.writeln('r');
        await _runningProcess!.stdin.flush();
        _debugService.addDebugConsole('⚡ Hot Reload enviado (proceso local)');
        ok = true;
      } catch (e) {
        print('⚠️ Hot Reload local falló: $e');
      }
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hot Reload no disponible. Espera a que Compile termine '
            'en debug, o pulsa Stop → Run.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Hot Restart (🔄) — stdin `R` al flutter run activo (solo debug).
  Future<void> _handleHotRestart() async {
    _debugService.showOutputTab();
    var ok = await _debugService.requestHotRestart();
    if (!ok && _runningProcess != null) {
      try {
        _runningProcess!.stdin.writeln('R');
        await _runningProcess!.stdin.flush();
        _debugService.addDebugConsole('🔄 Hot Restart enviado (proceso local)');
        ok = true;
      } catch (e) {
        print('⚠️ Hot Restart local falló ($e) — reinicio completo');
        await _handleRestart();
        return;
      }
    }
    if (!ok && mounted) {
      // Sin proceso debug interactivo: reinicio completo (Stop + Run).
      _debugService.addDebugConsole(
        '🔄 Hot Restart no disponible → reinicio completo',
      );
      await _handleRestart();
    }
  }

  /// Callback del Agent: delega al handler unificado de controles del IDE.
  Future<String> _handleIdeControl(
    String action, {
    Map<String, dynamic>? args,
  }) =>
      _handleIdeControlFromAgent(action, args: args);

  // Métodos públicos para acceso desde MultiChatScreen
  void handleRun() => _handleRun();
  void handleDebug() => _handleDebug();
  Future<void> handleStop() => _handleStop();
  Future<void> handleRestart() => _handleRestart();
  Future<void> handleHotReload() => _handleHotReload();
  Future<void> handleHotRestart() => _handleHotRestart();

  // Getters públicos para el estado
  bool get isRunning => _isRunning;
  bool get isDebugging => _isDebugging;
  String get selectedPlatform => _selectedPlatform;

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    ).then((_) async {
      await _loadOpenAIService();
    });
  }

  Widget _buildEmptyChatArea() {
    return Center(
      child: SingleChildScrollView(
        // Padding más compacto: el panel de chat suele ser ~250–400px
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const VoryxelBrandLogo(
                iconSize: 80,
                fontSize: 26,
                subtitle: 'Tu asistente de IA para desarrollo de software',
              ),
              const SizedBox(height: 32),
              // Capacidades
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildCapabilityChip('📱 Apps iOS/Android', Colors.blue),
                  _buildCapabilityChip('🌐 Sitios Web', Colors.green),
                  _buildCapabilityChip('🐍 Backend', Colors.orange),
                  _buildCapabilityChip('🔍 Code Review', Colors.purple),
                  _buildCapabilityChip('🐛 Debugging', Colors.red),
                  _buildCapabilityChip('🚀 Run & Debug', Colors.teal),
                ],
              ),
              const SizedBox(height: 32),
              // Mensaje de inicio
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CursorTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CursorTheme.border),
                ),
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: CursorTheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Puedo ayudarte con:',
                            style: const TextStyle(
                              color: CursorTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildHelpItem('Crear apps y proyectos completos'),
                    _buildHelpItem('Editar y optimizar código existente'),
                    _buildHelpItem('Solucionar errores y bugs'),
                    _buildHelpItem('Compilar y ejecutar tu proyecto'),
                    _buildHelpItem('Descargar recursos desde internet'),
                    _buildHelpItem('Ejecutar comandos en terminal'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Escribe un mensaje para comenzar',
                style: TextStyle(
                  color: CursorTheme.textSecondary.withOpacity(0.7),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapabilityChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildHelpItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: CursorTheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: CursorTheme.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatArea() {
    // NO llamar _scrollToBottom aquí - causa problemas de layout
    // Se llamará después de agregar mensajes en _sendMessage

    // SelectionArea: todo el chat seleccionable → copiar / pegar (⌘C / Ctrl+C).
    return SelectionArea(
      child: ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 16,
      ), // Más padding horizontal como Cursor
      shrinkWrap: false, // Asegurar que no use shrinkWrap
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          // Tarjeta compacta para "pensando" o "trabajando con archivos" - estilo Cursor
          // Mostrar tarjeta de trabajo en tiempo real si hay operación de archivo
          if (_currentFileOperation != null && _currentFilePath != null) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // ✅ FIX: Tamaño mínimo
                children: [
                  // Icono del proyecto (robot azul)
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF007ACC),
                      borderRadius: BorderRadius.circular(
                        4.5,
                      ), // Esquinas redondeadas como iconos del dock
                      border: Border.all(
                        color: const Color(
                          0xFF007ACC,
                        ).withOpacity(0.3), // Borde sutil
                        width: 0.5,
                      ),
                    ),
                    child: CustomPaint(painter: RobotIconPainter()),
                  ),
                  const SizedBox(width: 12),
                  // ✅ FIX: Usar Flexible para evitar overflow
                  Flexible(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 500),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CursorTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: CursorTheme.border, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Color(0xFF007ACC),
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _currentFileOperation == 'creando'
                                      ? 'Creando archivo'
                                      : _currentFileOperation == 'editando'
                                      ? 'Editando archivo'
                                      : _currentFileOperation == 'leyendo'
                                      ? 'Leyendo archivo'
                                      : _currentFileOperation == 'compilando'
                                      ? 'Compilando / lanzando'
                                      : _currentFileOperation == 'ejecutando'
                                      ? 'Ejecutando comando'
                                      : _currentFileOperation == 'buscando'
                                      ? 'Buscando en el código'
                                      : _currentFileOperation == 'listando'
                                      ? 'Explorando proyecto'
                                      : 'Trabajando',
                                  style: const TextStyle(
                                    color: CursorTheme.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: CursorTheme.background,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _currentFileOperation == 'creando'
                                      ? Icons.add_circle_outline
                                      : _currentFileOperation == 'editando'
                                      ? Icons.edit_outlined
                                      : Icons.description_outlined,
                                  size: 14,
                                  color: CursorTheme.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _currentFilePath!.split('/').last,
                                    style: const TextStyle(
                                      color: CursorTheme.textSecondary,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ), // ✅ Cierre de Container (tarjeta de trabajo)
                  ), // ✅ Cierre de Flexible
                ],
              ),
            );
          }
          // Indicador de "pensando" simple
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icono del proyecto (robot azul)
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFF007ACC),
                    borderRadius: BorderRadius.circular(
                      4.5,
                    ), // Esquinas redondeadas como iconos del dock
                    border: Border.all(
                      color: const Color(
                        0xFF007ACC,
                      ).withOpacity(0.3), // Borde sutil
                      width: 0.5,
                    ),
                  ),
                  child: CustomPaint(painter: RobotIconPainter()),
                ),
                const SizedBox(width: 12),
                // Texto simple sin contenedor
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF007ACC),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _loadingStatus.isNotEmpty
                          ? _loadingStatus
                          : 'Thought briefly',
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }
        final msg = _messages[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            MessageBubble(
              message: msg,
              onAcceptActions:
                  msg.pendingActions != null &&
                      msg.pendingActions!.isNotEmpty
                  ? (actions) => _handleAcceptActions(actions, index)
                  : null,
              onRejectActions:
                  msg.pendingActions != null &&
                      msg.pendingActions!.isNotEmpty
                  ? () => _handleRejectActions(msg.pendingActions!, index)
                  : null,
              onEdit: msg.role == 'user' && !_isLoading && !_isSending
                  ? () => _editUserMessageAt(index)
                  : null,
              onResend: msg.role == 'user' && !_isLoading && !_isSending
                  ? () => _resendUserMessageAt(index)
                  : null,
              onContinueTask: msg.role == 'assistant' &&
                      msg.canContinueTask &&
                      !_isLoading &&
                      !_isSending
                  ? () => _continueAgentTask(index)
                  : null,
              onOpenFile: (path) => widget.onAgentOpenFile?.call(path),
            ),
            if (msg.role == 'assistant' && msg.checkpoint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(48, 0, 16, 8),
                child: CheckpointBannerWidget(
                  checkpoint: msg.checkpoint!,
                  onRestored: () {
                    if (!mounted) return;
                    setState(() {
                      if (index >= 0 && index < _messages.length) {
                        final current = _messages[index];
                        if (current.checkpoint != null) {
                          _messages[index] = current.copyWith(
                            checkpoint:
                                current.checkpoint!.copyWith(restored: true),
                          );
                        }
                      }
                    });
                    unawaited(_saveConversation());
                  },
                ),
              ),
          ],
        );
      },
    ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projectPath = widget.projectPath ?? '';
    // No usar Scaffold con AppBar cuando está dentro de MultiChatScreen
    // para evitar overflow - MultiChatScreen ya tiene su propia barra de pestañas
    return Container(
      color: CursorTheme.background,
      child: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyChatArea()
                : _buildChatArea(),
          ),
          if (_autocompleteActive && projectPath.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ContextAutocompleteOverlay(
                  inputText: _inputText,
                  cursorOffset: _cursorOffset,
                  projectPath: projectPath,
                  activeFilePath: _effectiveActiveFilePath,
                  onMentionSelected: _onMentionSelected,
                  onSlashCommandSelected: (cmd, expanded, query) {
                    // Preferir expand con archivo activo + problems actuales
                    final withActive = ContextBuilderService.expandSlashCommand(
                      command: cmd,
                      activeFilePath: _effectiveActiveFilePath,
                      activeFileContent: widget.activeFileContent,
                    );
                    _onSlashCommandSelected(cmd, withActive, query);
                  },
                  onOpenAddDocumentation: () async {
                    setState(() => _autocompleteActive = false);
                    final added = await showAddDocumentationDialog(context);
                    if (added && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Documentación agregada. El agente la usará como referencia.',
                          ),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  onDismiss: () {
                    setState(() => _autocompleteActive = false);
                  },
                ),
              ),
            ),
          _buildActiveMentionChips(),
          CursorChatInput(
            controller: _messageController,
            onSend: _sendMessage,
            onAttachImage: _pickImage,
            onAttachFile: _pickFile,
            isLoading: _isLoading,
            onStop: _stopRequest,
            placeholder: 'Plan, @ for context, / for commands',
            selectedImages: _selectedImages,
            selectedFilePath: _selectedFilePath,
            chatMode: _chatMode,
            onChatModeChanged: (mode) {
              setState(() => _chatMode = mode);
            },
            onImagesDropped: (paths) {
              if (!mounted || paths.isEmpty) return;
              setState(() {
                for (final path in paths) {
                  if (!_selectedImages.contains(path)) {
                    _selectedImages.add(path);
                  }
                }
              });
            },
            onRemoveImage: (index) {
              setState(() {
                if (index >= 0 && index < _selectedImages.length) {
                  _selectedImages.removeAt(index);
                }
              });
            },
            onRemoveFile: () {
              setState(() {
                _selectedFilePath = null;
              });
            },
            onModelChanged: (model) async {
              print('🔄 ChatScreen.onModelChanged recibido: $model');
              // Actualizar el modelo en el servicio OpenAI
              if (_openAIService != null) {
                _openAIService!.setModel(model);
                await SettingsService.saveSelectedModel(model);
                print('✅ Modelo actualizado en OpenAI Service: $model');
                print('💾 Modelo guardado en configuración: $model');
              } else {
                print(
                  '⚠️ OpenAI Service no está inicializado. Cargando...',
                );
                await _loadOpenAIService();
              }
            },
            onDocumentationSelected: (url) async {
              // Agregar documentación a la lista de seleccionadas
              if (!_selectedDocumentation.contains(url)) {
                setState(() {
                  _selectedDocumentation.add(url);
                });
                print('✅ Documentación agregada: $url');
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Limpiar timeouts
    if (_startupTimeout != null) {
      _startupTimeout!.cancel();
      _startupTimeout = null;
    }
    if (_startupTimeoutDebug != null) {
      _startupTimeoutDebug!.cancel();
      _startupTimeoutDebug = null;
    }

    // Detener proceso si está ejecutándose
    if (_runningProcess != null) {
      try {
        _runningProcess!.kill();
        _runningProcess = null;
      } catch (e) {
        print('⚠️ Error al detener proceso en dispose: $e');
      }
    }

    _messageController.removeListener(_onMessageInputChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _platformService.removeListener(_onPlatformChanged);
    _openAIService?.dispose();
    _saveConversation();
    super.dispose();
  }
}
