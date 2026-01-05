import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/message.dart';
import '../services/openai_service.dart';
import '../services/settings_service.dart';
import '../services/project_service.dart';
import '../services/chat_storage_service.dart';
import '../services/project_context_service.dart';
import '../services/file_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/cursor_chat_input.dart';
import '../widgets/cursor_theme.dart';
import '../widgets/project_explorer.dart';
import '../widgets/code_editor_panel.dart';
import '../widgets/screen_preview.dart';
import '../widgets/run_debug_panel.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  final String? chatId;
  final String? projectPath;
  
  const ChatScreen({super.key, this.chatId, this.projectPath});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _messages = [];
  bool _isLoading = false;
  String _loadingStatus = '';
  String? _currentFileOperation; // 'creando', 'editando', 'leyendo'
  String? _currentFilePath;
  OpenAIService? _openAIService;
  List<String> _selectedImages = [];
  String? _selectedFilePath;
  late String _currentSessionId;
  bool _showProjectExplorer = true;
  bool _showRunDebugPanel = false;
  double _explorerWidth = 300.0;
  String? _lastProjectPath;
  int _explorerRefreshCounter = 0; // Para forzar refresh del explorador

  @override
  void initState() {
    super.initState();
    _currentSessionId = widget.chatId ?? DateTime.now().millisecondsSinceEpoch.toString();
    _initialize();
  }

  Future<void> _initialize() async {
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
      if (projectPath == null) return;
      
      final messagesJson = await ChatStorageService.loadAgentMessages(_currentSessionId);
      if (messagesJson != null && messagesJson.isNotEmpty) {
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
    
    if ((!hasText && !hasImages) || _isLoading) return;
    
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

    final userMessage = _messageController.text.trim().isEmpty 
        ? (hasImages ? 'Analiza esta imagen y describe lo que ves' : '')
        : _messageController.text.trim();
    _messageController.clear();

    final userMsg = Message(
      role: 'user',
      content: userMessage,
      timestamp: DateTime.now(),
      imageUrls: imagesToSend.isNotEmpty ? imagesToSend : null,
      filePath: filePathToSend,
    );

    setState(() {
      _messages.add(userMsg);
      _isLoading = true;
      _selectedImages.clear();
      _selectedFilePath = null;
    });

    _scrollToBottom();

    try {
      final systemPrompt = await SettingsService.getSystemPrompt();
      
      setState(() {
        _loadingStatus = 'Analizando el contexto...';
      });
      
      String projectContext = '';
      String projectSummary = '';
      try {
        projectContext = await ProjectContextService.getProjectContext();
        projectSummary = await ProjectContextService.getProjectSummary();
        
        if (projectContext.length > 50000) {
          projectContext = projectContext.substring(0, 50000) + '\n...[Contexto truncado]';
        }
      } catch (e) {
        print('⚠️ Error al obtener contexto: $e');
      }
      
      setState(() {
        _loadingStatus = 'Pensando en la solución...';
      });

      String? fileContent;
      if (_selectedFilePath != null) {
        try {
          fileContent = await FileService.readFile(_selectedFilePath!);
        } catch (e) {
          print('⚠️ Error al leer archivo: $e');
        }
      }

        final conversationHistory = _messages.map((msg) {
          return {
            'role': msg.role,
            'content': msg.content,
          };
        }).toList();

        String enhancedMessage = userMessage;
        if (projectContext.isNotEmpty) {
          enhancedMessage = '''
$userMessage

--- CONTEXTO DEL PROYECTO ---
$projectSummary

ESTRUCTURA Y ARCHIVOS:
$projectContext

⚠️ ACTÚA DIRECTAMENTE - Proporciona código completo cuando se solicite.
''';
        }

      final projectPath = widget.projectPath ?? await ProjectService.getProjectPath();
      
      final response = await _openAIService!.sendMessage(
          message: enhancedMessage,
        imagePaths: imagesToSend.isNotEmpty ? imagesToSend : null,
          conversationHistory: conversationHistory,
          fileContent: fileContent,
          systemPrompt: systemPrompt.isNotEmpty ? systemPrompt : null,
        projectPath: projectPath, // CRÍTICO: Necesario para Function Calling
        onFileOperation: (operation, filePath) {
          // Actualizar estado cuando se ejecuta una operación de archivo
          if (mounted) {
      setState(() {
              _currentFileOperation = operation;
              _currentFilePath = filePath;
      });
          }
        },
      );

      final assistantMsg = Message(
        role: 'assistant',
        content: response,
        timestamp: DateTime.now(),
      );

      setState(() {
        _messages.add(assistantMsg);
        _isLoading = false;
        _loadingStatus = '';
        _currentFileOperation = null;
        _currentFilePath = null;
        _explorerRefreshCounter++; // Forzar refresh del explorador después de crear/editar archivos
      });

      await _saveConversation();
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _loadingStatus = '';
        _currentFileOperation = null;
        _currentFilePath = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
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

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    ).then((_) async {
      await _loadOpenAIService();
    });
  }

  void _onFileSelected(String path) {
    // Acción cuando se selecciona un archivo
  }

  void _onFileDoubleClick(String path) {
    // Acción cuando se hace doble clic en un archivo - abrir código
    _openFileEditor(path);
  }

  void _onFileViewCode(String path) {
    _openFileEditor(path);
  }

  void _onFileViewScreen(String path) {
    // Mostrar vista previa de pantalla (ventana independiente, no bloqueante)
    if (!path.endsWith('.dart')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La vista previa solo está disponible para archivos .dart'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    showDialog(
      context: context,
      barrierDismissible: true, // Permitir cerrar haciendo clic fuera
      barrierColor: Colors.black.withOpacity(0.5), // Fondo semitransparente
      builder: (context) => ScreenPreview(filePath: path),
    );
  }

  void _onFileCopy(String path) {
    Clipboard.setData(ClipboardData(text: path));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ruta copiada al portapapeles'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _runForPlatform(String platform) {
    // Mostrar panel de consola
    setState(() {
      _showRunDebugPanel = true;
    });
    // El panel manejará la ejecución cuando el usuario presione "Ejecutar"
  }

  Future<void> _onFileDelete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        setState(() {
          _explorerRefreshCounter++; // Refrescar explorador
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Archivo eliminado: ${path.split('/').last}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar archivo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openFileEditor(String path) async {
    try {
      final content = await FileService.readFile(path);
      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.8,
            decoration: BoxDecoration(
              color: CursorTheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CursorTheme.explorerBackground,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          path.split('/').last,
                          style: const TextStyle(
                            color: CursorTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: CursorTheme.textSecondary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Editor
                Expanded(
                  child: CodeEditorPanel(
                    filePath: path,
                    initialContent: content,
                    onSave: (savedPath) {
                      setState(() {
                        _explorerRefreshCounter++; // Refrescar explorador
                      });
                      Navigator.of(context).pop();
                    },
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir archivo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildEmptyChatArea() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: CursorTheme.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Comienza una conversación',
              style: TextStyle(color: CursorTheme.textPrimary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatArea() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
    
    return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _messages.length) {
                // Tarjeta compacta para "pensando" o "trabajando con archivos" - estilo Cursor
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: const Color(0xFF007ACC),
                        child: const Icon(Icons.smart_toy, size: 14, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 350),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: CursorTheme.assistantMessageBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: CursorTheme.assistantMessageBorder, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF007ACC)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _currentFileOperation != null && _currentFilePath != null
                                    ? '${_currentFileOperation == 'creando' ? 'Creando' : _currentFileOperation == 'editando' ? 'Editando' : 'Leyendo'} ${_currentFilePath!.split('/').last}'
                                    : (_loadingStatus.isNotEmpty ? _loadingStatus : 'Pensando...'),
                                style: const TextStyle(
                                  color: CursorTheme.textPrimary,
                                  fontSize: 12,
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
                );
              }
        return MessageBubble(message: _messages[index]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CursorTheme.background,
      appBar: AppBar(
        backgroundColor: CursorTheme.surface,
        elevation: 0,
        title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
            const Text('Lopez Code', style: TextStyle(color: CursorTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF007ACC).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF007ACC), width: 1),
              ),
              child: const Text('v1.5.1', style: TextStyle(color: Color(0xFF007ACC), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
        actions: [
          // Run and Debug button
          PopupMenuButton<String>(
            icon: const Icon(Icons.play_circle_outline, size: 18),
            color: CursorTheme.surface,
            tooltip: 'Run and Debug',
            onSelected: (value) {
              if (value == 'toggle_panel') {
                setState(() {
                  _showRunDebugPanel = !_showRunDebugPanel;
                });
              } else {
                // Ejecutar para la plataforma seleccionada
                _runForPlatform(value);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle_panel',
                child: Row(
                  children: [
                    Icon(
                      _showRunDebugPanel ? Icons.visibility_off : Icons.visibility,
                      size: 16,
                      color: CursorTheme.textPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _showRunDebugPanel ? 'Ocultar Consola' : 'Mostrar Consola',
                      style: const TextStyle(color: CursorTheme.textPrimary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'macos',
                child: Row(
                  children: [
                    Icon(Icons.desktop_mac, size: 16, color: CursorTheme.textPrimary),
                    SizedBox(width: 8),
                    Text('macOS', style: TextStyle(color: CursorTheme.textPrimary, fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'ios',
                child: Row(
                  children: [
                    Icon(Icons.phone_iphone, size: 16, color: CursorTheme.textPrimary),
                    SizedBox(width: 8),
                    Text('iOS', style: TextStyle(color: CursorTheme.textPrimary, fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'android',
                child: Row(
                  children: [
                    Icon(Icons.phone_android, size: 16, color: CursorTheme.textPrimary),
                    SizedBox(width: 8),
                    Text('Android', style: TextStyle(color: CursorTheme.textPrimary, fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'web',
                child: Row(
                  children: [
                    Icon(Icons.web, size: 16, color: CursorTheme.textPrimary),
                    SizedBox(width: 8),
                    Text('Web', style: TextStyle(color: CursorTheme.textPrimary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          // Toggle Project Explorer
          IconButton(
            icon: Icon(
              _showProjectExplorer ? Icons.folder_open : Icons.folder,
              size: 18,
            ),
            color: _showProjectExplorer ? CursorTheme.primary : CursorTheme.textSecondary,
            onPressed: () {
              setState(() {
                _showProjectExplorer = !_showProjectExplorer;
              });
            },
            tooltip: _showProjectExplorer ? 'Ocultar Explorador' : 'Mostrar Explorador',
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 18),
            color: CursorTheme.textSecondary,
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Row(
                  children: [
                if (_showProjectExplorer) ...[
            Container(
              width: _explorerWidth,
              decoration: BoxDecoration(
                color: CursorTheme.explorerBackground,
                border: Border(right: BorderSide(color: CursorTheme.border, width: 1)),
              ),
              child: ProjectExplorer(
                key: ValueKey('${widget.projectPath ?? _lastProjectPath ?? 'no-project'}_$_explorerRefreshCounter'),
                onFileSelected: _onFileSelected,
                onFileDoubleClick: _onFileDoubleClick,
                onFileDelete: _onFileDelete,
                onFileViewCode: _onFileViewCode,
                onFileViewScreen: _onFileViewScreen,
                onFileCopy: _onFileCopy,
              ),
            ),
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _explorerWidth += details.delta.dx;
                  if (_explorerWidth < 200) _explorerWidth = 200;
                  if (_explorerWidth > 600) _explorerWidth = 600;
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(width: 4, color: CursorTheme.border),
              ),
            ),
          ],
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _messages.isEmpty ? _buildEmptyChatArea() : _buildChatArea(),
                ),
                if (_selectedImages.isNotEmpty || _selectedFilePath != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: CursorTheme.surface,
                    child: Row(
                      children: [
                        if (_selectedImages.isNotEmpty)
                          Text('${_selectedImages.length} imagen(es)', style: const TextStyle(color: CursorTheme.textSecondary, fontSize: 12)),
                        if (_selectedFilePath != null)
                          Text(_selectedFilePath!.split('/').last, style: const TextStyle(color: CursorTheme.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                CursorChatInput(
                  controller: _messageController,
                  onSend: _sendMessage,
                  onAttachImage: _pickImage,
                  onAttachFile: _pickFile,
                  isLoading: _isLoading,
                  placeholder: 'Plan, @ for context, / for commands',
                ),
              ],
            ),
          ),
          if (_showRunDebugPanel) ...[
            Container(
              width: 4,
              color: CursorTheme.border,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    // Redimensionar panel (opcional)
                  },
                ),
              ),
            ),
            SizedBox(
              width: 400,
              child: RunDebugPanel(),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _openAIService?.dispose();
    _saveConversation();
    super.dispose();
  }
}
