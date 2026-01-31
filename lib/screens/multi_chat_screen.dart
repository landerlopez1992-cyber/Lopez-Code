import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/agent_chat.dart';
import '../widgets/cursor_theme.dart';
import '../widgets/explorer_toolbar.dart';
import '../widgets/project_explorer.dart';
import '../widgets/debug_console_panel.dart';
import '../widgets/phone_emulator.dart';
import '../services/project_service.dart';
import '../services/chat_storage_service.dart';
import '../services/debug_console_service.dart';
import '../services/platform_service.dart';
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
  double _sidebarWidth = 350.0;
  double _debugPanelWidth = 0.0; // Ancho del panel de debug (0 = oculto, >0 = visible)
  int _selectedToolbarIndex = 0; // Índice del toolbar seleccionado
  bool _emulatorVisible = true; // Emulador visible por defecto
  double _emulatorScale = 0.75; // Escala del emulador (0.5 = 50%, 1.0 = 100%)

  String? _lastProjectPath; // Para detectar cambios
  final DebugConsoleService _debugService = DebugConsoleService();
  final PlatformService _platformService = PlatformService();
  final Map<String, GlobalKey> _chatScreenKeys = {}; // Keys para acceder a ChatScreen
  String? _lastOpenedUrl; // Para evitar abrir la misma URL múltiples veces

  @override
  void initState() {
    super.initState();
    _loadProjectAndChats();
    // Escuchar cambios en el servicio de debug console
    _debugService.addListener(_onDebugServiceChanged);
    _platformService.addListener(_onPlatformChanged);
    // Emulador visible por defecto, Debug Console oculto
    _emulatorVisible = true;
    _debugPanelWidth = 0.0;
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
        // Actualizar ancho del panel según visibilidad del servicio
        if (_debugService.isVisible && _debugPanelWidth == 0) {
          _debugPanelWidth = 400.0;
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
      name: 'Agente ${_chats.length + 1}',
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
    // Actualizar ancho del panel desde el servicio
    if (_debugService.isVisible && _debugPanelWidth == 0) {
      _debugPanelWidth = 400.0;
    } else if (!_debugService.isVisible && _debugPanelWidth > 0) {
      _debugPanelWidth = 0.0;
    }
    
    return Scaffold(
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
                      _debugPanelWidth = 400.0;
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
          IconButton(
            icon: const Icon(Icons.add, size: 18, color: CursorTheme.primary),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _createNewChat,
            tooltip: 'Nuevo Agente',
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
                ),
                // Listado de carpetas (ProjectExplorer - foto 1)
                if (_currentProjectPath != null)
                  Expanded(
                    child: ProjectExplorer(
                      key: ValueKey(_currentProjectPath),
                      onFileSelected: (path) {
                        print('📁 Archivo seleccionado: $path');
                      },
                      onFileDoubleClick: (path) {
                        print('📁 Doble clic en: $path');
                      },
                      onFileDelete: (path) {
                        print('📁 Eliminar: $path');
                      },
                      onFileViewCode: (path) {
                        print('📁 Ver código: $path');
                      },
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
          // Divisor redimensionable entre explorador y debug panel
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
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
          // Panel del medio (columna vertical) - Emulador y Debug Console
          if (_emulatorVisible || _debugPanelWidth > 0)
            Container(
              width: _emulatorVisible && _debugPanelWidth > 0 
                  ? _debugPanelWidth 
                  : _emulatorVisible 
                      ? 400.0  // Solo emulador visible
                      : _debugPanelWidth, // Solo debug console visible
              decoration: BoxDecoration(
                color: CursorTheme.surface,
                border: Border(
                  right: BorderSide(color: CursorTheme.border, width: 1),
                ),
              ),
              child: Column(
                children: [
                  // Emulador de teléfono (independiente del Debug Console)
                  if (_emulatorVisible) ...[
                    // Header con selector de tamaño
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: CursorTheme.background,
                        border: Border(
                          bottom: BorderSide(color: CursorTheme.border, width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Selector de tamaño del emulador
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: CursorTheme.surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: CursorTheme.border, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 16),
                                  color: CursorTheme.textSecondary,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                  onPressed: () {
                                    setState(() {
                                      _emulatorScale = (_emulatorScale - 0.1).clamp(0.5, 1.0);
                                    });
                                  },
                                  tooltip: 'Reducir tamaño',
                                ),
                                Text(
                                  '${(_emulatorScale * 100).toInt()}%',
                                  style: TextStyle(
                                    color: CursorTheme.textPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 16),
                                  color: CursorTheme.textSecondary,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                  onPressed: () {
                                    setState(() {
                                      _emulatorScale = (_emulatorScale + 0.1).clamp(0.5, 1.0);
                                    });
                                  },
                                  tooltip: 'Aumentar tamaño',
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                    // Emulador o Vista Web (ocupa todo el espacio disponible si Debug Console está oculto)
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        color: CursorTheme.background,
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: AnimatedBuilder(
                            animation: _debugService,
                            builder: (context, child) {
                              // Para todas las plataformas, usar el emulador normal (incluye WebView para web)
                              return Transform.scale(
                                scale: _emulatorScale,
                                child: Stack(
                                  children: [
                                    PhoneEmulator(
                                      platform: _platformService.selectedPlatform,
                                      isRunning: _debugService.isRunning,
                                      appUrl: _debugService.appUrl,
                                      compilationProgress: _debugService.compilationProgress,
                                      compilationStatus: _debugService.compilationStatus,
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
                                    // NOTA: El botón flotante para abrir en navegador está ahora en PhoneEmulator
                                    // No es necesario duplicarlo aquí
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    // Divisor fijo (no redimensionable) solo si ambos están visibles
                    if (_debugPanelWidth > 0)
                      Container(
                        height: 1,
                        color: CursorTheme.border,
                      ),
                  ],
                  // Debug Console Panel (con scroll) - independiente del emulador
                  if (_debugPanelWidth > 0)
                    Expanded(
                      child: DebugConsolePanel(
                        height: double.infinity,
                        onHeightChanged: (height) {
                          // No aplicable cuando está en columna vertical
                        },
                        problems: _debugService.problems,
                        output: _debugService.output,
                        debugConsole: _debugService.debugConsole,
                        onSendToChat: (message) {
                          // Enviar mensaje al chat activo
                          _sendMessageToActiveChat(message);
                        },
                      ),
                    ),
                ],
              ),
            ),
          // Divisor redimensionable entre panel medio y chat
          if (_emulatorVisible || _debugPanelWidth > 0)
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                _debugPanelWidth += details.delta.dx;
                if (_debugPanelWidth < 200) _debugPanelWidth = 200;
                if (_debugPanelWidth > 600) _debugPanelWidth = 600;
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
          // Chat activo
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
    );
  }

}
