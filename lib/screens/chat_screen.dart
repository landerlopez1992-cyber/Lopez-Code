import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/message.dart';
import '../services/openai_service.dart';
import '../services/settings_service.dart';
import '../services/project_service.dart';
import '../services/chat_storage_service.dart';
import '../services/advanced_debugging_service.dart';
import '../services/project_type_detector.dart';
import '../widgets/message_bubble.dart';
import '../widgets/cursor_chat_input.dart';
import '../widgets/cursor_theme.dart';
import '../widgets/error_confirmation_dialog.dart';
import '../services/debug_console_service.dart';
import '../services/platform_service.dart';
import '../models/pending_action.dart';
import '../services/conversation_memory_service.dart';
import '../services/smart_context_manager.dart';
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
      ..strokeWidth = 1.8 // Más delgado para tamaño pequeño
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
  final Function(GlobalKey<_ChatScreenState>)? onScreenCreated; // Callback para registrar el GlobalKey
  
  const ChatScreen({
    super.key, 
    this.chatId, 
    this.projectPath,
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
  String? _currentFileOperation; // 'creando', 'editando', 'leyendo'
  String? _currentFilePath;
  OpenAIService? _openAIService;
  List<String> _selectedImages = [];
  String? _selectedFilePath;
  late String _currentSessionId;
  String? _lastProjectPath;
  Map<String, dynamic>? _lastUserMessage; // Guardar último mensaje para reenviar después de confirmación
  List<String> _selectedDocumentation = []; // URLs de documentación seleccionadas
  bool _isSending = false; // ✅ FIX: Protección contra envíos duplicados
  bool _pendingActionsShown = false; // ✅ FIX: Evitar mensajes duplicados de confirmación
  
  // Run and Debug
  String _selectedPlatform = 'macos';
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
    _currentSessionId = widget.chatId ?? DateTime.now().millisecondsSinceEpoch.toString();
    // Escuchar cambios en la plataforma
    _platformService.addListener(_onPlatformChanged);
    _initialize();
  }

  void _onPlatformChanged() {
    if (mounted) {
      setState(() {
        _selectedPlatform = _platformService.selectedPlatform;
        print('🔧 ChatScreen._onPlatformChanged: Plataforma actualizada a: $_selectedPlatform');
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

  Future<void> _initialize() async {
    // Sincronizar plataforma con PlatformService
    // Si el servicio no tiene plataforma, establecer 'macos' como predeterminada
    if (_platformService.selectedPlatform.isEmpty) {
      _platformService.setPlatform('macos');
    }
    _selectedPlatform = _platformService.selectedPlatform;
    print('🔧 ChatScreen._initialize: Plataforma sincronizada: $_selectedPlatform');
    
    // Resetear estado cuando cambia el proyecto
    final projectPath = widget.projectPath ?? await ProjectService.getProjectPath();
    if (_lastProjectPath != projectPath) {
    setState(() {
      _messages.clear();
      _isLoading = false;
      _loadingStatus = '';
        _currentFileOperation = null;
        _currentFilePath = null;
      _selectedImages.clear();
      _selectedFilePath = null;
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
      final selectedModel = await SettingsService.getSelectedModel();
      _openAIService?.dispose();
      setState(() {
        _openAIService = OpenAIService(apiKey: apiKey, model: selectedModel);
      });
      print('✅ OpenAI Service inicializado con modelo: $selectedModel');
    }
  }

  Future<void> _loadConversation() async {
    try {
      final projectPath = widget.projectPath ?? await ProjectService.getProjectPath();
      if (projectPath == null || projectPath.isEmpty) return;
      
      final messagesJson = await ChatStorageService.loadAgentMessages(_currentSessionId);
      if (messagesJson.isNotEmpty) {
        setState(() {
          _messages.clear();
          _messages.addAll(messagesJson.map((m) => Message.fromJson(m)));
        });
        _scrollToBottom();
      }
    } catch (e) {
      print('⚠️ Error al cargar conversación: $e');
    }
  }

  Future<void> _saveConversation() async {
    try {
      final projectPath = widget.projectPath ?? await ProjectService.getProjectPath();
      if (projectPath == null) return;
      
      final messagesJson = _messages.map((m) => m.toJson()).toList();
      await ChatStorageService.saveAgentMessages(_currentSessionId, messagesJson, projectPath: projectPath);
    } catch (e) {
      print('⚠️ Error al guardar conversación: $e');
    }
  }

  Future<void> _sendMessage() async {
    final hasText = _messageController.text.trim().isNotEmpty;
    final hasImages = _selectedImages.isNotEmpty;
    
    // ✅ FIX: Protección contra envíos duplicados y carga infinita
    if ((!hasText && !hasImages) || _isLoading || _isSending) {
      print('⚠️ Intento de envío duplicado bloqueado: _isLoading=$_isLoading, _isSending=$_isSending');
      return;
    }
    
    _isSending = true; // ✅ Marcar como enviando
    
    if (_openAIService == null) {
        try {
          await _loadOpenAIService();
        if (_openAIService == null) {
          _openSettings();
          return;
        }
      } catch (e) {
        print('❌ Error al inicializar OpenAI Service: $e');
        return;
      }
    }
    
    final projectPath = widget.projectPath ?? await ProjectService.getProjectPath();
    if (projectPath == null || projectPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay proyecto cargado. Por favor carga un proyecto primero.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    final imagesToSend = List<String>.from(_selectedImages);
    final filePathToSend = _selectedFilePath;

    String userMessage = _messageController.text.trim().isEmpty 
        ? (hasImages ? 'Analiza esta imagen y describe lo que ves' : '')
        : _messageController.text.trim();

    final bool isErrorReport = _isErrorReportDraft ||
        userMessage.contains('Errores de Compilación/Ejecución');

    // Si es un reporte de errores, limitar tamaño para evitar bloqueos
    if (isErrorReport && userMessage.length > 6000) {
      userMessage = '${userMessage.substring(0, 6000)}\n\n...[Errores truncados para evitar bloqueo]';
    }
    _messageController.clear();

    try {
      // Obtener projectPath antes de usarlo
      final currentProjectPath = widget.projectPath ?? await ProjectService.getProjectPath();
      
      if (mounted) {
        setState(() {
          _loadingStatus = 'Construyendo contexto optimizado...';
        });
      }
      
      // ✨ NUEVO SISTEMA INTELIGENTE DE CONTEXTO ✨
      // Construye contexto optimizado automáticamente con timeout para evitar cuelgues
      ContextBundle contextBundle;
      try {
        contextBundle = await SmartContextManager.buildOptimizedContext(
          userMessage: userMessage,
          projectPath: currentProjectPath ?? '',
          sessionId: _currentSessionId,
          selectedFiles: _selectedFilePath != null ? [_selectedFilePath!] : null,
          includeDocumentation: SmartContextManager.needsDocumentation(userMessage),
          includeHistory: true,
          includeProjectStructure: SmartContextManager.needsFullContext(userMessage),
        ).timeout(
          const Duration(seconds: 10), // ✅ FIX: Timeout para evitar cuelgues
          onTimeout: () {
            print('⚠️ Timeout al construir contexto, usando contexto mínimo');
            return ContextBundle(
              content: userMessage,
              estimatedTokens: SmartContextManager.estimateTokens(userMessage),
              metadata: {'timeout': true},
            );
          },
        );
      } catch (e) {
        print('❌ Error al construir contexto: $e');
        // Usar contexto mínimo si falla
        contextBundle = ContextBundle(
          content: userMessage,
          estimatedTokens: SmartContextManager.estimateTokens(userMessage),
          metadata: {'error': e.toString()},
        );
      }
      
      print('📊 Contexto: ${contextBundle.summary}, ${contextBundle.estimatedTokens} tokens');
      
      if (mounted) {
        setState(() {
          _loadingStatus = 'Pensando en la solución... (${contextBundle.estimatedTokens} tokens)';
        });
      }
      
      // Guardar mensaje en memoria persistente
      await ConversationMemoryService.addMessage(
        role: 'user',
        content: userMessage,
        sessionId: _currentSessionId,
        metadata: {
          'hasImages': imagesToSend.isNotEmpty,
          'hasFiles': _selectedFilePath != null,
        },
      );
      
      // El contexto ya está optimizado y listo para enviar
      final enhancedMessage = contextBundle.content;
      
      // Usar system prompt del contexto optimizado
      final systemPrompt = ''; // Ya está incluido en enhancedMessage
      
      final conversationHistory = _messages.map((msg) {
        return {
          'role': msg.role,
          'content': msg.content,
        };
      }).toList();
      
      // fileContent ya no se usa - el contexto está optimizado
      final fileContent = null; // Para compatibilidad con código existente
      
      // Guardar mensaje del usuario para reenviar después de confirmación
      _lastUserMessage = {
        'message': enhancedMessage,
        'imagePaths': imagesToSend,
        'conversationHistory': conversationHistory,
        'fileContent': fileContent,
        'systemPrompt': systemPrompt.isNotEmpty ? systemPrompt : null,
        'projectPath': currentProjectPath,
      };

      final bool allowTools = !isErrorReport;
      
      // ✅ FIX: Detectar SOLO si es una solicitud DIRECTA de run/debug (no preguntas)
      final lowerMessage = userMessage.toLowerCase();
      final isQuestion = lowerMessage.contains('cómo') || 
          lowerMessage.contains('como') ||
          lowerMessage.contains('puedo') ||
          lowerMessage.contains('debo') ||
          lowerMessage.contains('necesito') ||
          lowerMessage.contains('quiero') ||
          lowerMessage.contains('?');
      
      final hasRunDebugWords = lowerMessage.contains('run') ||
          lowerMessage.contains('debug') ||
          lowerMessage.contains('ejecuta') ||
          lowerMessage.contains('compila') ||
          lowerMessage.contains('corre') ||
          lowerMessage.contains('inicia');
      
      // Solo ejecutar directamente si tiene palabras de run/debug Y NO es una pregunta
      final isSimpleRunRequest = hasRunDebugWords && !isQuestion;
      
      // Si es una solicitud simple de run/debug, ejecutar directamente sin esperar respuesta del agente
      if (isSimpleRunRequest) {
        print('🚀 Solicitud DIRECTA de run/debug detectada (no es pregunta), ejecutando...');
        
        // ✅ FIX: Agregar mensaje del usuario al chat
        final userMsg = Message(
          role: 'user',
          content: userMessage,
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
            _loadingStatus = 'Ejecutando...';
            _isSending = false; // ✅ FIX: Limpiar flag ya que se ejecuta directamente
          });
          await _saveConversation();
          _scrollToBottom();
        }
        
        // Ejecutar directamente según la solicitud
        if (lowerMessage.contains('debug') || lowerMessage.contains('depura')) {
          print('🚀 Ejecutando DEBUG directamente');
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              _handleDebug();
            }
          });
          return; // Salir temprano, no enviar al agente
        } else {
          print('🚀 Ejecutando RUN directamente');
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              _handleRun();
            }
          });
          return; // Salir temprano, no enviar al agente
        }
      }
      
      // ✅ FIX: Agregar mensaje del usuario (flujo normal)
      final userMsg = Message(
        role: 'user',
        content: userMessage,
        timestamp: DateTime.now(),
        imageUrls: imagesToSend.isNotEmpty ? imagesToSend : null,
        filePath: filePathToSend,
      );

      if (mounted) {
        setState(() {
          _messages.add(userMsg);
          _isLoading = true;
          _selectedImages.clear();
          _selectedFilePath = null;
        });
        _scrollToBottom();
      }

      // ✅ FIX: Agregar timeout para evitar cuelgues
      final response = await _openAIService!.sendMessage(
        message: enhancedMessage,
        imagePaths: imagesToSend.isNotEmpty ? imagesToSend : null,
        conversationHistory: conversationHistory,
        fileContent: fileContent,
        systemPrompt: systemPrompt.isNotEmpty ? systemPrompt : null,
        projectPath: currentProjectPath, // CRÍTICO: Necesario para Function Calling
        allowTools: allowTools,
        onFileOperation: allowTools ? (operation, filePath) {
          // Actualizar estado cuando se ejecuta una operación de archivo
          if (mounted) {
            setState(() {
              _currentFileOperation = operation;
              _currentFilePath = filePath;
            });
          }
        } : null,
        onPendingActions: (allowTools && !isSimpleRunRequest) ? (pendingActionsList) {
          // Convertir a objetos PendingAction y mostrar diálogo de confirmación
          print('🔔 onPendingActions callback recibido con ${pendingActionsList.length} acciones');
          if (mounted) {
            final pendingActions = pendingActionsList.map((action) {
              return PendingAction(
                id: action['id'] as String,
                functionName: action['functionName'] as String,
                arguments: Map<String, dynamic>.from(action['arguments']),
                description: action['description'] as String,
                timestamp: action['timestamp'] != null 
                    ? DateTime.parse(action['timestamp'])
                    : DateTime.now(),
                toolCallId: action['toolCallId'] as String?,
                reasoning: action['reasoning'] as String?,
                diff: action['diff'] as String?,
                oldContent: action['oldContent'] as String?,
                newContent: action['newContent'] as String?,
              );
            }).toList();
            
            print('✅ ${pendingActions.length} acciones convertidas a PendingAction');

            final allReadOnly = pendingActions.every(
              (action) => action.functionName == 'read_file',
            );
            
            if (mounted) {
              setState(() {
                _isLoading = false; // Detener loading para mostrar tarjeta
              });

              if (allReadOnly) {
                // ✅ FIX: Lecturas son seguras, ejecutar sin confirmación
                print('✅ Acciones solo de lectura detectadas, ejecutando sin confirmación...');
                _pendingActionsShown = false;
                _executeConfirmedActions(pendingActions);
                return;
              }

              print('🔔 Agregando mensaje con acciones pendientes al chat...');
              // ✅ NUEVO: Agregar mensaje especial con acciones pendientes en lugar de diálogo
              final pendingActionsMsg = Message(
                role: 'assistant',
                content: 'Esperando tu confirmación para ejecutar ${pendingActions.length} acción(es).',
                timestamp: DateTime.now(),
                pendingActions: pendingActions, // ✅ Agregar acciones pendientes al mensaje
              );
              setState(() {
                _messages.add(pendingActionsMsg);
                _pendingActionsShown = true;
              });
              _scrollToBottom();
              print('✅ Mensaje con acciones pendientes agregado al chat');
            }
          } else {
            print('❌ Widget no está montado, no se puede mostrar diálogo');
          }
        } : null,
      ).timeout(
        const Duration(seconds: 120), // ✅ FIX: Timeout de 2 minutos para evitar cuelgues infinitos
        onTimeout: () {
          throw TimeoutException('La solicitud tardó demasiado. Intenta de nuevo con un mensaje más corto.');
        },
      );

      // ✅ FIX: Evitar duplicado de "Esperando confirmación" cuando ya se mostró la tarjeta
      if (_pendingActionsShown &&
          response.trim().toLowerCase().startsWith('esperando tu confirmación')) {
        _pendingActionsShown = false;
        return;
      }

      final assistantMsg = Message(
        role: 'assistant',
        content: response,
        timestamp: DateTime.now(),
      );
      
      // Guardar respuesta del asistente en memoria persistente
      await ConversationMemoryService.addMessage(
        role: 'assistant',
        content: response,
        sessionId: _currentSessionId,
      );

      if (mounted) {
        setState(() {
          _messages.add(assistantMsg);
          _isLoading = false;
          _loadingStatus = '';
          _currentFileOperation = null;
          _currentFilePath = null;
          _isErrorReportDraft = false;
          _isSending = false; // ✅ FIX: Limpiar flag de envío
        });
        await _saveConversation();
        _scrollToBottom();
        
        // Si es una solicitud simple de run/debug, ejecutar directamente
        if (isSimpleRunRequest) {
          final lowerResponse = response.toLowerCase();
          if (lowerResponse.contains('debug') || lowerResponse.contains('depura')) {
            print('🚀 Ejecutando DEBUG automáticamente desde solicitud del usuario');
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                _handleDebug();
              }
            });
          } else if (lowerResponse.contains('run') || lowerResponse.contains('ejecut') || lowerResponse.contains('compil')) {
            print('🚀 Ejecutando RUN automáticamente desde solicitud del usuario');
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                _handleRun();
              }
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingStatus = '';
          _currentFileOperation = null;
          _currentFilePath = null;
          _isErrorReportDraft = false;
          _isSending = false; // ✅ FIX: Limpiar flag de envío
        });
        
        // ✅ FIX: Mensajes de error más amigables
        String errorMessage = 'Error al procesar la solicitud';
        if (e is TimeoutException) {
          errorMessage = '⏱️ La solicitud tardó demasiado. Intenta con un mensaje más corto o verifica tu conexión.';
        } else if (e.toString().contains('timeout') || e.toString().contains('Timeout')) {
          errorMessage = '⏱️ La solicitud tardó demasiado. Intenta con un mensaje más corto.';
        } else if (e.toString().contains('network') || e.toString().contains('Network')) {
          errorMessage = '🌐 Error de conexión. Verifica tu internet e intenta de nuevo.';
        } else if (e.toString().contains('cancel') || e.toString().contains('Cancel')) {
          errorMessage = '⏸️ Solicitud cancelada por el usuario.';
        } else {
          errorMessage = '❌ Error: ${e.toString().length > 100 ? e.toString().substring(0, 100) + "..." : e.toString()}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      // ✅ FIX: Asegurar que siempre se limpie el flag de envío
      if (mounted) {
        _isSending = false;
      }
    }
  }

  // ✅ NUEVO: Manejar aceptación de acciones desde la tarjeta del chat
  Future<void> _handleAcceptActions(List<PendingAction> actions, int messageIndex) async {
    print('✅ Aceptando ${actions.length} acciones desde el chat');
    
    // Remover el mensaje con acciones pendientes y agregar uno nuevo confirmando
    if (mounted) {
      setState(() {
        _messages.removeAt(messageIndex);
        _messages.insert(messageIndex, Message(
          role: 'assistant',
          content: '✅ Ejecutando ${actions.length} acción(es)...',
          timestamp: DateTime.now(),
        ));
        _isLoading = true;
      });
      _scrollToBottom();
    }
    
    // Ejecutar las acciones
    await _executeConfirmedActions(actions);
  }
  
  // ✅ NUEVO: Manejar rechazo de acciones desde la tarjeta del chat
  void _handleRejectActions(int messageIndex) {
    print('❌ Rechazando acciones desde el chat');
    
    if (mounted) {
      setState(() {
        _messages.removeAt(messageIndex);
        _messages.insert(messageIndex, Message(
          role: 'assistant',
          content: '❌ Acciones canceladas por el usuario.',
          timestamp: DateTime.now(),
        ));
        _isLoading = false;
      });
      _scrollToBottom();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acciones canceladas'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _executeConfirmedActions(List<PendingAction> acceptedActions) async {
    if (_openAIService == null || _lastUserMessage == null) return;
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _loadingStatus = 'Ejecutando acciones confirmadas...';
    });

    try {
      // Reenviar el mensaje pero SIN el callback onPendingActions para que se ejecuten directamente
      // Esto es un workaround - en una implementación ideal necesitaríamos un método separado
      final response = await _openAIService!.sendMessage(
        message: _lastUserMessage!['message'] as String,
        imagePaths: _lastUserMessage!['imagePaths'] as List<String>?,
        conversationHistory: _lastUserMessage!['conversationHistory'] as List<Map<String, dynamic>>?,
        fileContent: _lastUserMessage!['fileContent'] as String?,
        systemPrompt: _lastUserMessage!['systemPrompt'] as String?,
        projectPath: _lastUserMessage!['projectPath'] as String?,
        onFileOperation: (operation, filePath) {
          if (mounted) {
            setState(() {
              _currentFileOperation = operation;
              _currentFilePath = filePath;
            });
          }
        },
        // NO pasar onPendingActions - esto hará que se ejecuten directamente
      ).timeout(
        const Duration(seconds: 120), // ✅ FIX: Timeout de 2 minutos
        onTimeout: () {
          throw TimeoutException('La solicitud tardó demasiado. Intenta de nuevo con un mensaje más corto.');
        },
      );

      final assistantMsg = Message(
        role: 'assistant',
        content: response,
        timestamp: DateTime.now(),
      );
      
      // Guardar respuesta del asistente en memoria persistente
      await ConversationMemoryService.addMessage(
        role: 'assistant',
        content: response,
        sessionId: _currentSessionId,
      );

      if (mounted) {
        setState(() {
          _messages.add(assistantMsg);
          _isLoading = false;
          _loadingStatus = '';
          _currentFileOperation = null;
          _currentFilePath = null;
        });
        await _saveConversation();
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al ejecutar acciones: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _stopRequest() {
    print('🛑 Deteniendo petición...');
    
    // ✅ FIX: Cancelar petición HTTP
    _openAIService?.cancelRequest();
    
    // ✅ FIX: Detener proceso en ejecución si existe
    if (_runningProcess != null) {
      print('🛑 Deteniendo proceso en ejecución...');
      try {
        _runningProcess!.kill();
        _runningProcess = null;
      } catch (e) {
        print('⚠️ Error al detener proceso: $e');
      }
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
    // Usar microtask para asegurar que se ejecute después del frame actual
    // y evitar conflictos con el layout
    Future.microtask(() {
      if (!mounted) return;
      if (_scrollController.hasClients && _scrollController.position.maxScrollExtent > 0) {
        try {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } catch (e) {
          print('⚠️ Error en _scrollToBottom: $e');
        }
      }
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
  
  Future<void> _handleRun() async {
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
      final projectType = await ProjectTypeDetector.detectProjectType(projectPath);
      
      if (projectType == ProjectType.unknown) {
        print('❌ ChatScreen._handleRun: TIPO DE PROYECTO DESCONOCIDO: $projectPath');
        
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
                  const Icon(Icons.error_outline, color: Colors.orange, size: 24),
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
                      ...missingFiles.map((file) => Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.warning, color: Colors.orange, size: 16),
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
                      )),
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
                              const Icon(Icons.lightbulb_outline, color: Colors.blue, size: 16),
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
                            style: TextStyle(color: CursorTheme.textSecondary, fontSize: 12),
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
                  child: const Text('Entendido', style: TextStyle(color: CursorTheme.primary)),
                ),
              ],
            ),
          );
        }
        return;
      }
      
      final projectTypeName = ProjectTypeDetector.getProjectTypeName(projectType);
      final projectTypeIcon = ProjectTypeDetector.getProjectTypeIcon(projectType);
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
      _debugService.setCompilationProgress(0.05, 'Iniciando $projectTypeName...');
      // Abrir Debug Console automáticamente al ejecutar
      _debugService.openPanel();
      _debugService.clearAll();
      
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

      // Analizar progreso
      String currentStatus = 'Iniciando $projectTypeName...';
      
      // Para Flutter, usar el sistema existente con dispositivos
      if (projectType == ProjectType.flutter) {
        // Sincronizar plataforma antes de ejecutar
        _selectedPlatform = _platformService.selectedPlatform;
        print('🚀 Ejecutando Flutter en plataforma: $_selectedPlatform');
        print('🔧 PlatformService.selectedPlatform: ${_platformService.selectedPlatform}');
        
        // Asegurar que la plataforma seleccionada se use correctamente
        // Priorizar _selectedPlatform, luego PlatformService, finalmente 'macos' como fallback
        final platformToUse = _selectedPlatform.isNotEmpty 
            ? _selectedPlatform 
            : (_platformService.selectedPlatform.isNotEmpty 
                ? _platformService.selectedPlatform 
                : 'macos');
        print('✅ Usando plataforma: $platformToUse');
        print('   _selectedPlatform: $_selectedPlatform');
        print('   _platformService.selectedPlatform: ${_platformService.selectedPlatform}');
        
        // Determinar si debemos usar web-server (solo para fallback Android/iOS, NO para web normal)
        // useWebServer = false significa que para la plataforma web normal se usará chrome (navegador externo)
        // Esto solo se activará en el fallback más adelante
        
      final result = await AdvancedDebuggingService.runFlutterApp(
        projectPath: projectPath,
          platform: platformToUse,
          mode: 'release',
          useWebServer: false, // Para la plataforma web normal, usar chrome
        onOutput: (line) {
          _debugService.addOutput(line);
          _debugService.addDebugConsole(line);
          _maybeCaptureVmServiceUri(line);
          
            print('📥 Flutter output: $line');
            
            // ✅ DETECCIÓN ESPECIAL: Proyecto sin soporte web
            if (line.contains('This application is not configured to build on the web') ||
                line.contains('To add web support to a project, run `flutter create .`') ||
                (line.contains('PathNotFoundException') && line.contains('web/') && line.contains('No such file or directory'))) {
              print('🔴 Error detectado: Proyecto sin soporte web');
              hasWebSupportError = true; // ✅ Marcar que hay error de soporte web
              _debugService.addOutput('\n⚠️ PROYECTO SIN SOPORTE WEB\n');
              _debugService.addOutput('Este proyecto Flutter no tiene configurado el soporte para web.\n');
              _debugService.addOutput('Para agregar soporte web, ejecuta: flutter create .\n');
              _debugService.addOutput('O cambia la plataforma a Android/iOS/macOS desde el selector.\n\n');
              _debugService.addProblem(line);
              
              // ✅ DETENER PROCESO Y LIMPIAR ESTADO
              setState(() {
                _isRunning = false;
              });
              _debugService.setRunning(false);
              _debugService.setAppUrl(null); // ✅ NO establecer URL si hay error
              _debugService.setCompilationProgress(0.0, 'Error: Proyecto sin soporte web');
              
              // Mostrar mensaje claro al usuario
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      '⚠️ Este proyecto no tiene soporte web. Ejecuta "flutter create ." o cambia a otra plataforma.',
                      style: TextStyle(color: Colors.white),
                    ),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 5),
                    action: SnackBarAction(
                      label: 'Ver detalles',
                      textColor: Colors.white,
                      onPressed: () {
                        _debugService.openPanel();
                      },
                    ),
                  ),
                );
              }
              
              // No marcar como error crítico adicional, es un problema del proyecto, no de la app
              // Ya se agregó a problemas arriba, así que no procesamos más esta línea
            } else {
              // Detectar errores (solo si no es el error de soporte web)
              final lowerLine = line.toLowerCase();
              if (RegExp(r'\.dart:\d+:\d+:\s*(error|warning):').hasMatch(line) ||
                  (lowerLine.contains('error:') && !lowerLine.contains('no error')) ||
                  (lowerLine.contains('failed') && !lowerLine.contains('no devices found')) ||
                  lowerLine.contains('undefined name') ||
                  lowerLine.contains('undefined class') ||
                  lowerLine.contains('undefined method') ||
                  lowerLine.contains('undefined getter') ||
                  lowerLine.contains('syntax error') ||
                  (lowerLine.contains('cannot') && (lowerLine.contains('find') || lowerLine.contains('resolve')))) {
                _debugService.addProblem(line);
                print('🔴 Error detectado: $line');
              }
            }
          
            // Analizar progreso
            double progress = _debugService.compilationProgress;
          String status = currentStatus;
          
          if (line.contains('Running Gradle task') || line.contains('Running pod install')) {
            status = 'Configurando dependencias...';
            progress = 0.15;
          } else if (line.contains('Resolving dependencies') || line.contains('Downloading')) {
            status = 'Descargando dependencias...';
            progress = 0.25;
          } else if (line.contains('Building') || line.contains('Compiling') || line.contains('Assembling')) {
            status = 'Compilando código...';
            progress = 0.45;
          } else if (line.contains('Running') && line.contains('flutter')) {
            status = 'Ejecutando aplicación...';
            progress = 0.75;
          } else if (line.contains('Launching') || line.contains('Starting')) {
            status = 'Iniciando aplicación...';
            progress = 0.85;
          } else if (line.contains('Flutter run key commands') || line.contains('An Observatory debugger')) {
            status = 'Aplicación ejecutándose';
            progress = 1.0;
          } else if (line.contains('Syncing files') || line.contains('Waiting for')) {
            status = 'Sincronizando archivos...';
            progress = 0.35;
          } else if (line.contains('%')) {
            final percentMatch = RegExp(r'(\d+)%').firstMatch(line);
            if (percentMatch != null) {
              final percent = int.parse(percentMatch.group(1)!);
              progress = percent / 100.0;
              status = 'Compilando... $percent%';
            }
          }
          
          if (progress > _debugService.compilationProgress) {
            _debugService.setCompilationProgress(progress, status);
            currentStatus = status;
          }
          
            // Detectar URL para web - patrones más amplios para Flutter web
            if (platformToUse == 'web') {
              print('🔍 Buscando URL en línea para Flutter web: "$line"');
              
              // Patrón 1: "The Flutter DevTools debugger and profiler on [platform] is available at: http://localhost:XXXXX"
              RegExpMatch? urlMatch = RegExp(r'available at:\s*(http://[^\s]+)', caseSensitive: false).firstMatch(line);
            if (urlMatch != null) {
                detectedUrl = urlMatch.group(1)!.trim();
              _debugService.setAppUrl(detectedUrl);
                print('🌐 ✅✅✅ URL detectada (available at): $detectedUrl');
                if (mounted) {
                  setState(() {
                    _isRunning = true;
                  });
                }
                _debugService.setRunning(true);
                _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose');
              } else {
                // Patrón 2: "http://localhost:XXXXX" o "http://127.0.0.1:XXXXX"
                urlMatch = RegExp(r'http://(localhost|127\.0\.0\.1):(\d+)').firstMatch(line);
                if (urlMatch != null) {
                  final host = urlMatch.group(1)!;
                  final port = urlMatch.group(2)!;
                  detectedUrl = 'http://$host:$port';
                  _debugService.setAppUrl(detectedUrl);
                  print('🌐 ✅✅✅ URL detectada (http://$host:$port): $detectedUrl');
                  if (mounted) {
                    setState(() {
                      _isRunning = true;
                    });
                  }
                  _debugService.setRunning(true);
                  _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose');
                } else {
                  // Patrón 3: Cualquier URL http:// en la línea
                  urlMatch = RegExp(r'(http://[^\s:]+:\d+)').firstMatch(line);
                  if (urlMatch != null) {
                    detectedUrl = urlMatch.group(1)!.trim();
                    _debugService.setAppUrl(detectedUrl);
                    print('🌐 ✅✅✅ URL detectada (genérico): $detectedUrl');
                    if (mounted) {
                      setState(() {
                        _isRunning = true;
                      });
                    }
                    _debugService.setRunning(true);
                    _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose');
                  }
                }
              }
              
              // ✅ También detectar cuando Chrome se abre (indica que la app está lista)
              // PERO solo si NO hay error de soporte web
              if (!hasWebSupportError && line.contains('Chrome') && (line.contains('Launching') || line.contains('Starting'))) {
                // Si no se detectó URL aún, usar localhost:8080 como fallback (puerto común de Flutter web)
                if (detectedUrl == null) {
                  detectedUrl = 'http://localhost:8080';
                  _debugService.setAppUrl(detectedUrl);
                  print('🌐 ✅ URL establecida por defecto (Chrome detectado): $detectedUrl');
                  if (mounted) {
                    setState(() {
                      _isRunning = true;
                    });
                  }
                  _debugService.setRunning(true);
                  _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose');
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
        print('🚫 NO estableciendo URL final: Error de soporte web detectado');
      }

        // Variables para detectar si se ejecutó el fallback web
        bool fallbackWebExecuted = false;
        final isAndroidOrIOS = platformToUse.toLowerCase() == 'android' || platformToUse.toLowerCase() == 'ios';
        
        // Para Flutter web, mantener _isRunning en true si la compilación fue exitosa
        // Para otras plataformas (Android/iOS/macOS), la app se ejecuta en el dispositivo/emulador
        if (platformToUse == 'web' && result.success) {
          print('✅ Flutter web ejecutándose correctamente, manteniendo _isRunning = true');
          if (mounted) {
      setState(() {
              _isRunning = true;
            });
          }
          _debugService.setRunning(true);
          _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose');
        } else if (result.success) {
          // Para Android/iOS/macOS, la app se ejecuta en el dispositivo/emulador
          // NO establecer URL (solo para web)
          print('✅ Flutter ${platformToUse} ejecutándose en dispositivo/emulador');
          if (mounted) {
            setState(() {
              _isRunning = true; // Mantener en true para mostrar que está ejecutándose
            });
          }
          _debugService.setRunning(true);
          _debugService.setAppUrl(null); // Asegurar que no hay URL para apps nativas
          _debugService.setCompilationProgress(1.0, 'Aplicación ejecutándose en ${platformToUse.toUpperCase()}');
        } else {
          // Compilación fallida - verificar si es por falta de dispositivo Android/iOS
          final errorMessage = result.errors.isNotEmpty 
              ? result.errors.join('\n')
              : 'La compilación falló. Revisa el Debug Console para más detalles.';
          
          final isNoDeviceError = errorMessage.contains('No se encontró dispositivo disponible') ||
                                 errorMessage.contains('No se encontró dispositivo para la plataforma');
          
          // Si es Android/iOS y no hay dispositivo, ejecutar automáticamente la versión web como fallback
          if (isAndroidOrIOS && isNoDeviceError) {
            print('📱 No se encontró dispositivo para $platformToUse. Ejecutando versión web como fallback...');
            _debugService.addDebugConsole('📱 No se encontró dispositivo para $platformToUse');
            _debugService.addDebugConsole('🌐 Ejecutando versión web como fallback...');
            _debugService.setCompilationProgress(0.1, 'Ejecutando versión web como fallback...');
            
            // Ejecutar la versión web
            String? webDetectedUrl;
            bool webUrlDetected = false;
            
            final webResult = await AdvancedDebuggingService.runFlutterApp(
              projectPath: projectPath,
              platform: 'web',
              mode: 'release',
              useWebServer: true, // Usar web-server para NO abrir navegador externo (fallback Android/iOS)
              webRenderer: 'html', // Necesario para inspector (DOM) en WebView
              onOutput: (line) {
                _debugService.addOutput(line);
                _debugService.addDebugConsole(line);
                _maybeCaptureVmServiceUri(line);
                
                print('📥 Flutter web (fallback) output: $line');
                
                // Detectar URL para web
                if (!webUrlDetected) {
                  // Patrón 1: "available at: http://..."
                  RegExpMatch? urlMatch = RegExp(r'available at:\s*(http://[^\s]+)', caseSensitive: false).firstMatch(line);
                  if (urlMatch != null) {
                    webDetectedUrl = urlMatch.group(1)!.trim();
                    _debugService.setAppUrl(webDetectedUrl);
                    webUrlDetected = true;
                    print('🌐 ✅✅✅ URL detectada (fallback web): $webDetectedUrl');
                    if (mounted) {
                      setState(() {
                        _isRunning = true;
                      });
                    }
                    _debugService.setRunning(true);
                    _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (fallback para $platformToUse)');
                  } else {
                    // Patrón 2: "http://localhost:XXXXX" o "http://127.0.0.1:XXXXX"
                    urlMatch = RegExp(r'http://(localhost|127\.0\.0\.1):(\d+)').firstMatch(line);
                    if (urlMatch != null) {
                      final host = urlMatch.group(1)!;
                      final port = urlMatch.group(2)!;
                      webDetectedUrl = 'http://$host:$port';
                      _debugService.setAppUrl(webDetectedUrl);
                      webUrlDetected = true;
                      print('🌐 ✅✅✅ URL detectada (fallback web): $webDetectedUrl');
                      if (mounted) {
                        setState(() {
                          _isRunning = true;
                        });
                      }
                      _debugService.setRunning(true);
                      _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (fallback para $platformToUse)');
                    } else {
                      // Patrón 3: Cualquier URL http:// en la línea
                      urlMatch = RegExp(r'(http://[^\s:]+:\d+)').firstMatch(line);
                      if (urlMatch != null) {
                        webDetectedUrl = urlMatch.group(1)!.trim();
                        _debugService.setAppUrl(webDetectedUrl);
                        webUrlDetected = true;
                        print('🌐 ✅✅✅ URL detectada (fallback web): $webDetectedUrl');
                        if (mounted) {
                          setState(() {
                            _isRunning = true;
                          });
                        }
                        _debugService.setRunning(true);
                        _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (fallback para $platformToUse)');
                      }
                    }
                  }
                  
                  // Fallback si se detecta Chrome pero no URL específica
                  if (webDetectedUrl == null && line.contains('Chrome') && (line.contains('Launching') || line.contains('Starting'))) {
                    webDetectedUrl = 'http://localhost:8080';
                    _debugService.setAppUrl(webDetectedUrl);
                    webUrlDetected = true;
                    print('🌐 ✅ URL establecida por defecto (fallback web): $webDetectedUrl');
                    if (mounted) {
                      setState(() {
                        _isRunning = true;
                      });
                    }
                    _debugService.setRunning(true);
                    _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (fallback para $platformToUse)');
                  }
                }
              },
              onError: (error) {
                _debugService.addProblem(error.toString());
                _debugService.setCompilationProgress(0.0, 'Error en compilación web (fallback)');
              },
            );
            
            if (webResult.success && webDetectedUrl != null) {
              print('✅ Versión web ejecutándose correctamente como fallback para $platformToUse');
              fallbackWebExecuted = true;
              if (mounted) {
                setState(() {
                  _isRunning = true;
                });
              }
              _debugService.setRunning(true);
              _debugService.setAppUrl(webDetectedUrl);
              _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (fallback para $platformToUse)');
            } else {
              // Si el fallback web también falla, mostrar error
              setState(() {
                _isRunning = false;
              });
      _debugService.setRunning(false);
              _debugService.setAppUrl(null);
              _debugService.setCompilationProgress(1.0, errorMessage);
            }
          } else {
            // Error normal (no es por falta de dispositivo)
            setState(() {
              _isRunning = false;
            });
            _debugService.setRunning(false);
            _debugService.setAppUrl(null); // Limpiar URL en caso de error
            _debugService.setCompilationProgress(1.0, errorMessage); // Establecer mensaje de error en compilationStatus
          }
        }
        
        // Solo mostrar diálogo de error si no se ejecutó el fallback web exitosamente
        if (!result.success && mounted && !fallbackWebExecuted) {
          final errorMessage = result.errors.isNotEmpty 
              ? result.errors.join('\n')
              : 'La compilación falló. Revisa el Debug Console para más detalles.';
          showDialog(
            context: context,
            builder: (context) => ErrorConfirmationDialog(
              title: 'Compilación fallida',
              message: errorMessage,
              showViewErrorsButton: true,
              onViewErrors: () {
                _debugService.openPanel();
              },
            ),
          );
        }
      } else {
        // EJECUCIÓN UNIVERSAL para otros lenguajes
        print('🎯 Ejecutando comando personalizado: ${runCommand.command} ${runCommand.args.join(' ')}');
        
        // Detectar si es un proceso de servidor de larga duración
        final isLongRunningServer = projectType == ProjectType.fastapi ||
            projectType == ProjectType.django ||
            projectType == ProjectType.flask ||
            projectType == ProjectType.nodejs ||
            projectType == ProjectType.react ||
            projectType == ProjectType.nextjs ||
            projectType == ProjectType.vue ||
            projectType == ProjectType.vite ||
            runCommand.command.contains('uvicorn') ||
            runCommand.command.contains('gunicorn') ||
            runCommand.command.contains('runserver') ||
            runCommand.command.contains('npm') && (runCommand.args.contains('start') || runCommand.args.contains('dev')) ||
            runCommand.command.contains('yarn') && (runCommand.args.contains('start') || runCommand.args.contains('dev'));
        
        try {
          final process = await Process.start(
            runCommand.command,
            runCommand.args,
            workingDirectory: runCommand.workingDirectory,
            runInShell: true,
            environment: runCommand.environment,
          );
          
          // Guardar referencia al proceso para poder detenerlo
          _runningProcess = process;
          
          _debugService.addOutput('$projectTypeIcon Ejecutando: ${runCommand.description}');
          _debugService.addOutput('📁 Directorio: ${runCommand.workingDirectory}');
          _debugService.addOutput('🚀 Comando: ${runCommand.command} ${runCommand.args.join(' ')}');
          _debugService.addOutput('');
          _debugService.setCompilationProgress(0.2, 'Ejecutando...');
          
          // Variables para rastrear el estado del proceso
          bool hasReceivedOutput = false;
          bool urlDetected = false; // Flag para detectar URL solo una vez
          
          // Verificar si ya hay una URL establecida (por si acaso)
          if (_debugService.appUrl != null && _debugService.appUrl!.isNotEmpty) {
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
              _debugService.addOutput(line);
              _debugService.addDebugConsole(line);
              
              print('🔍 Analizando línea STDOUT: "$line"');
              
              // Detectar URL SOLO UNA VEZ y solo en mensajes específicos de inicio de servidor
              // NO detectar en logs de peticiones HTTP (GET, POST, etc)
              // También verificar si ya hay una URL establecida en el servicio
              if (!urlDetected && (_debugService.appUrl == null || _debugService.appUrl!.isEmpty)) {
                final lowerLine = line.toLowerCase();
                
                // Solo buscar URL si la línea contiene indicadores claros de inicio de servidor
                // Y NO contiene indicadores de peticiones HTTP
                final isServerStartupMessage = (lowerLine.contains('uvicorn running on') || 
                    lowerLine.contains('starting development server at') ||
                    lowerLine.contains('server running on') ||
                    lowerLine.contains('serving on') ||
                    lowerLine.contains('listening on'));
                
                final isHttpRequestLog = lowerLine.contains('get ') || 
                    lowerLine.contains('post ') || 
                    lowerLine.contains('put ') || 
                    lowerLine.contains('delete ') ||
                    lowerLine.contains('" 200 ') ||
                    lowerLine.contains('" 404 ') ||
                    lowerLine.contains('" 500 ');
                
                if (isServerStartupMessage && !isHttpRequestLog) {
                  print('✅ Línea contiene indicador de inicio de servidor (no es log de petición)');
                  
                  if (line.contains('0.0.0.0:')) {
                    final portMatch = RegExp(r'0\.0\.0\.0:(\d+)').firstMatch(line);
                    if (portMatch != null) {
                      final port = portMatch.group(1);
                      detectedUrl = 'http://localhost:$port';
                      _debugService.setAppUrl(detectedUrl);
                      urlDetected = true;
                      print('🌐 ✅✅✅ URL DETECTADA EN STDOUT: 0.0.0.0:$port -> $detectedUrl (detección bloqueada para futuras líneas)');
                    }
                  } else if (line.contains('localhost:')) {
                    final portMatch = RegExp(r'localhost:(\d+)').firstMatch(line);
                    if (portMatch != null) {
                      final port = portMatch.group(1);
                      detectedUrl = 'http://localhost:$port';
                      _debugService.setAppUrl(detectedUrl);
                      urlDetected = true;
                      print('🌐 ✅✅✅ URL DETECTADA EN STDOUT: localhost:$port -> $detectedUrl (detección bloqueada)');
                    }
                  } else if (line.contains('127.0.0.1:')) {
                    final portMatch = RegExp(r'127\.0\.0\.1:(\d+)').firstMatch(line);
                    if (portMatch != null) {
                      final port = portMatch.group(1);
                      detectedUrl = 'http://127.0.0.1:$port';
                      _debugService.setAppUrl(detectedUrl);
                      urlDetected = true;
                      print('🌐 ✅✅✅ URL DETECTADA EN STDOUT: 127.0.0.1:$port -> $detectedUrl (detección bloqueada)');
                    }
                  }
                } else if (!isServerStartupMessage && !isHttpRequestLog && line.contains(':') && RegExp(r'\d+').hasMatch(line)) {
                  print('⚠️ Línea ignorada: no es mensaje de inicio de servidor ni petición HTTP');
                }
              }
              
              // Actualizar progreso basado en palabras clave
              final lowerLine = line.toLowerCase();
              if (lowerLine.contains('uvicorn running on') || 
                  lowerLine.contains('application startup complete')) {
                // La URL ya fue establecida cuando se detectó, no es necesario establecerla de nuevo
                // Esto evita notificaciones innecesarias que podrían causar múltiples aperturas del navegador
                _debugService.setCompilationProgress(1.0, 'Servidor ejecutándose ✅');
                _debugService.setRunning(true);
                print('✅ Servidor listo con URL: ${detectedUrl ?? "pendiente"}');
        if (mounted) {
                  setState(() {
                    _isRunning = true; // Mantener en ejecución para servidores
                  });
                }
              } else if (lowerLine.contains('started server process')) {
                _debugService.setCompilationProgress(0.8, 'Iniciando servidor...');
              } else if (lowerLine.contains('waiting for application startup')) {
                _debugService.setCompilationProgress(0.9, 'Preparando aplicación...');
              } else if (lowerLine.contains('server') && (lowerLine.contains('running') || lowerLine.contains('started'))) {
                _debugService.setCompilationProgress(1.0, 'Servidor ejecutándose');
                _debugService.setRunning(true);
                if (mounted) {
                  setState(() {
                    _isRunning = true;
                  });
                }
              } else if (lowerLine.contains('listening') || lowerLine.contains('ready')) {
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
              _debugService.addOutput(line);
              _debugService.addDebugConsole(line);
              
              print('🔍 Analizando línea STDERR: "$line"');
              
              // IMPORTANTE: Uvicorn envía sus logs INFO a stderr!
              // Detectar URL SOLO UNA VEZ en mensajes específicos de inicio de servidor
              // También verificar si ya hay una URL establecida en el servicio
              if (!urlDetected && (_debugService.appUrl == null || _debugService.appUrl!.isEmpty)) {
                final lowerLine = line.toLowerCase();
                
                // Solo buscar URL si la línea contiene indicadores claros de inicio de servidor
                // Y NO contiene indicadores de peticiones HTTP
                final isServerStartupMessage = (lowerLine.contains('uvicorn running on') || 
                    lowerLine.contains('starting development server at') ||
                    lowerLine.contains('server running on') ||
                    lowerLine.contains('serving on') ||
                    lowerLine.contains('listening on'));
                
                final isHttpRequestLog = lowerLine.contains('get ') || 
                    lowerLine.contains('post ') || 
                    lowerLine.contains('put ') || 
                    lowerLine.contains('delete ') ||
                    lowerLine.contains('" 200 ') ||
                    lowerLine.contains('" 404 ') ||
                    lowerLine.contains('" 500 ');
                
                if (isServerStartupMessage && !isHttpRequestLog) {
                  print('✅ Línea STDERR contiene indicador de inicio de servidor (no es log de petición)');
                  
                  if (line.contains('0.0.0.0:')) {
                    final portMatch = RegExp(r'0\.0\.0\.0:(\d+)').firstMatch(line);
                    if (portMatch != null) {
                      final port = portMatch.group(1);
                      detectedUrl = 'http://localhost:$port';
                      _debugService.setAppUrl(detectedUrl);
                      urlDetected = true;
                      print('🌐 ✅✅✅ URL DETECTADA EN STDERR: 0.0.0.0:$port -> $detectedUrl (detección bloqueada)');
                    }
                  } else if (line.contains('localhost:')) {
                    final portMatch = RegExp(r'localhost:(\d+)').firstMatch(line);
                    if (portMatch != null) {
                      final port = portMatch.group(1);
                      detectedUrl = 'http://localhost:$port';
                      _debugService.setAppUrl(detectedUrl);
                      urlDetected = true;
                      print('🌐 ✅✅✅ URL detectada EN STDERR (localhost): $detectedUrl (detección bloqueada)');
                    }
                  } else if (line.contains('127.0.0.1:')) {
                    final portMatch = RegExp(r'127\.0\.0\.1:(\d+)').firstMatch(line);
                    if (portMatch != null) {
                      final port = portMatch.group(1);
                      detectedUrl = 'http://127.0.0.1:$port';
                      _debugService.setAppUrl(detectedUrl);
                      urlDetected = true;
                      print('🌐 ✅✅✅ URL detectada EN STDERR (127.0.0.1): $detectedUrl (detección bloqueada)');
                    }
                  }
                }
              }
              
              // Detectar errores críticos que impiden el inicio
              final lowerLine = line.toLowerCase();
              if (lowerLine.contains('error') || lowerLine.contains('failed') || 
                  lowerLine.contains('cannot') || lowerLine.contains('not found') ||
                  lowerLine.contains('command not found') || lowerLine.contains('no such file')) {
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
                  _debugService.setCompilationProgress(0.0, 'Error: Comando no encontrado');
                  
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
                        message: 'No se pudo ejecutar el comando:\n\n$line\n\nVerifica que el comando existe y está instalado.',
                        showViewErrorsButton: true,
                        onViewErrors: () {
                          _debugService.openPanel();
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
                print('⚠️ Timeout: El proceso no ha producido output después de 30 segundos');
                _debugService.addProblem('⚠️ Timeout: El proceso no ha producido output después de 30 segundos');
                _debugService.setCompilationProgress(0.0, 'Error: Timeout al iniciar');
                
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
                    message: 'El servidor no ha iniciado después de 30 segundos.\n\n'
                        'Posibles causas:\n'
                        '• El comando no existe o no está instalado\n'
                        '• Faltan dependencias\n'
                        '• Error en la configuración\n\n'
                        'Revisa el Debug Console para más detalles.',
                    showViewErrorsButton: true,
                    onViewErrors: () {
                      _debugService.openPanel();
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
                    message: 'El servidor terminó inesperadamente con código: $exitCode\n\nRevisa el Debug Console para más detalles.',
                    showViewErrorsButton: true,
                    onViewErrors: () {
                      _debugService.openPanel();
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
            _debugService.setCompilationProgress(1.0, exitCode == 0 ? 'Completado' : 'Error');
            
            if (exitCode != 0 && mounted) {
              showDialog(
                context: context,
                builder: (context) => ErrorConfirmationDialog(
                  title: 'Ejecución fallida',
                  message: 'El proceso terminó con código de error: $exitCode\n\nRevisa el Debug Console para más detalles.',
                  showViewErrorsButton: true,
                  onViewErrors: () {
                      _debugService.openPanel();
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
                message: 'No se pudo ejecutar el proyecto:\n\n$e\n\nAsegúrate de que las dependencias están instaladas:\n'
                    '${_getSuggestedCommand(projectType)}',
                showViewErrorsButton: true,
                onViewErrors: () {
                  _debugService.openPanel();
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
        print('❌ ChatScreen._handleDebug: EL DIRECTORIO NO EXISTE: $projectPath');
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
      final projectType = await ProjectTypeDetector.detectProjectType(projectPath);
      
      if (projectType == ProjectType.unknown) {
        print('❌ ChatScreen._handleDebug: TIPO DE PROYECTO DESCONOCIDO: $projectPath');
        
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
                  const Icon(Icons.error_outline, color: Colors.orange, size: 24),
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
                      ...missingFiles.map((file) => Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.warning, color: Colors.orange, size: 16),
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
                      )),
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
                              const Icon(Icons.lightbulb_outline, color: Colors.blue, size: 16),
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
                            style: TextStyle(color: CursorTheme.textSecondary, fontSize: 12),
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
                  child: const Text('Entendido', style: TextStyle(color: CursorTheme.primary)),
                ),
              ],
            ),
          );
        }
        return;
      }
      
      final projectTypeName = ProjectTypeDetector.getProjectTypeName(projectType);
      final projectTypeIcon = ProjectTypeDetector.getProjectTypeIcon(projectType);
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
      _debugService.setCompilationProgress(0.05, 'Iniciando $projectTypeName (DEBUG)...');
      // Abrir Debug Console automáticamente al ejecutar
      _debugService.openPanel();
    _debugService.clearAll();
      
      // Obtener nombre del proyecto
      final projectName = projectPath.split('/').last;
      print('✅ ChatScreen._handleDebug: Proyecto válido encontrado');
      print('   Nombre del proyecto: $projectName');
      print('   Tipo: $projectTypeIcon $projectTypeName');
      print('   Ruta del proyecto: $projectPath');
      print('   Modo: DEBUG');

      // Detectar URL para proyectos web
      String? detectedUrl;

      // Analizar progreso
      String currentStatus = 'Iniciando $projectTypeName (DEBUG)...';
      
      // Para Flutter, usar el sistema existente con dispositivos
      if (projectType == ProjectType.flutter) {
        // Sincronizar plataforma antes de ejecutar
        _selectedPlatform = _platformService.selectedPlatform;
        print('🚀 Ejecutando Flutter en plataforma (DEBUG): $_selectedPlatform');
        print('🔧 PlatformService.selectedPlatform: ${_platformService.selectedPlatform}');
        
        // Asegurar que la plataforma seleccionada se use correctamente
        // Priorizar _selectedPlatform, luego PlatformService, finalmente 'macos' como fallback
        final platformToUse = _selectedPlatform.isNotEmpty 
            ? _selectedPlatform 
            : (_platformService.selectedPlatform.isNotEmpty 
                ? _platformService.selectedPlatform 
                : 'macos');
        print('✅ Usando plataforma (DEBUG): $platformToUse');
        print('   _selectedPlatform: $_selectedPlatform');
        print('   _platformService.selectedPlatform: ${_platformService.selectedPlatform}');
        
        final result = await AdvancedDebuggingService.runFlutterApp(
          projectPath: projectPath,
          platform: platformToUse,
          mode: 'debug',
          useWebServer: false, // Para la plataforma web normal, usar chrome
          onOutput: (line) {
            _debugService.addOutput(line);
            _debugService.addDebugConsole(line);
            _maybeCaptureVmServiceUri(line);
            
            print('📥 Flutter output (DEBUG): $line');
            
            // Detectar errores
            final lowerLine = line.toLowerCase();
            if (RegExp(r'\.dart:\d+:\d+:\s*(error|warning):').hasMatch(line) ||
                (lowerLine.contains('error:') && !lowerLine.contains('no error')) ||
                (lowerLine.contains('failed') && !lowerLine.contains('no devices found')) ||
                lowerLine.contains('undefined name') ||
                lowerLine.contains('undefined class') ||
                lowerLine.contains('undefined method') ||
                lowerLine.contains('undefined getter') ||
                lowerLine.contains('syntax error') ||
                (lowerLine.contains('cannot') && (lowerLine.contains('find') || lowerLine.contains('resolve')))) {
              _debugService.addProblem(line);
              print('🔴 Error detectado: $line');
            }
            
            // Analizar progreso
            double progress = _debugService.compilationProgress;
            String status = currentStatus;
            
            if (line.contains('Running Gradle task') || line.contains('Running pod install')) {
              status = 'Configurando dependencias...';
              progress = 0.15;
            } else if (line.contains('Resolving dependencies') || line.contains('Downloading')) {
              status = 'Descargando dependencias...';
              progress = 0.25;
            } else if (line.contains('Building') || line.contains('Compiling') || line.contains('Assembling')) {
              status = 'Compilando código...';
              progress = 0.45;
            } else if (line.contains('Running') && line.contains('flutter')) {
              status = 'Ejecutando aplicación...';
              progress = 0.75;
            } else if (line.contains('Launching') || line.contains('Starting')) {
              status = 'Iniciando aplicación...';
              progress = 0.85;
            } else if (line.contains('Flutter run key commands') || line.contains('An Observatory debugger')) {
              status = 'Aplicación ejecutándose (DEBUG)';
              progress = 1.0;
            } else if (line.contains('Syncing files') || line.contains('Waiting for')) {
              status = 'Sincronizando archivos...';
              progress = 0.35;
            } else if (line.contains('%')) {
              final percentMatch = RegExp(r'(\d+)%').firstMatch(line);
              if (percentMatch != null) {
                final percent = int.parse(percentMatch.group(1)!);
                progress = percent / 100.0;
                status = 'Compilando... $percent%';
              }
            }
            
            if (progress > _debugService.compilationProgress) {
              _debugService.setCompilationProgress(progress, status);
              currentStatus = status;
            }
            
            // Detectar URL para web - patrones más amplios para Flutter web
            if (platformToUse == 'web') {
              print('🔍 Buscando URL en línea para Flutter web (DEBUG): "$line"');
              
              // Patrón 1: "The Flutter DevTools debugger and profiler on [platform] is available at: http://localhost:XXXXX"
              RegExpMatch? urlMatch = RegExp(r'available at:\s*(http://[^\s]+)', caseSensitive: false).firstMatch(line);
              if (urlMatch != null) {
                detectedUrl = urlMatch.group(1)!.trim();
                _debugService.setAppUrl(detectedUrl);
                print('🌐 ✅✅✅ URL detectada (available at): $detectedUrl');
                if (mounted) {
    setState(() {
                    _isRunning = true;
                    _isDebugging = true;
                  });
                }
                _debugService.setRunning(true);
                _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (DEBUG)');
              } else {
                // Patrón 2: "http://localhost:XXXXX" o "http://127.0.0.1:XXXXX"
                urlMatch = RegExp(r'http://(localhost|127\.0\.0\.1):(\d+)').firstMatch(line);
                if (urlMatch != null) {
                  final host = urlMatch.group(1)!;
                  final port = urlMatch.group(2)!;
                  detectedUrl = 'http://$host:$port';
                  _debugService.setAppUrl(detectedUrl);
                  print('🌐 ✅✅✅ URL detectada (http://$host:$port): $detectedUrl');
                  if (mounted) {
                    setState(() {
                      _isRunning = true;
                      _isDebugging = true;
                    });
                  }
                  _debugService.setRunning(true);
                  _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (DEBUG)');
                } else {
                  // Patrón 3: Cualquier URL http:// en la línea
                  urlMatch = RegExp(r'(http://[^\s:]+:\d+)').firstMatch(line);
                  if (urlMatch != null) {
                    detectedUrl = urlMatch.group(1)!.trim();
                    _debugService.setAppUrl(detectedUrl);
                    print('🌐 ✅✅✅ URL detectada (genérico): $detectedUrl');
                    if (mounted) {
                      setState(() {
                        _isRunning = true;
                        _isDebugging = true;
                      });
                    }
                    _debugService.setRunning(true);
                    _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (DEBUG)');
                  }
                }
              }
              
              // También detectar cuando Chrome se abre (indica que la app está lista)
              if (line.contains('Chrome') && (line.contains('Launching') || line.contains('Starting'))) {
                // Si no se detectó URL aún, usar localhost:8080 como fallback (puerto común de Flutter web)
                if (detectedUrl == null) {
                  detectedUrl = 'http://localhost:8080';
                  _debugService.setAppUrl(detectedUrl);
                  print('🌐 ✅ URL establecida por defecto (Chrome detectado): $detectedUrl');
                  if (mounted) {
                    setState(() {
                      _isRunning = true;
                      _isDebugging = true;
                    });
                  }
                  _debugService.setRunning(true);
                  _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (DEBUG)');
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

        // Variables para detectar si se ejecutó el fallback web (DEBUG)
        bool fallbackWebExecutedDebug = false;
        final isAndroidOrIOSDebug = platformToUse.toLowerCase() == 'android' || platformToUse.toLowerCase() == 'ios';
        
        // Para Flutter web, mantener _isRunning en true si la compilación fue exitosa
        // Para otras plataformas (Android/iOS/macOS), la app se ejecuta en el dispositivo/emulador
        if (platformToUse == 'web' && result.success) {
          print('✅ Flutter web ejecutándose correctamente (DEBUG), manteniendo _isRunning = true');
          if (mounted) {
            setState(() {
              _isRunning = true;
              _isDebugging = true;
            });
          }
          _debugService.setRunning(true);
          _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (DEBUG)');
        } else if (result.success) {
          // Para Android/iOS/macOS, la app se ejecuta en el dispositivo/emulador
          // NO establecer URL (solo para web)
          print('✅ Flutter ${platformToUse} ejecutándose en dispositivo/emulador (DEBUG)');
          if (mounted) {
            setState(() {
              _isRunning = true; // Mantener en true para mostrar que está ejecutándose
              _isDebugging = true;
            });
          }
          _debugService.setRunning(true);
          _debugService.setAppUrl(null); // Asegurar que no hay URL para apps nativas
          _debugService.setCompilationProgress(1.0, 'Aplicación ejecutándose en ${platformToUse.toUpperCase()} (DEBUG)');
        } else {
          // Compilación fallida - verificar si es por falta de dispositivo Android/iOS
          final errorMessage = result.errors.isNotEmpty 
              ? result.errors.join('\n')
              : 'La compilación falló. Revisa el Debug Console para más detalles.';
          
          final isNoDeviceError = errorMessage.contains('No se encontró dispositivo disponible') ||
                                 errorMessage.contains('No se encontró dispositivo para la plataforma');
          
          // Si es Android/iOS y no hay dispositivo, ejecutar automáticamente la versión web como fallback
          if (isAndroidOrIOSDebug && isNoDeviceError) {
            print('📱 No se encontró dispositivo para $platformToUse (DEBUG). Ejecutando versión web como fallback...');
            _debugService.addDebugConsole('📱 No se encontró dispositivo para $platformToUse (DEBUG)');
            _debugService.addDebugConsole('🌐 Ejecutando versión web como fallback (DEBUG)...');
            _debugService.setCompilationProgress(0.1, 'Ejecutando versión web como fallback (DEBUG)...');
            
            // Ejecutar la versión web
            String? webDetectedUrl;
            bool webUrlDetected = false;
            
            final webResult = await AdvancedDebuggingService.runFlutterApp(
              projectPath: projectPath,
              platform: 'web',
              mode: 'debug',
              useWebServer: true, // Usar web-server para NO abrir navegador externo (fallback Android/iOS)
              webRenderer: 'html', // Necesario para inspector (DOM) en WebView
              onOutput: (line) {
                _debugService.addOutput(line);
                _debugService.addDebugConsole(line);
                _maybeCaptureVmServiceUri(line);
                
                print('📥 Flutter web (fallback DEBUG) output: $line');
                
                // Detectar URL para web
                if (!webUrlDetected) {
                  // Patrón 1: "available at: http://..."
                  RegExpMatch? urlMatch = RegExp(r'available at:\s*(http://[^\s]+)', caseSensitive: false).firstMatch(line);
                  if (urlMatch != null) {
                    webDetectedUrl = urlMatch.group(1)!.trim();
                    _debugService.setAppUrl(webDetectedUrl);
                    webUrlDetected = true;
                    print('🌐 ✅✅✅ URL detectada (fallback web DEBUG): $webDetectedUrl');
                    if (mounted) {
                      setState(() {
                        _isRunning = true;
                        _isDebugging = true;
                      });
                    }
                    _debugService.setRunning(true);
                    _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (fallback para $platformToUse, DEBUG)');
                  } else {
                    // Patrón 2: "http://localhost:XXXXX" o "http://127.0.0.1:XXXXX"
                    urlMatch = RegExp(r'http://(localhost|127\.0\.0\.1):(\d+)').firstMatch(line);
                    if (urlMatch != null) {
                      final host = urlMatch.group(1)!;
                      final port = urlMatch.group(2)!;
                      webDetectedUrl = 'http://$host:$port';
                      _debugService.setAppUrl(webDetectedUrl);
                      webUrlDetected = true;
                      print('🌐 ✅✅✅ URL detectada (fallback web DEBUG): $webDetectedUrl');
                      if (mounted) {
                        setState(() {
                          _isRunning = true;
                          _isDebugging = true;
                        });
                      }
                      _debugService.setRunning(true);
                      _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (fallback para $platformToUse, DEBUG)');
                    } else {
                      // Patrón 3: Cualquier URL http:// en la línea
                      urlMatch = RegExp(r'(http://[^\s:]+:\d+)').firstMatch(line);
                      if (urlMatch != null) {
                        webDetectedUrl = urlMatch.group(1)!.trim();
                        _debugService.setAppUrl(webDetectedUrl);
                        webUrlDetected = true;
                        print('🌐 ✅✅✅ URL detectada (fallback web DEBUG): $webDetectedUrl');
                        if (mounted) {
                          setState(() {
                            _isRunning = true;
                            _isDebugging = true;
                          });
                        }
                        _debugService.setRunning(true);
                        _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (fallback para $platformToUse, DEBUG)');
                      }
                    }
                  }
                  
                  // Fallback si se detecta Chrome pero no URL específica
                  if (webDetectedUrl == null && line.contains('Chrome') && (line.contains('Launching') || line.contains('Starting'))) {
                    webDetectedUrl = 'http://localhost:8080';
                    _debugService.setAppUrl(webDetectedUrl);
                    webUrlDetected = true;
                    print('🌐 ✅ URL establecida por defecto (fallback web DEBUG): $webDetectedUrl');
                    if (mounted) {
                      setState(() {
                        _isRunning = true;
                        _isDebugging = true;
                      });
                    }
                    _debugService.setRunning(true);
                    _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (fallback para $platformToUse, DEBUG)');
                  }
                }
              },
              onError: (error) {
                _debugService.addProblem(error.toString());
                _debugService.setCompilationProgress(0.0, 'Error en compilación web (fallback DEBUG)');
              },
            );
            
            if (webResult.success && webDetectedUrl != null) {
              print('✅ Versión web ejecutándose correctamente como fallback para $platformToUse (DEBUG)');
              fallbackWebExecutedDebug = true;
              if (mounted) {
                setState(() {
                  _isRunning = true;
                  _isDebugging = true;
                });
              }
              _debugService.setRunning(true);
              _debugService.setAppUrl(webDetectedUrl);
              _debugService.setCompilationProgress(1.0, 'Aplicación web ejecutándose (fallback para $platformToUse, DEBUG)');
            } else {
              // Si el fallback web también falla, mostrar error
              setState(() {
                _isRunning = false;
                _isDebugging = false;
              });
              _debugService.setRunning(false);
              _debugService.setAppUrl(null);
              _debugService.setCompilationProgress(1.0, errorMessage);
            }
          } else {
            // Error normal (no es por falta de dispositivo)
            setState(() {
              _isRunning = false;
              _isDebugging = false;
            });
            _debugService.setRunning(false);
            _debugService.setAppUrl(null); // Limpiar URL en caso de error
            _debugService.setCompilationProgress(1.0, errorMessage); // Establecer mensaje de error en compilationStatus
          }
        }
        
        // Solo mostrar diálogo de error si no se ejecutó el fallback web exitosamente
        if (!result.success && mounted && !fallbackWebExecutedDebug) {
          final errorMessage = result.errors.isNotEmpty 
              ? result.errors.join('\n')
              : 'La compilación falló. Revisa el Debug Console para más detalles.';
    showDialog(
      context: context,
            builder: (context) => ErrorConfirmationDialog(
              title: 'Compilación fallida',
              message: errorMessage,
              showViewErrorsButton: true,
              onViewErrors: () {
                _debugService.openPanel();
              },
            ),
          );
        }
      } else {
        // EJECUCIÓN UNIVERSAL para otros lenguajes (modo debug)
        print('🎯 Ejecutando comando personalizado (DEBUG): ${runCommand.command} ${runCommand.args.join(' ')}');
        
        // Detectar si es un proceso de servidor de larga duración
        final isLongRunningServer = projectType == ProjectType.fastapi ||
            projectType == ProjectType.django ||
            projectType == ProjectType.flask ||
            projectType == ProjectType.nodejs ||
            projectType == ProjectType.react ||
            projectType == ProjectType.nextjs ||
            projectType == ProjectType.vue ||
            projectType == ProjectType.vite ||
            runCommand.command.contains('uvicorn') ||
            runCommand.command.contains('gunicorn') ||
            runCommand.command.contains('runserver') ||
            runCommand.command.contains('npm') && (runCommand.args.contains('start') || runCommand.args.contains('dev')) ||
            runCommand.command.contains('yarn') && (runCommand.args.contains('start') || runCommand.args.contains('dev'));
        
        try {
          final process = await Process.start(
            runCommand.command,
            runCommand.args,
            workingDirectory: runCommand.workingDirectory,
            runInShell: true,
            environment: runCommand.environment,
          );
          
          // Guardar referencia al proceso para poder detenerlo
          _runningProcess = process;
          
          _debugService.addOutput('$projectTypeIcon Ejecutando (DEBUG): ${runCommand.description}');
          _debugService.addOutput('📁 Directorio: ${runCommand.workingDirectory}');
          _debugService.addOutput('🚀 Comando: ${runCommand.command} ${runCommand.args.join(' ')}');
          _debugService.addOutput('');
          _debugService.setCompilationProgress(0.2, 'Ejecutando (DEBUG)...');
          
          // Variables para rastrear el estado del proceso
          bool hasReceivedOutputDebug = false;
          bool urlDetectedDebug = false; // Flag para detectar URL solo una vez
          
          // Verificar si ya hay una URL establecida (por si acaso)
          if (_debugService.appUrl != null && _debugService.appUrl!.isNotEmpty) {
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
            
            print('📥 STDOUT recibido (${data.length} chars): "${data.substring(0, data.length > 100 ? 100 : data.length)}..."');
            
            for (var line in data.split('\n')) {
              if (line.trim().isEmpty) continue;
              _debugService.addOutput(line);
              _debugService.addDebugConsole(line);
              
              print('🔍 Analizando línea STDOUT: "$line"');
              
              // Detectar URLs en el output SOLO UNA VEZ
              // Método simple y directo: buscar 0.0.0.0:PORT y convertir a localhost
              // También verificar si ya hay una URL establecida
              if (!urlDetectedDebug && (_debugService.appUrl == null || _debugService.appUrl!.isEmpty)) {
                if (line.contains('0.0.0.0:')) {
                print('✅ Línea contiene "0.0.0.0:" - intentando extraer puerto...');
                final portMatch = RegExp(r'0\.0\.0\.0:(\d+)').firstMatch(line);
                  if (portMatch != null) {
                    final port = portMatch.group(1);
                    detectedUrl = 'http://localhost:$port';
                    _debugService.setAppUrl(detectedUrl);
                    urlDetectedDebug = true;
                    print('🌐 ✅✅✅ URL DETECTADA (DEBUG STDOUT): 0.0.0.0:$port -> $detectedUrl (detección bloqueada)');
                  } else {
                    print('❌ No se pudo extraer puerto de: "$line"');
                  }
                } else if (line.contains('localhost:')) {
                  print('✅ Línea contiene "localhost:" - intentando extraer puerto...');
                  final portMatch = RegExp(r'localhost:(\d+)').firstMatch(line);
                  if (portMatch != null) {
                    final port = portMatch.group(1);
                    detectedUrl = 'http://localhost:$port';
                    _debugService.setAppUrl(detectedUrl);
                    urlDetectedDebug = true;
                    print('🌐 ✅✅✅ URL detectada (DEBUG STDOUT localhost): $detectedUrl (detección bloqueada)');
                  }
                } else if (line.contains('127.0.0.1:')) {
                  print('✅ Línea contiene "127.0.0.1:" - intentando extraer puerto...');
                  final portMatch = RegExp(r'127\.0\.0\.1:(\d+)').firstMatch(line);
                  if (portMatch != null) {
                    final port = portMatch.group(1);
                    detectedUrl = 'http://127.0.0.1:$port';
                    _debugService.setAppUrl(detectedUrl);
                    urlDetectedDebug = true;
                    print('🌐 ✅✅✅ URL detectada (DEBUG STDOUT 127.0.0.1): $detectedUrl (detección bloqueada)');
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
                  print('🌐 ✅ URL confirmada al detectar servidor listo (DEBUG): $detectedUrl');
                }
                _debugService.setCompilationProgress(1.0, 'Servidor ejecutándose (DEBUG) ✅');
                _debugService.setRunning(true);
                print('✅ Servidor DEBUG listo con URL: ${detectedUrl ?? "pendiente"}');
                if (mounted) {
                  setState(() {
                    _isRunning = true;
                    _isDebugging = true;
                  });
                }
              } else if (lowerLine.contains('started server process')) {
                _debugService.setCompilationProgress(0.8, 'Iniciando servidor (DEBUG)...');
              } else if (lowerLine.contains('waiting for application startup')) {
                _debugService.setCompilationProgress(0.9, 'Preparando aplicación (DEBUG)...');
              } else if (lowerLine.contains('server') && (lowerLine.contains('running') || lowerLine.contains('started'))) {
                _debugService.setCompilationProgress(1.0, 'Servidor ejecutándose (DEBUG)');
                _debugService.setRunning(true);
                if (mounted) {
                  setState(() {
                    _isRunning = true;
                    _isDebugging = true;
                  });
                }
              } else if (lowerLine.contains('listening') || lowerLine.contains('ready')) {
                _debugService.setCompilationProgress(0.9, 'Servidor listo (DEBUG)');
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
            
            print('📥 STDERR recibido (${data.length} chars): "${data.substring(0, data.length > 100 ? 100 : data.length)}..."');
            
            for (var line in data.split('\n')) {
              if (line.trim().isEmpty) continue;
              _debugService.addOutput(line);
              _debugService.addDebugConsole(line);
              
              print('🔍 Analizando línea STDERR: "$line"');
              
              // IMPORTANTE: Uvicorn envía sus logs INFO a stderr, no stdout!
              // Detectar URLs en el output de stderr también SOLO UNA VEZ
              // También verificar si ya hay una URL establecida
              if (!urlDetectedDebug && (_debugService.appUrl == null || _debugService.appUrl!.isEmpty)) {
                if (line.contains('0.0.0.0:')) {
                  print('✅ Línea STDERR contiene "0.0.0.0:" - intentando extraer puerto...');
                  final portMatch = RegExp(r'0\.0\.0\.0:(\d+)').firstMatch(line);
                  if (portMatch != null) {
                    final port = portMatch.group(1);
                    detectedUrl = 'http://localhost:$port';
                    _debugService.setAppUrl(detectedUrl);
                    urlDetectedDebug = true;
                    print('🌐 ✅✅✅ URL DETECTADA EN STDERR (DEBUG): 0.0.0.0:$port -> $detectedUrl (detección bloqueada)');
                  } else {
                    print('❌ No se pudo extraer puerto de STDERR: "$line"');
                  }
                } else if (line.contains('localhost:')) {
                  print('✅ Línea STDERR contiene "localhost:" - intentando extraer puerto...');
                  final portMatch = RegExp(r'localhost:(\d+)').firstMatch(line);
                  if (portMatch != null) {
                    final port = portMatch.group(1);
                    detectedUrl = 'http://localhost:$port';
                    _debugService.setAppUrl(detectedUrl);
                    urlDetectedDebug = true;
                    print('🌐 ✅✅✅ URL detectada EN STDERR (DEBUG localhost): $detectedUrl (detección bloqueada)');
                  }
                } else if (line.contains('127.0.0.1:')) {
                  print('✅ Línea STDERR contiene "127.0.0.1:" - intentando extraer puerto...');
                  final portMatch = RegExp(r'127\.0\.0\.1:(\d+)').firstMatch(line);
                  if (portMatch != null) {
                    final port = portMatch.group(1);
                    detectedUrl = 'http://127.0.0.1:$port';
                    _debugService.setAppUrl(detectedUrl);
                    urlDetectedDebug = true;
                    print('🌐 ✅✅✅ URL detectada EN STDERR (DEBUG 127.0.0.1): $detectedUrl (detección bloqueada)');
                  }
                }
              }
              
              // Detectar errores críticos que impiden el inicio
              final lowerLine = line.toLowerCase();
              if (lowerLine.contains('error') || lowerLine.contains('failed') || 
                  lowerLine.contains('cannot') || lowerLine.contains('not found') ||
                  lowerLine.contains('command not found') || lowerLine.contains('no such file')) {
                _debugService.addProblem(line);
                
                // Si es un error crítico, detener el proceso
                if (lowerLine.contains('command not found') || 
                    lowerLine.contains('no such file') ||
                    lowerLine.contains('cannot find')) {
                  print('❌ Error crítico detectado (DEBUG), deteniendo proceso...');
                  if (mounted) {
                    setState(() {
                      _isRunning = false;
                      _isDebugging = false;
                    });
                  }
                  _debugService.setRunning(false);
                  _debugService.setCompilationProgress(0.0, 'Error: Comando no encontrado');
                  
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
                        message: 'No se pudo ejecutar el comando:\n\n$line\n\nVerifica que el comando existe y está instalado.',
                        showViewErrorsButton: true,
                        onViewErrors: () {
                          _debugService.openPanel();
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
                print('⚠️ Timeout (DEBUG): El proceso no ha producido output después de 30 segundos');
                _debugService.addProblem('⚠️ Timeout: El proceso no ha producido output después de 30 segundos');
                _debugService.setCompilationProgress(0.0, 'Error: Timeout al iniciar');
                
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
                    message: 'El servidor no ha iniciado después de 30 segundos.\n\n'
                        'Posibles causas:\n'
                        '• El comando no existe o no está instalado\n'
                        '• Faltan dependencias\n'
                        '• Error en la configuración\n\n'
                        'Revisa el Debug Console para más detalles.',
                    showViewErrorsButton: true,
                    onViewErrors: () {
                      _debugService.openPanel();
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
                    message: 'El servidor terminó inesperadamente con código: $exitCode\n\nRevisa el Debug Console para más detalles.',
                    showViewErrorsButton: true,
                    onViewErrors: () {
                      _debugService.openPanel();
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
            _debugService.setCompilationProgress(1.0, exitCode == 0 ? 'Completado (DEBUG)' : 'Error');
            
            if (exitCode != 0 && mounted) {
              showDialog(
                context: context,
                builder: (context) => ErrorConfirmationDialog(
                  title: 'Ejecución fallida',
                  message: 'El proceso terminó con código de error: $exitCode\n\nRevisa el Debug Console para más detalles.',
                  showViewErrorsButton: true,
                  onViewErrors: () {
                    _debugService.openPanel();
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
                message: 'No se pudo ejecutar el proyecto:\n\n$e\n\nAsegúrate de que las dependencias están instaladas:\n'
                    '${_getSuggestedCommand(projectType)}',
                showViewErrorsButton: true,
                onViewErrors: () {
                  _debugService.openPanel();
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

  void _handleStop() {
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
        print('⚠️ Error al detener proceso: $e');
      }
    }
    
    setState(() {
      _isRunning = false;
      _isDebugging = false;
    });
    _debugService.setRunning(false);
    _debugService.setAppUrl(null); // Limpiar URL al detener
    _debugService.setVmServiceUri(null); // Limpiar VM Service al detener
    _debugService.setCompilationProgress(0.0, '');
    _debugService.addDebugConsole('🛑 Ejecución detenida por el usuario');
  }

  Future<void> _handleRestart() async {
    _handleStop();
    await Future.delayed(const Duration(milliseconds: 500));
    if (_isDebugging) {
      await _handleDebug();
    } else {
      await _handleRun();
    }
  }

  // Métodos públicos para acceso desde MultiChatScreen
  void handleRun() => _handleRun();
  void handleDebug() => _handleDebug();
  void handleStop() => _handleStop();
  void handleRestart() => _handleRestart();
  
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
        padding: const EdgeInsets.all(32.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icono de Lopez Code (robot azul profesional)
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF007ACC),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF007ACC).withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: CustomPaint(
                  painter: RobotIconPainter(),
                ),
              ),
              const SizedBox(height: 24),
              // Título
              const Text(
                'Lopez Code',
                style: TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tu asistente de IA para desarrollo de software',
                style: TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 14,
                ),
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
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: CursorTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CursorTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: CursorTheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Puedo ayudarte con:',
                          style: const TextStyle(
                            color: CursorTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
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
              style: TextStyle(
                color: CursorTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatArea() {
    // NO llamar _scrollToBottom aquí - causa problemas de layout
    // Se llamará después de agregar mensajes en _sendMessage
    
    return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), // Más padding horizontal como Cursor
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
                            borderRadius: BorderRadius.circular(4.5), // Esquinas redondeadas como iconos del dock
                            border: Border.all(
                              color: const Color(0xFF007ACC).withOpacity(0.3), // Borde sutil
                              width: 0.5,
                            ),
                          ),
                          child: CustomPaint(
                            painter: RobotIconPainter(),
                          ),
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
                                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF007ACC)),
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          borderRadius: BorderRadius.circular(4.5), // Esquinas redondeadas como iconos del dock
                          border: Border.all(
                            color: const Color(0xFF007ACC).withOpacity(0.3), // Borde sutil
                            width: 0.5,
                          ),
                        ),
                        child: CustomPaint(
                          painter: RobotIconPainter(),
                        ),
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
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF007ACC)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _loadingStatus.isNotEmpty ? _loadingStatus : 'Pensando...',
                            style: const TextStyle(
                              color: CursorTheme.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }
        final msg = _messages[index];
        return MessageBubble(
          message: msg,
          onAcceptActions: msg.pendingActions != null && msg.pendingActions!.isNotEmpty
              ? (actions) => _handleAcceptActions(actions, index)
              : null,
          onRejectActions: msg.pendingActions != null && msg.pendingActions!.isNotEmpty
              ? () => _handleRejectActions(index)
              : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // No usar Scaffold con AppBar cuando está dentro de MultiChatScreen
    // para evitar overflow - MultiChatScreen ya tiene su propia barra de pestañas
    return Container(
      color: CursorTheme.background,
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min, // ✅ FIX: Evitar overflow
            children: [
              Expanded(
                child: _messages.isEmpty ? _buildEmptyChatArea() : _buildChatArea(),
              ),
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
                print('⚠️ OpenAI Service no está inicializado. Cargando...');
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
    
    _messageController.dispose();
    _scrollController.dispose();
    _platformService.removeListener(_onPlatformChanged);
    _openAIService?.dispose();
    _saveConversation();
    super.dispose();
  }
}
