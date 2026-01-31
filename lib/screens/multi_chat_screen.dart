import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/agent_chat.dart';
import '../widgets/cursor_theme.dart';
import '../widgets/explorer_toolbar.dart';
import '../widgets/project_explorer.dart';
import '../widgets/debug_console_panel.dart';
import '../widgets/phone_emulator.dart';
import '../widgets/code_editor_panel.dart';
import '../models/inspector_element.dart';
import '../services/project_service.dart';
import '../services/file_service.dart';
import '../services/chat_storage_service.dart';
import '../services/debug_console_service.dart';
import '../services/platform_service.dart';
import '../widgets/run_debug_toolbar.dart';
import 'chat_screen.dart';
import 'welcome_screen.dart';

class MultiChatScreen extends StatefulWidget {
  const MultiChatScreen({super.key});

  @override
  State<MultiChatScreen> createState() => _MultiChatScreenState();
}

class _MultiChatScreenState extends State<MultiChatScreen> {
  final List<AgentChat> _chats = [];
  String? _activeChatId;
  String? _currentProjectPath;
  double _sidebarWidth = 280.0; // Sidebar más compacto
  double _debugPanelWidth = 350.0; // Ancho del panel de debug (visible por defecto)
  double _debugPanelHeight = 250.0; // Altura del panel de debug console
  double _emulatorPanelWidth = 550.0; // Ancho del panel del emulador - más grande para mostrar todos los controles
  int _selectedToolbarIndex = 0; // Índice del toolbar seleccionado (0 = explorer, 1 = search)
  bool _emulatorVisible = true; // Emulador visible por defecto
  double _emulatorScale = 1.0; // Escala del emulador fija a 100% para mantener consistencia
  bool _inspectorMode = false; // Modo inspector activo/desactivo
  int _selectedTab = 0; // 0 = Preview, 1 = Code - SIEMPRE iniciar en Preview
  InspectorElement? _selectedElement; // Elemento seleccionado en el inspector
  String? _selectedFilePath; // Archivo seleccionado del explorador
  String? _selectedFileContent; // Contenido del archivo seleccionado

  String? _lastProjectPath; // Para detectar cambios
  final DebugConsoleService _debugService = DebugConsoleService();
  final PlatformService _platformService = PlatformService();
  final Map<String, GlobalKey> _chatScreenKeys = {}; // Keys para acceder a ChatScreen
  String? _lastOpenedUrl; // Para evitar abrir la misma URL múltiples veces

  @override
  void initState() {
    super.initState();
    // Inicializar plataforma si no está establecida
    if (_platformService.selectedPlatform.isEmpty) {
      _platformService.setPlatform('macos');
    }
    _loadProjectAndChats();
    // Escuchar cambios en el servicio de debug console
    _debugService.addListener(_onDebugServiceChanged);
    _platformService.addListener(_onPlatformChanged);
    // Emulador visible por defecto, Debug Console VISIBLE por defecto (como en la foto)
    _emulatorVisible = true;
    _selectedTab = 0; // SIEMPRE iniciar en Preview para mostrar el emulador
    _debugPanelWidth = 350.0; // Debug Console visible al inicio
    _emulatorPanelWidth = 550.0; // Ancho inicial más grande para mostrar todos los controles
    _emulatorScale = 0.7; // Escala inicial al 70% como en la foto de referencia
    _sidebarWidth = 280.0; // Sidebar más compacto al inicio
    _debugPanelHeight = 250.0; // Altura del Debug Console visible
  }

  @override
  void dispose() {
    _debugService.removeListener(_onDebugServiceChanged);
    _platformService.removeListener(_onPlatformChanged);
    super.dispose();
  }

  void _onDebugServiceChanged() {
    if (mounted) {
      setState(() {
        // Mantener el ancho del panel sincronizado con el servicio
        if (_debugService.isVisible && _debugPanelWidth == 0) {
          _debugPanelWidth = 350.0;
        } else if (!_debugService.isVisible && _debugPanelWidth > 0) {
          _debugPanelWidth = 0.0;
        }
      });
      
      // Si la URL se limpió (se detuvo el servidor), resetear el estado
      if (_debugService.appUrl == null || _debugService.appUrl!.isEmpty) {
        if (_lastOpenedUrl != null) {
          _lastOpenedUrl = null;
          print('🔄 MultiChatScreen: URL limpiada, reseteando estado de apertura');
        }
      }
      
      // NOTA: La apertura automática del navegador está desactivada.
      // La aplicación web se muestra dentro del WebView del emulador por defecto.
      // El usuario puede usar el botón flotante "Abrir en navegador" si prefiere verla en el navegador externo.
      
      // Si quieres reactivar la apertura automática, descomenta el siguiente código:
      /*
      final isWebPlatform = _platformService.selectedPlatform.toLowerCase() == 'web';
      final hasUrl = _debugService.appUrl != null && _debugService.appUrl!.isNotEmpty;
      final urlChanged = _debugService.appUrl != _lastOpenedUrl;
      final serverReady = _debugService.isRunning && _debugService.compilationProgress >= 1.0;
      
      if (isWebPlatform && 
          hasUrl && 
          serverReady && 
          urlChanged && 
          !_isOpeningUrl) {
        final urlToOpen = _debugService.appUrl!;
        _lastOpenedUrl = urlToOpen;
        _isOpeningUrl = true;
        
        print('🌐 MultiChatScreen: Detectada URL web nueva y servidor listo. Abriendo en navegador: $urlToOpen');
        
        Future.delayed(const Duration(seconds: 1), () async {
          await _openUrlInBrowser(urlToOpen);
          Future.delayed(const Duration(seconds: 2), () {
            _isOpeningUrl = false;
          });
        });
      }
      */
    }
  }
  void _onPlatformChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Verificar si el proyecto cambió cuando se vuelve a esta pantalla
    _checkProjectChange();
  }

  Future<void> _checkProjectChange() async {
    final currentProjectPath = await ProjectService.getProjectPath();
    if (currentProjectPath != _lastProjectPath) {
      print('🔄 Proyecto cambió en MultiChatScreen. Recargando...');
      _lastProjectPath = currentProjectPath;
      await _loadProjectAndChats();
    }
  }

  Future<void> _loadProjectAndChats() async {
    print('🔄 MultiChatScreen._loadProjectAndChats: Iniciando carga...');
    final projectPath = await ProjectService.getProjectPath();
    print('📁 MultiChatScreen._loadProjectAndChats: Path obtenido: $projectPath');
    
    if (projectPath == null || projectPath.isEmpty) {
      print('⚠️ MultiChatScreen._loadProjectAndChats: NO HAY PROYECTO SELECCIONADO');
      print('⚠️ Esto puede significar que:');
      print('   1. El usuario no seleccionó un proyecto');
      print('   2. El proyecto no se guardó correctamente');
      print('   3. Hubo un error al guardar el proyecto');
      
      setState(() {
        _currentProjectPath = null;
        _lastProjectPath = null;
      });
      
      // Mostrar mensaje al usuario
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay proyecto seleccionado. Por favor, selecciona un proyecto.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
      
      // No crear chat si no hay proyecto
      return;
    }
    
    // Verificar si es Flutter (solo para logging, no bloquea la carga)
    final isFlutter = await ProjectService.isFlutterProject(projectPath);
    if (isFlutter) {
      final projectName = await ProjectService.getProjectName(projectPath);
      print('✅ MultiChatScreen._loadProjectAndChats: Proyecto Flutter detectado');
      print('   Nombre: ${projectName ?? "N/A"}');
    } else {
      print('ℹ️ MultiChatScreen._loadProjectAndChats: Proyecto no-Flutter (permitido - editor de código)');
    }
    print('   Ruta: $projectPath');
    
    setState(() {
      _currentProjectPath = projectPath;
      _lastProjectPath = projectPath;
    });
    
    await _loadChatsForProject(projectPath);
  }

  Future<void> _loadChatsForProject(String projectPath) async {
    print('📁 Cargando chats para proyecto: $projectPath');
    final allChats = await ChatStorageService.loadAgentChats();
    print('📁 Total de chats en almacenamiento: ${allChats.length}');
    
    // Filtrar chats por proyecto - normalizar rutas para comparación
    final projectChats = allChats.where((chat) {
      final chatPath = chat.projectPath ?? '';
      final normalizedChatPath = chatPath.replaceAll('\\', '/');
      final normalizedProjectPath = projectPath.replaceAll('\\', '/');
      final matches = normalizedChatPath == normalizedProjectPath;
      if (matches) {
        print('✅ Chat "${chat.name}" pertenece a este proyecto');
      }
      return matches;
    }).toList();
    
    print('📁 Chats encontrados para este proyecto: ${projectChats.length}');
    
    // Ordenar por última actualización (más reciente primero)
    projectChats.sort((a, b) {
      final aTime = a.lastUpdated ?? a.createdAt;
      final bTime = b.lastUpdated ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    
    setState(() {
      _chats.clear();
      _chats.addAll(projectChats);
      
      if (_chats.isEmpty) {
        print('📁 No hay chats para este proyecto, creando uno nuevo...');
        _createNewChat();
      } else {
        // Activar el chat más reciente (primero en la lista)
        print('📁 Activando chat más reciente: ${_chats.first.name} (${_chats.first.id})');
        _chats.first.isActive = true;
        _activeChatId = _chats.first.id;
      }
    });
  }

  Future<void> _changeProject() async {
    // Navegar a WelcomeScreen para cambiar de proyecto
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const WelcomeScreen(),
      ),
    );
  }

  Future<void> _createNewChat() async {
    final newChat = AgentChat(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Chat ${_chats.length + 1}',
      messages: [],
      createdAt: DateTime.now(),
      projectPath: _currentProjectPath,
      isActive: true,
    );

    setState(() {
      // Desactivar todos los chats anteriores
      for (var chat in _chats) {
        chat.isActive = false;
      }
      _chats.add(newChat);
      _activeChatId = newChat.id;
    });
    
    // Guardar el chat
    await ChatStorageService.saveAgentChat(newChat);
  }

  Future<void> _closeChat(String chatId) async {
    if (_chats.length <= 1) {
      // No permitir cerrar el último chat
      return;
    }

    final chatIndex = _chats.indexWhere((chat) => chat.id == chatId);
    if (chatIndex == -1) return;

    final wasActive = _chats[chatIndex].id == _activeChatId;

    setState(() {
      _chats.removeAt(chatIndex);
      // Eliminar la key del chat cerrado
      _chatScreenKeys.remove(chatId);

      // Si el chat cerrado era el activo, activar otro chat
      if (wasActive && _chats.isNotEmpty) {
        _chats.first.isActive = true;
        _activeChatId = _chats.first.id;
      } else if (_chats.isNotEmpty && _activeChatId == null) {
        _chats.first.isActive = true;
        _activeChatId = _chats.first.id;
      }
    });

    // Eliminar el chat del almacenamiento
    await ChatStorageService.deleteAgentChat(chatId);
  }

  /// Construye una pestaña
  Widget _buildTab(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = index;
        });
      },
      child: Container(
        constraints: const BoxConstraints(minWidth: 80), // Ancho mínimo para evitar overflow
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? CursorTheme.surface : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isSelected ? CursorTheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? CursorTheme.primary : CursorTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? CursorTheme.primary : CursorTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Construye el contenido según la pestaña seleccionada
  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0: // Preview
        return _buildPreviewTab();
      case 1: // Code
        return _buildCodeTab();
      default:
        return _buildPreviewTab();
    }
  }

  /// Construye la pestaña Preview (emulador)
  Widget _buildPreviewTab() {
    return Column(
      children: [
        // Emulador
        Expanded(
          child: Container(
            width: double.infinity,
            color: CursorTheme.background,
            padding: const EdgeInsets.all(16),
            child: Center(
              child: AnimatedBuilder(
                animation: _debugService,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _emulatorScale,
                    child: PhoneEmulator(
                      platform: _platformService.selectedPlatform,
                      isRunning: _debugService.isRunning,
                      appUrl: _debugService.appUrl,
                      compilationProgress: _debugService.compilationProgress,
                      compilationStatus: _debugService.compilationStatus,
                      inspectorMode: _inspectorMode,
                      onElementSelected: (element) {
                        print('📥 Elemento seleccionado recibido: ${element.tagName}');
                        setState(() {
                          _selectedElement = element;
                          // Cambiar automáticamente a la pestaña Code
                          _selectedTab = 1;
                          print('📝 Cambiando a pestaña Code automáticamente');
                        });
                        // Enviar información del elemento seleccionado al chat
                        final elementInfo = 'Elemento seleccionado en el inspector:\n'
                            'Tag: ${element.tagName}\n'
                            '${element.id != null && element.id!.isNotEmpty ? "ID: ${element.id}\n" : ""}'
                            '${element.className != null && element.className!.isNotEmpty ? "Clase: ${element.className}\n" : ""}'
                            'Selector: ${element.fullSelector}\n'
                            'Dimensiones: ${element.boundingRect?.width.toInt() ?? 0}x${element.boundingRect?.height.toInt() ?? 0}px';
                        
                        print('📤 Enviando elemento seleccionado al chat: $elementInfo');
                        _sendMessageToActiveChat(elementInfo);
                      },
                      child: _debugService.isRunning && 
                            _debugService.compilationProgress == 0.0 && 
                            _debugService.appUrl == null
                        ? Container(
                            color: CursorTheme.surface,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    color: CursorTheme.primary,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Iniciando compilación...',
                                    style: TextStyle(
                                      color: CursorTheme.textPrimary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : null,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        // Debug Console Panel (si está visible)
        if (_debugService.isVisible && _debugPanelWidth > 0)
          Container(
            height: _debugPanelHeight,
            child: DebugConsolePanel(
              height: _debugPanelHeight,
              onHeightChanged: (height) {
                setState(() {
                  _debugPanelHeight = height;
                });
              },
              problems: _debugService.problems,
              output: _debugService.output,
              debugConsole: _debugService.debugConsole,
              onSendToChat: (message) {
                _sendMessageToActiveChat(message);
              },
            ),
          ),
      ],
    );
  }

  /// Construye la pestaña Code (editor de código)
  Widget _buildCodeTab() {
    // PRIORIDAD 1: Si hay un archivo seleccionado del explorador, mostrarlo
    if (_selectedFilePath != null && _selectedFileContent != null) {
      print('📝 _buildCodeTab: Mostrando archivo: $_selectedFilePath');
      return CodeEditorPanel(
        key: ValueKey('file_$_selectedFilePath'),
        filePath: _selectedFilePath,
        initialContent: _selectedFileContent,
        onSave: (path) async {
          print('💾 Guardando archivo en: $path');
          try {
            await FileService.writeFile(path, _selectedFileContent ?? '');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ Archivo guardado'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            print('❌ Error al guardar: $e');
          }
        },
        onClose: () {
          setState(() {
            _selectedFilePath = null;
            _selectedFileContent = null;
          });
        },
      );
    }
    
    // PRIORIDAD 2: Si hay un elemento seleccionado del inspector, mostrar su código HTML
    if (_selectedElement != null) {
      final code = _generateElementCode(_selectedElement!);
      print('📝 _buildCodeTab: Generando código para elemento: ${_selectedElement!.tagName}');
      print('📝 _buildCodeTab: Código generado (${code.length} caracteres)');
      
      return CodeEditorPanel(
        key: ValueKey('element_${_selectedElement!.tagName}_${_selectedElement!.hashCode}'),
        filePath: null,
        initialContent: code,
        onSave: (path) {
          print('💾 Guardando código del elemento');
        },
        onClose: () {
          setState(() {
            _selectedElement = null;
          });
        },
      );
    }
    
    // PRIORIDAD 3: Mensaje de ayuda
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.code,
                size: 64,
                color: CursorTheme.textSecondary.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'Para ver código:\n'
                '• Haz clic derecho en un archivo y selecciona "Ver código"\n'
                '• O activa el inspector y selecciona un elemento en la app',
                style: TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }


  /// Genera código HTML del elemento seleccionado
  String _generateElementCode(InspectorElement element) {
    final buffer = StringBuffer();
    
    // Comentario con información del elemento
    buffer.writeln('<!-- Elemento seleccionado: ${element.tagName} -->');
    buffer.writeln('<!-- Selector: ${element.fullSelector} -->');
    if (element.boundingRect != null) {
      buffer.writeln('<!-- Dimensiones: ${element.boundingRect!.width.toInt()}x${element.boundingRect!.height.toInt()}px -->');
    }
    buffer.writeln('');
    
    // HTML del elemento
    buffer.writeln('<${element.tagName.toLowerCase()}');
    
    // ID primero
    if (element.id != null && element.id!.isNotEmpty) {
      buffer.writeln('  id="${element.id}"');
    }
    
    // Clases después
    if (element.className != null && element.className!.isNotEmpty) {
      buffer.writeln('  class="${element.className}"');
    }
    
    // Otros atributos
    element.attributes.forEach((key, value) {
      if (key != 'id' && key != 'class') {
        buffer.writeln('  $key="$value"');
      }
    });
    
    buffer.writeln('>');
    
    // Contenido de texto (si existe)
    if (element.textContent != null && element.textContent!.isNotEmpty) {
      final text = element.textContent!.trim();
      if (text.length > 50) {
        buffer.writeln('  ${text.substring(0, 50)}...');
      } else {
        buffer.writeln('  $text');
      }
    }
    
    buffer.writeln('</${element.tagName.toLowerCase()}>');
    
    // Estilos CSS calculados
    if (element.computedStyles.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('/* Estilos calculados */');
      buffer.writeln('${element.fullSelector} {');
      
      // Agrupar estilos relacionados
      final styles = <String, String>{};
      element.computedStyles.forEach((key, value) {
        if (value.isNotEmpty && value != 'none' && value != 'auto' && value != '0px') {
          styles[key] = value;
        }
      });
      
      // Ordenar estilos: layout primero, luego visuales
      final layoutProps = ['width', 'height', 'margin', 'padding', 'position', 'top', 'left', 'right', 'bottom'];
      final visualProps = ['color', 'background', 'border', 'font', 'text'];
      
      for (final prop in layoutProps) {
        if (styles.containsKey(prop)) {
          buffer.writeln('  $prop: ${styles[prop]};');
          styles.remove(prop);
        }
      }
      
      for (final prop in visualProps) {
        styles.keys.where((k) => k.contains(prop)).forEach((key) {
          buffer.writeln('  $key: ${styles[key]};');
          styles.remove(key);
        });
      }
      
      // Resto de estilos
      styles.forEach((key, value) {
        buffer.writeln('  $key: $value;');
      });
      
      buffer.writeln('}');
    }
    
    return buffer.toString();
  }

  /// Maneja las acciones del toolbar del explorador
  void _handleToolbarAction(String action) {
    switch (action) {
      case 'search':
        _showFileSearchDialog();
        break;
      case 'git':
        _showGitDialog();
        break;
      case 'supabase':
        _showSupabaseDialog();
        break;
      case 'firebase':
        _showFirebaseDialog();
        break;
    }
  }

  /// Cambia entre modo explorador y búsqueda
  void _showFileSearchDialog() {
    setState(() {
      // Cambiar entre explorer (0) y search (1)
      _selectedToolbarIndex = _selectedToolbarIndex == 1 ? 0 : 1;
    });
  }
  
  /// Maneja la visualización de código de un archivo
  void _handleFileViewCode(String path) async {
    print('📁 Ver código: $path');
    try {
      // Leer el contenido del archivo
      final content = await FileService.readFile(path);
      setState(() {
        _selectedFilePath = path;
        _selectedFileContent = content;
        _selectedTab = 1; // Cambiar a pestaña Code
      });
    } catch (e) {
      print('❌ Error al leer archivo: $e');
      if (mounted) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Cerrar',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    }
  }

  /// Muestra el diálogo de Git (Commit & Push)
  void _showGitDialog() {
    showDialog(
      context: context,
      builder: (context) => _GitDialog(
        projectPath: _currentProjectPath,
      ),
    );
  }

  /// Muestra el diálogo de Supabase
  void _showSupabaseDialog() {
    showDialog(
      context: context,
      builder: (context) => _SupabaseDialog(),
    );
  }

  /// Muestra el diálogo de Firebase
  void _showFirebaseDialog() {
    showDialog(
      context: context,
      builder: (context) => _FirebaseDialog(),
    );
  }

  /// Obtiene el estado del ChatScreen activo
  dynamic _getActiveChatScreenState() {
    if (_activeChatId == null) return null;
    final chatKey = _chatScreenKeys[_activeChatId];
    if (chatKey == null || chatKey.currentState == null) return null;
    return chatKey.currentState;
  }

  /// Handler para Run - delega al ChatScreen activo
  void _handleRun() {
    final state = _getActiveChatScreenState();
    if (state != null) {
      try {
        (state as dynamic).handleRun();
      } catch (e) {
        print('❌ Error en _handleRun: $e');
      }
    }
  }

  /// Handler para Debug - delega al ChatScreen activo
  void _handleDebug() {
    final state = _getActiveChatScreenState();
    if (state != null) {
      try {
        (state as dynamic).handleDebug();
      } catch (e) {
        print('❌ Error en _handleDebug: $e');
      }
    }
  }

  /// Handler para Stop - delega al ChatScreen activo
  void _handleStop() {
    final state = _getActiveChatScreenState();
    if (state != null) {
      try {
        (state as dynamic).handleStop();
      } catch (e) {
        print('❌ Error en _handleStop: $e');
      }
    }
  }

  /// Handler para Restart - delega al ChatScreen activo
  void _handleRestart() {
    final state = _getActiveChatScreenState();
    if (state != null) {
      try {
        (state as dynamic).handleRestart();
      } catch (e) {
        print('❌ Error en _handleRestart: $e');
      }
    }
  }

  /// Obtiene el estado de running/debugging del ChatScreen activo
  bool _getIsRunning() {
    final state = _getActiveChatScreenState();
    if (state != null) {
      try {
        return (state as dynamic).isRunning ?? false;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  /// Obtiene el estado de debugging del ChatScreen activo
  bool _getIsDebugging() {
    final state = _getActiveChatScreenState();
    if (state != null) {
      try {
        return (state as dynamic).isDebugging ?? false;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  /// Obtiene la plataforma seleccionada del ChatScreen activo
  String _getSelectedPlatform() {
    // Priorizar PlatformService que es la fuente de verdad
    final platformFromService = _platformService.selectedPlatform;
    if (platformFromService.isNotEmpty) {
      return platformFromService;
    }
    
    // Si no hay plataforma en el servicio, intentar obtenerla del ChatScreen activo
    final state = _getActiveChatScreenState();
    if (state != null) {
      try {
        final platformFromState = (state as dynamic).selectedPlatform;
        if (platformFromState != null && platformFromState.toString().isNotEmpty) {
          return platformFromState.toString();
        }
      } catch (e) {
        // Ignorar errores
      }
    }
    
    // Fallback a 'macos' solo si no hay nada
    return 'macos';
  }

  /// Envía un mensaje al chat activo
  void _sendMessageToActiveChat(String message) {
    if (_activeChatId == null || message.isEmpty) return;
    
    try {
      // Obtener el GlobalKey del chat activo
      final chatKey = _chatScreenKeys[_activeChatId];
      if (chatKey == null || chatKey.currentState == null) {
        print('⚠️ ChatScreen no está disponible aún');
        return;
      }
      
      // Usar un microtask para evitar problemas de estado durante el build
      Future.microtask(() {
        if (!mounted) return;
        
        try {
          // Enviar mensaje al ChatScreen de forma segura
          final state = chatKey.currentState;
          if (state != null) {
            // Llamar al método usando reflection segura
            (state as dynamic).sendExternalMessage(message);
          }
        } catch (e) {
          print('❌ Error al enviar mensaje al chat: $e');
          // Mostrar mensaje de error al usuario
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al precargar mensaje: $e'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      });
    } catch (e) {
      print('❌ Error en _sendMessageToActiveChat: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sincronizar ancho del panel con el servicio
    if (_debugService.isVisible && _debugPanelWidth == 0) {
      _debugPanelWidth = 350.0;
    } else if (!_debugService.isVisible && _debugPanelWidth > 0) {
      _debugPanelWidth = 0.0;
    }
    
    return Stack(
      clipBehavior: Clip.none, // Permitir que elementos flotantes se muestren fuera del Stack
      children: [
        Scaffold(
          backgroundColor: CursorTheme.background,
          appBar: AppBar(
        backgroundColor: CursorTheme.surface,
        elevation: 0,
        title: Text(
          _currentProjectPath != null
              ? 'Proyecto: ${_currentProjectPath!.split('/').last}'
              : 'Lopez Code',
          style: const TextStyle(
            color: CursorTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // Toggle Emulador
          AnimatedBuilder(
            animation: _platformService,
            builder: (context, child) {
              return IconButton(
                icon: Icon(
                  _emulatorVisible ? Icons.phone_android : Icons.phone_android_outlined,
                  size: 18,
                ),
                color: _emulatorVisible ? CursorTheme.primary : CursorTheme.textSecondary,
                onPressed: () {
                  setState(() {
                    _emulatorVisible = !_emulatorVisible;
                  });
                },
                tooltip: _emulatorVisible ? 'Ocultar Emulador' : 'Mostrar Emulador',
              );
            },
          ),
          // Toggle Debug Console
          AnimatedBuilder(
            animation: _debugService,
            builder: (context, child) {
              return IconButton(
                icon: Icon(
                  _debugService.isVisible ? Icons.terminal : Icons.terminal_outlined,
                  size: 18,
                ),
                color: _debugService.isVisible ? CursorTheme.primary : CursorTheme.textSecondary,
                onPressed: () {
                  _debugService.togglePanel();
                  setState(() {
                    if (_debugService.isVisible && _debugPanelWidth == 0) {
                      _debugPanelWidth = 350.0;
                    } else if (!_debugService.isVisible) {
                      _debugPanelWidth = 0.0;
                    }
                  });
                },
                tooltip: _debugService.isVisible ? 'Ocultar Debug Console' : 'Mostrar Debug Console',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.folder_open, size: 18, color: CursorTheme.textPrimary),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _changeProject,
            tooltip: 'Cambiar Proyecto',
          ),
        ],
      ),
      body: Row(
        children: [
          // Panel lateral izquierdo (Explorador)
          Container(
            width: _sidebarWidth,
            decoration: BoxDecoration(
              color: CursorTheme.explorerBackground,
              border: Border(
                right: BorderSide(color: CursorTheme.border, width: 1),
              ),
            ),
            child: Column(
              children: [
                // Barra de herramientas (foto 2)
                ExplorerToolbar(
                  selectedIndex: _selectedToolbarIndex,
                  onItemSelected: (index) {
                    setState(() {
                      _selectedToolbarIndex = index;
                    });
                  },
                  onAction: (action) {
                    _handleToolbarAction(action);
                  },
                ),
                // Listado de carpetas o búsqueda (ProjectExplorer - foto 1)
                if (_currentProjectPath != null)
                  Expanded(
                    child: ProjectExplorer(
                      key: ValueKey('${_currentProjectPath}_${_selectedToolbarIndex}'),
                      mode: _selectedToolbarIndex == 1 ? 'search' : 'explorer',
                      onFileSelected: (path) {
                        print('📁 Archivo seleccionado: $path');
                      },
                      onFileDoubleClick: (path) {
                        print('📁 Doble clic en: $path');
                        _handleFileViewCode(path);
                      },
                      onFileDelete: (path) {
                        print('📁 Eliminar: $path');
                      },
                      onFileViewCode: _handleFileViewCode,
                      onFileViewScreen: (path) {
                        print('📁 Ver pantalla: $path');
                      },
                      onFileCopy: (path) {
                        print('📁 Copiar: $path');
                      },
                    ),
                  )
                else
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 48,
                            color: CursorTheme.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No hay proyecto seleccionado',
                            style: TextStyle(
                              color: CursorTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Divisor redimensionable entre explorador y contenido principal
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                // Redimensionar sidebar
                _sidebarWidth += details.delta.dx;
                if (_sidebarWidth < 150) _sidebarWidth = 150;
                if (_sidebarWidth > 400) _sidebarWidth = 400;
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: Container(
                width: 4,
                color: CursorTheme.border,
                child: Center(
                  child: Container(
                    width: 1,
                    color: CursorTheme.textDisabled,
                  ),
                ),
              ),
            ),
          ),
          // Divisor redimensionable entre contenido principal y panel derecho
          // Siempre visible cuando el emulador está visible
          if (_emulatorVisible)
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                setState(() {
                  if (_debugPanelWidth > 0) {
                    // Si el debug console está visible, ajustar su ancho
                    _debugPanelWidth -= details.delta.dx;
                    if (_debugPanelWidth < 200) _debugPanelWidth = 200;
                    if (_debugPanelWidth > 600) _debugPanelWidth = 600;
                  } else {
                    // Si solo el emulador está visible, ajustar su ancho
                    _emulatorPanelWidth -= details.delta.dx;
                    if (_emulatorPanelWidth < 400) _emulatorPanelWidth = 400; // Mínimo más grande
                    if (_emulatorPanelWidth > 800) _emulatorPanelWidth = 800; // Máximo más grande
                  }
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: 4,
                  color: CursorTheme.border,
                  child: Center(
                    child: Container(
                      width: 1,
                      color: CursorTheme.textDisabled,
                    ),
                  ),
                ),
              ),
            ),
          // Panel del medio (columna vertical) - Emulador y Debug Console
          // El emulador SIEMPRE debe estar visible por defecto
          if (_emulatorVisible)
            Container(
              width: _emulatorPanelWidth,
              decoration: BoxDecoration(
                color: CursorTheme.surface,
                border: Border(
                  right: BorderSide(color: CursorTheme.border, width: 1),
                ),
              ),
              child: Column(
                children: [
                  // Pestañas Preview/Code
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: CursorTheme.background,
                      border: Border(
                        bottom: BorderSide(color: CursorTheme.border, width: 1),
                      ),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildTab(0, 'Preview', Icons.phone_android),
                          _buildTab(1, 'Code', Icons.code),
                          const SizedBox(width: 16),
                          // Toggle "Inspect Mode" (solo visible en Preview)
                          if (_selectedTab == 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Inspect Mode',
                                  style: TextStyle(
                                    color: CursorTheme.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _inspectorMode = !_inspectorMode;
                                    });
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: _inspectorMode 
                                          ? CursorTheme.primary 
                                          : CursorTheme.surface.withOpacity(0.5),
                                      border: Border.all(
                                        color: _inspectorMode 
                                            ? CursorTheme.primary 
                                            : CursorTheme.border,
                                        width: 1,
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        AnimatedPositioned(
                                          duration: const Duration(milliseconds: 200),
                                          curve: Curves.easeInOut,
                                          left: _inspectorMode ? 22 : 2,
                                          top: 2,
                                          child: Container(
                                            width: 20,
                                            height: 20,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(10),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.2),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(width: 8),
                          // Selector de tamaño del emulador (solo visible en Preview)
                          if (_selectedTab == 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              decoration: BoxDecoration(
                                color: CursorTheme.surface,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: CursorTheme.border, width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Botón de zoom out
                                  IconButton(
                                    icon: const Icon(Icons.remove, size: 14),
                                    color: CursorTheme.textSecondary,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                    onPressed: () {
                                      setState(() {
                                        if (_emulatorScale > 0.5) {
                                          _emulatorScale -= 0.1;
                                        }
                                      });
                                    },
                                    tooltip: 'Reducir tamaño',
                                  ),
                                  // Indicador de porcentaje
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    child: Text(
                                      '${(_emulatorScale * 100).toInt()}%',
                                      style: TextStyle(
                                        color: CursorTheme.textPrimary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  // Botón de zoom in
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 14),
                                    color: CursorTheme.textSecondary,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                    onPressed: () {
                                      setState(() {
                                        if (_emulatorScale < 2.0) {
                                          _emulatorScale += 0.1;
                                        }
                                      });
                                    },
                                    tooltip: 'Aumentar tamaño',
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Contenido según la pestaña seleccionada
                  Expanded(
                    child: _buildTabContent(),
                  ),
                ],
              ),
            ),
          // Divisor redimensionable entre panel medio y chat
          // Siempre visible cuando el emulador está visible
          if (_emulatorVisible)
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                if (_debugPanelWidth > 0) {
                  // Si el debug console está visible, ajustar su ancho
                  _debugPanelWidth += details.delta.dx;
                  if (_debugPanelWidth < 200) _debugPanelWidth = 200;
                  if (_debugPanelWidth > 600) _debugPanelWidth = 600;
                } else {
                  // Si solo el emulador está visible, ajustar su ancho
                  _emulatorPanelWidth += details.delta.dx;
                  if (_emulatorPanelWidth < 400) _emulatorPanelWidth = 400; // Mínimo más grande
                  if (_emulatorPanelWidth > 800) _emulatorPanelWidth = 800; // Máximo más grande
                }
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: Container(
                width: 4,
                color: CursorTheme.border,
                child: Center(
                  child: Container(
                    width: 1,
                    color: CursorTheme.textDisabled,
                  ),
                ),
              ),
            ),
          ),
          // Panel de chat con pestañas - sin límite de ancho
          Expanded(
            child: Column(
              children: [
                  // Barra de pestañas de chat
                  Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: CursorTheme.background,
                    border: Border(
                      bottom: BorderSide(color: CursorTheme.border, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Pestañas de chat
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: _chats.map((chat) {
                              final isActive = chat.id == _activeChatId;
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    // Desactivar todos los chats
                                    for (var c in _chats) {
                                      c.isActive = false;
                                    }
                                    // Activar el chat seleccionado
                                    chat.isActive = true;
                                    _activeChatId = chat.id;
                                  });
                                },
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 100, maxWidth: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isActive ? CursorTheme.surface : Colors.transparent,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: isActive ? CursorTheme.primary : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.smart_toy,
                                        size: 14,
                                        color: isActive ? CursorTheme.primary : CursorTheme.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          chat.name,
                                          style: TextStyle(
                                            color: isActive ? CursorTheme.primary : CursorTheme.textSecondary,
                                            fontSize: 12,
                                            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      // Botón para cerrar pestaña (solo si hay más de un chat)
                                      if (_chats.length > 1)
                                        GestureDetector(
                                          onTap: () {
                                            _closeChat(chat.id);
                                          },
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              child: Icon(
                                                Icons.close,
                                                size: 14,
                                                color: CursorTheme.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      // Botón para crear nuevo chat
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          color: CursorTheme.primary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: _createNewChat,
                          tooltip: 'Nuevo Chat',
                        ),
                      ),
                    ],
                  ),
                ),
                // Contenido del chat activo
                Expanded(
                  child: _activeChatId != null && _chats.isNotEmpty && _currentProjectPath != null
                      ? ChatScreen(
                          key: _chatScreenKeys.putIfAbsent(
                            _activeChatId!,
                            () => GlobalKey(),
                          ),
                          chatId: _activeChatId!,
                          projectPath: _currentProjectPath,
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.smart_toy_outlined,
                                size: 48,
                                color: CursorTheme.textSecondary,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No hay chats activos',
                                style: TextStyle(
                                  color: CursorTheme.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _createNewChat,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Crear nuevo agente'),
                                style: TextButton.styleFrom(
                                  foregroundColor: CursorTheme.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pushAndRemoveUntil(
                                    MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                                    (route) => false,
                                  );
                                },
                                icon: const Icon(Icons.home, size: 16),
                                label: const Text('Volver a inicio'),
                                style: TextButton.styleFrom(
                                  foregroundColor: CursorTheme.textSecondary,
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
        ),
      ),
      // Barra de Run and Debug flotante (visible en toda la app)
      RunDebugToolbar(
          onRun: _handleRun,
          onDebug: _handleDebug,
          onStop: _handleStop,
          onRestart: _handleRestart,
          onPlatformChanged: (platform) {
            print('🔧 Plataforma seleccionada desde MultiChatScreen: $platform');
            
            // Detener cualquier ejecución en curso antes de cambiar de plataforma
            final state = _getActiveChatScreenState();
            if (state != null) {
              try {
                final isRunning = (state as dynamic).isRunning ?? false;
                if (isRunning) {
                  print('⚠️ Deteniendo ejecución antes de cambiar de plataforma');
                  (state as dynamic).handleStop();
                }
              } catch (e) {
                print('⚠️ Error al detener ejecución: $e');
              }
            }
            
            // Actualizar plataforma en el servicio
            _platformService.setPlatform(platform);
            
            // Limpiar URL si no es web
            if (platform.toLowerCase() != 'web') {
              _debugService.setAppUrl(null);
            }
          },
          selectedPlatform: _getSelectedPlatform(),
          isRunning: _getIsRunning(),
          isDebugging: _getIsDebugging(),
        ),
      ],
    );
  }

}

/// Diálogo de Git (Commit & Push)
class _GitDialog extends StatelessWidget {
  final String? projectPath;

  const _GitDialog({this.projectPath});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: CursorTheme.surface,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.source, color: CursorTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Git - Commit & Push',
                  style: TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: CursorTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Funcionalidad de Git próximamente disponible',
              style: TextStyle(color: CursorTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cerrar', style: TextStyle(color: CursorTheme.textPrimary)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo de Supabase
class _SupabaseDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: CursorTheme.surface,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.cloud, color: CursorTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Conectar con Supabase',
                  style: TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: CursorTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Funcionalidad de Supabase próximamente disponible',
              style: TextStyle(color: CursorTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cerrar', style: TextStyle(color: CursorTheme.textPrimary)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo de Firebase
class _FirebaseDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: CursorTheme.surface,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department, color: CursorTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Conectar con Firebase',
                  style: TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: CursorTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Funcionalidad de Firebase próximamente disponible',
              style: TextStyle(color: CursorTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cerrar', style: TextStyle(color: CursorTheme.textPrimary)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
