import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/agent_chat.dart';
import '../widgets/cursor_theme.dart';
import '../widgets/voryxel_brand_logo.dart';
import '../widgets/explorer_toolbar.dart';
import '../widgets/project_explorer.dart';
import '../widgets/global_search_panel.dart';
import '../widgets/git_scm_panel.dart';
import '../widgets/ui_builder_panel.dart';
import '../widgets/ui_builder_properties_panel.dart';
import 'git_settings_screen.dart';
import '../widgets/debug_console_panel.dart';
import '../widgets/phone_emulator.dart';
import '../widgets/code_editor_panel.dart';
import '../models/inspector_element.dart';
import '../models/problem_item.dart';
import '../models/ui_builder_component.dart';
import '../services/project_service.dart';
import '../services/file_service.dart';
import '../services/chat_storage_service.dart';
import '../services/debug_console_service.dart';
import '../services/advanced_debugging_service.dart';
import '../services/platform_service.dart';
import '../services/devtools_service.dart';
import '../services/auth_service.dart';
import '../services/credit_service.dart';
import '../services/openai_service.dart';
import '../services/backend_project_inspector.dart';
import '../services/agent_activity_service.dart';
import '../services/inspector_selection_service.dart';
import '../services/ui_builder_insert_service.dart';
import '../services/ui_builder_edit_service.dart';
import '../widgets/run_debug_toolbar.dart';
import '../widgets/app_toast.dart';
import '../widgets/inspector_monitor_panel.dart';
import '../widgets/backend_connector_panels.dart';
import 'chat_screen.dart';
import 'welcome_screen.dart';
import 'wallet_screen.dart';
import 'settings_screen.dart';

/// Chip de saldo estilo Cursor; al hacer clic abre la página de billetera.
class _CreditBalanceWidget extends StatefulWidget {
  const _CreditBalanceWidget();

  @override
  State<_CreditBalanceWidget> createState() => _CreditBalanceWidgetState();
}

class _CreditBalanceWidgetState extends State<_CreditBalanceWidget> {
  double _balance = 0.0;
  bool _hover = false;
  bool _signedIn = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _signedIn = AuthService.instance.isSignedIn;
    AuthService.instance.addListener(_onAuthChanged);
    _loadBalance();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _loadBalance();
    });
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    setState(() => _signedIn = AuthService.instance.isSignedIn);
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    final balance = await CreditService.getBalance();
    if (!mounted) return;
    setState(() => _balance = balance);
  }

  void _openWallet() {
    Navigator.of(context, rootNavigator: true)
        .push(
          MaterialPageRoute(builder: (_) => const WalletScreen()),
        )
        .then((_) {
      if (mounted) _loadBalance();
    });
  }

  @override
  Widget build(BuildContext context) {
    final low = _balance <= 0;
    final accent = low ? const Color(0xFFE06C75) : CursorTheme.primary;
    final bg = _hover ? CursorTheme.surfaceHover : CursorTheme.background;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: _signedIn
            ? 'Billetera de tu cuenta'
            : 'Anónimo · sin saldo de cuenta. Inicia sesión para recargar',
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openWallet,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _hover
                      ? accent.withValues(alpha: 0.55)
                      : CursorTheme.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 13,
                    color: accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '\$${_balance.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: CursorTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (!_signedIn) ...[
                    const SizedBox(width: 4),
                    Text(
                      'anon',
                      style: TextStyle(
                        color: CursorTheme.textSecondary.withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: CursorTheme.textDisabled,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Viewport del Preview: centra el emulador y hace scroll si el zoom lo agranda.
class _PreviewZoomViewport extends StatelessWidget {
  const _PreviewZoomViewport({
    required this.panelW,
    required this.panelH,
    required this.displayW,
    required this.displayH,
    required this.child,
  });

  final double panelW;
  final double panelH;
  final double displayW;
  final double displayH;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final needsScroll = displayW > panelW + 0.5 || displayH > panelH + 0.5;
    final content = SizedBox(
      width: displayW,
      height: displayH,
      child: child,
    );

    if (!needsScroll) {
      return SizedBox(
        width: panelW,
        height: panelH,
        child: Center(child: content),
      );
    }

    return SizedBox(
      width: panelW,
      height: panelH,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(panelW, displayW),
            height: math.max(panelH, displayH),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}

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
  double _debugPanelWidth =
      350.0; // Ancho del panel de debug (visible por defecto)
  double _debugPanelHeight = 250.0; // Altura del panel de debug console
  double _chatPanelWidth = 400.0; // Ancho inicial del panel de chat
  int _selectedToolbarIndex = -1; // -1 = ninguna acción del toolbar activa
  bool _isSearchMode = false; // Modo búsqueda activo
  /// Vista del sidebar: explorer | git | search | ui_builder
  String _sidebarView = 'explorer';
  bool _emulatorVisible = true; // Emulador visible por defecto
  double _emulatorScale =
      1.0; // Escala del emulador fija a 100% para mantener consistencia
  bool _inspectorMode = false; // Modo inspector activo/desactivo
  int _selectedTab = 0; // 0 = Preview, 1 = Code - SIEMPRE iniciar en Preview
  InspectorElement? _selectedElement; // Elemento seleccionado en el inspector
  String? _selectedFilePath; // Archivo seleccionado del explorador
  String? _selectedFileContent; // Contenido del archivo seleccionado
  int? _selectedFileLine; // Línea a posicionar (Problems / analyze)
  int? _selectedFileColumn;
  /// Archivo que el agente está tocando ahora (resalte intermitente en explorer).
  String? _agentActivePath;
  /// Highlight del Preview mientras se arrastra un componente UI Builder.
  bool _uiBuilderDropHover = false;
  /// Última posición global del puntero durante un drag del UI Builder.
  Offset? _uiBuilderPointerGlobal;
  final GlobalKey<PhoneEmulatorState> _previewKey =
      GlobalKey<PhoneEmulatorState>();

  String? _lastProjectPath; // Para detectar cambios
  final DebugConsoleService _debugService = DebugConsoleService();
  final PlatformService _platformService = PlatformService();
  final AgentActivityService _agentActivity = AgentActivityService();
  final Map<String, GlobalKey> _chatScreenKeys =
      {}; // Keys para acceder a ChatScreen
  String? _lastOpenedUrl; // Para evitar abrir la misma URL múltiples veces
  int _lastAgentRevision = -1;

  @override
  void initState() {
    super.initState();
    // Plataforma por defecto al iniciar: Web (selector foto 1).
    _platformService.setPlatform('web');
    _loadProjectAndChats();
    // Snapshot inicial del Preview (por si el servicio ya tiene URL).
    _previewAppUrl = _debugService.appUrl;
    _previewRunning = _debugService.isRunning;
    _previewProgress = _debugService.compilationProgress;
    _previewStatus = _debugService.compilationStatus;
    _previewNonce = _debugService.previewReloadNonce;
    _previewReloadHard = _debugService.previewReloadHard;
    // Escuchar cambios en el servicio de debug console
    _debugService.addListener(_onDebugServiceChanged);
    _platformService.addListener(_onPlatformChanged);
    _agentActivity.addListener(_onAgentActivityChanged);
    // Notificar UI cuando flutter run termina de verdad (stop / exit)
    AdvancedDebuggingService.setOnProcessEnded(() {
      _debugService.notifyProcessEnded();
    });
    // Emulador visible por defecto, Debug Console VISIBLE por defecto (como en la foto)
    _emulatorVisible = true;
    _selectedTab = 0; // SIEMPRE iniciar en Preview para mostrar el emulador
    _debugPanelWidth = 350.0; // Debug Console visible al inicio
    // 1.0 = el Preview llena el hueco hasta la Debug Console (sin espacio vacío).
    // Transform.scale < 1 encogía solo el dibujo y dejaba un hueco muerto debajo.
    _emulatorScale = 1.0;
    _sidebarWidth = 280.0; // Sidebar más compacto al inicio
    _debugPanelHeight = 250.0; // Altura del Debug Console visible
    _chatPanelWidth = 400.0; // Ancho inicial del panel de chat
  }

  @override
  void dispose() {
    _debugService.removeListener(_onDebugServiceChanged);
    _platformService.removeListener(_onPlatformChanged);
    _agentActivity.removeListener(_onAgentActivityChanged);
    super.dispose();
  }

  /// El agente cambió de actividad → banner + (si hay archivo) Code/pulso.
  void _onAgentActivityChanged() {
    if (!mounted) return;
    final path = _agentActivity.activePath;
    final line = _agentActivity.focusLine;
    final rev = _agentActivity.revision;
    if (rev == _lastAgentRevision) return;
    _lastAgentRevision = rev;

    // Siempre rebuild del banner (compile / pub get / edit…).
    setState(() {
      if (!_agentActivity.hasFileTarget) {
        _agentActivePath = null;
      }
    });

    if (!_agentActivity.hasFileTarget) return;
    if (path == null || path.isEmpty) return;
    // No await: UI inmediata; la lectura del archivo sigue en background.
    _openFileFromAgentLive(path, line: line);
  }

  // Snapshot Preview: evita setState en cada línea de Output (eso
  // reconstruía el WebView y el scroll temblequeaba / se trababa).
  String? _previewAppUrl;
  bool _previewRunning = false;
  double _previewProgress = 0.0;
  String _previewStatus = '';
  int _previewNonce = 0;
  bool _previewReloadHard = true;

  void _onDebugServiceChanged() {
    if (!mounted) return;

    final url = _debugService.appUrl;
    final running = _debugService.isRunning;
    final progress = _debugService.compilationProgress;
    final status = _debugService.compilationStatus;
    final nonce = _debugService.previewReloadNonce;
    final reloadHard = _debugService.previewReloadHard;
    final visible = _debugService.isVisible;

    if (url == null || url.isEmpty) {
      if (_lastOpenedUrl != null) {
        _lastOpenedUrl = null;
        print(
          '🔄 MultiChatScreen: URL limpiada, reseteando estado de apertura',
        );
      }
    }

    final previewChanged = url != _previewAppUrl ||
        running != _previewRunning ||
        progress != _previewProgress ||
        status != _previewStatus ||
        nonce != _previewNonce ||
        reloadHard != _previewReloadHard;
    final panelChanged = (visible && _debugPanelWidth == 0) ||
        (!visible && _debugPanelWidth > 0);
    final hasWebView = url != null && url.isNotEmpty;
    final inspectorCleanup = !hasWebView && _inspectorMode;

    // Output/problems: DebugConsolePanel ya escucha el servicio solo.
    if (!previewChanged && !panelChanged && !inspectorCleanup) {
      return;
    }

    setState(() {
      _previewAppUrl = url;
      _previewRunning = running;
      _previewProgress = progress;
      _previewStatus = status;
      _previewNonce = nonce;
      _previewReloadHard = reloadHard;
      if (visible && _debugPanelWidth == 0) {
        _debugPanelWidth = 350.0;
      } else if (!visible && _debugPanelWidth > 0) {
        _debugPanelWidth = 0.0;
      }
      if (inspectorCleanup) {
        _inspectorMode = false;
        _selectedElement = null;
        InspectorSelectionService().clear();
      }
    });
  }

  void _onPlatformChanged() {
    if (mounted) {
      setState(() {
        // Inspector DOM funciona con Preview WebView (web o app embebida).
        final hasPreview =
            _debugService.appUrl != null && _debugService.appUrl!.isNotEmpty;
        if (!hasPreview && _inspectorMode) {
          _inspectorMode = false;
          _selectedElement = null;
          InspectorSelectionService().clear();
        }
      });
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
    print(
      '📁 MultiChatScreen._loadProjectAndChats: Path obtenido: $projectPath',
    );
    
    if (projectPath == null || projectPath.isEmpty) {
      print(
        '⚠️ MultiChatScreen._loadProjectAndChats: NO HAY PROYECTO SELECCIONADO',
      );
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
        AppToast.warning(context, 'No hay proyecto seleccionado. Por favor, selecciona un proyecto.');
      }
      
      // No crear chat si no hay proyecto
      return;
    }
    
    // Verificar si es Flutter (solo para logging, no bloquea la carga)
    final isFlutter = await ProjectService.isFlutterProject(projectPath);
    if (isFlutter) {
      final projectName = await ProjectService.getProjectName(projectPath);
      print(
        '✅ MultiChatScreen._loadProjectAndChats: Proyecto Flutter detectado',
      );
      print('   Nombre: ${projectName ?? "N/A"}');
      // Detectar carpetas + dispositivos: sin AVD/Simulator → Web Preview
      final preferred =
          await _platformService.refreshFromProject(projectPath);
      print(
        '📱 Plataformas del proyecto: ${_platformService.supportedPlatforms}',
      );
      print('🎯 Plataforma seleccionada (dropdown Run): $preferred');
      if (mounted) setState(() {}); // refresca selector de la barra superior
    } else {
      print(
        'ℹ️ MultiChatScreen._loadProjectAndChats: Proyecto no-Flutter (permitido - editor de código)',
      );
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
        print(
          '📁 Activando chat más reciente: ${_chats.first.name} (${_chats.first.id})',
        );
        _chats.first.isActive = true;
        _activeChatId = _chats.first.id;
      }
    });
  }

  Future<void> _changeProject() async {
    // Navegar a WelcomeScreen para cambiar de proyecto
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const WelcomeScreen()),
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

  /// Barra vertical arrastrable (←→) para redimensionar paneles.
  Widget _buildVerticalResizeHandle({
    required void Function(double dx) onDrag,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: SizedBox(
          width: 6,
          child: Center(
            child: Container(
              width: 1,
              color: CursorTheme.border,
            ),
          ),
        ),
      ),
    );
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
        constraints: const BoxConstraints(
          minWidth: 80,
        ), // Ancho mínimo para evitar overflow
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
              color: isSelected
                  ? CursorTheme.primary
                  : CursorTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? CursorTheme.primary
                      : CursorTheme.textSecondary,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Preview: pegado a las pestañas arriba y a la Debug Console abajo.
        // Sin Transform.scale (dejaba franja vacía arriba o abajo).
        Expanded(
          child: ColoredBox(
            color: CursorTheme.background,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
                  return const SizedBox.shrink();
                }

                const monitorW = 240.0;
                final showMonitor = _inspectorMode;
                final previewW =
                    showMonitor ? math.max(160.0, w - monitorW - 12) : w;

                // Solo plataforma: el Preview NO debe rebuild-ear con cada
                // línea de Output (provoca parpadeo / scroll roto en WebView).
                return AnimatedBuilder(
                  animation: _platformService,
                  builder: (context, _) {
                    final platform =
                        _platformService.selectedPlatform.toLowerCase();
                    // Solo web/macos llenan el panel; android/ios (Preview o
                    // Nativo) usan el marco de teléfono central.
                    final isWeb = platform == 'web' || platform == 'macos';

                    PhoneEmulator buildEmulator({
                      required double width,
                      required double height,
                    }) {
                      return PhoneEmulator(
                        key: _previewKey,
                        width: width,
                        height: height,
                        platform: _platformService.selectedPlatform,
                        isRunning: _previewRunning,
                        appUrl: _previewAppUrl,
                        compilationProgress: _previewProgress,
                        compilationStatus: _previewStatus,
                        previewReloadNonce: _previewNonce,
                        previewReloadHard: _previewReloadHard,
                        inspectorMode: _inspectorMode,
                        onElementSelected: (element) {
                          setState(() => _selectedElement = element);
                          final id = _voryxelBlockIdOf(element);
                          if (id != null) {
                            unawaited(
                              _previewKey.currentState?.bindUiBuilderMove(id),
                            );
                          }
                        },
                        onUiBuilderMoved: (id, left, top) {
                          unawaited(_syncUiBuilderPosition(id, left, top));
                        },
                        onUiBuilderTextEdited: (id, text) {
                          unawaited(_syncUiBuilderText(id, text));
                        },
                        child: null,
                      );
                    }

                    final zoom = _emulatorScale.clamp(0.5, 2.0);

                    Widget previewBody;
                    if (isWeb) {
                      final displayW = previewW * zoom;
                      final displayH = h * zoom;
                      previewBody = _PreviewZoomViewport(
                        panelW: previewW,
                        panelH: h,
                        displayW: displayW,
                        displayH: displayH,
                        child: buildEmulator(
                          width: displayW,
                          height: displayH,
                        ),
                      );
                    } else {
                      const baseW = 300.0;
                      const baseH = 650.0;
                      final fit100 =
                          math.min(previewW / baseW, h / baseH);
                      final displayW = baseW * fit100 * zoom;
                      final displayH = baseH * fit100 * zoom;
                      previewBody = _PreviewZoomViewport(
                        panelW: previewW,
                        panelH: h,
                        displayW: displayW,
                        displayH: displayH,
                        child: buildEmulator(
                          width: displayW,
                          height: displayH,
                        ),
                      );
                    }

                    // Zona de drop del UI Builder (arrastrar componentes → HTML).
                    final dropPreview = Listener(
                      onPointerMove: (e) {
                        if (_uiBuilderDropHover) {
                          _uiBuilderPointerGlobal = e.position;
                        }
                      },
                      child: DragTarget<UiBuilderComponent>(
                      onWillAcceptWithDetails: (details) {
                        if (!_uiBuilderDropHover) {
                          setState(() => _uiBuilderDropHover = true);
                        }
                        return true;
                      },
                      onMove: (details) {
                        _uiBuilderPointerGlobal = details.offset;
                      },
                      onLeave: (_) {
                        if (_uiBuilderDropHover) {
                          setState(() => _uiBuilderDropHover = false);
                        }
                      },
                      onAcceptWithDetails: (details) {
                        final dropAt =
                            _uiBuilderPointerGlobal ?? details.offset;
                        setState(() {
                          _uiBuilderDropHover = false;
                          _uiBuilderPointerGlobal = null;
                        });
                        unawaited(
                          _handleUiBuilderDrop(
                            details.data,
                            globalOffset: dropAt,
                          ),
                        );
                      },
                      builder: (context, candidate, rejected) {
                        final hovering =
                            candidate.isNotEmpty || _uiBuilderDropHover;
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            previewBody,
                            if (hovering)
                              IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: CursorTheme.primary
                                        .withValues(alpha: 0.12),
                                    border: Border.all(
                                      color: CursorTheme.primary,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Suelta aquí para añadir al HTML',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        shadows: [
                                          Shadow(
                                            blurRadius: 8,
                                            color: Colors.black54,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    );

                    if (!showMonitor) return dropPreview;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: dropPreview),
                        const InspectorMonitorPanel(width: monitorW),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
        if (_debugService.isVisible && _debugPanelWidth > 0)
          SizedBox(
            height: _debugPanelHeight,
            child: DebugConsolePanel(
              height: _debugPanelHeight,
              onHeightChanged: (height) {
                setState(() {
                  _debugPanelHeight = height;
                });
              },
              problemItems: _debugService.problemItems,
              output: _debugService.output,
              debugConsole: _debugService.debugConsole,
              projectPath: _currentProjectPath,
              onSendToChat: (message) {
                _sendMessageToActiveChat(message);
              },
              onProblemTap: _handleProblemTap,
              onRefreshAnalyze: () {
                _debugService.refreshProblemsFromAnalyze();
              },
            ),
          ),
      ],
    );
  }

  /// Construye la pestaña Code (editor de código)
  Widget _buildCodeTab() {
    // El banner superior ya se pinta arriba de _buildTabContent() (sin duplicar).

    // PRIORIDAD 1: Si hay un archivo seleccionado del explorador, mostrarlo
    if (_selectedFilePath != null && _selectedFileContent != null) {
      print('📝 _buildCodeTab: Mostrando archivo: $_selectedFilePath');
      // Key estable: las pestañas multi-archivo viven dentro del panel.
      return CodeEditorPanel(
          key: const ValueKey('main_code_editor'),
          filePath: _selectedFilePath,
          initialContent: _selectedFileContent,
          initialLine: _selectedFileLine,
          initialColumn: _selectedFileColumn,
          onActiveFileChanged: (path, content) {
            if (!mounted) return;
            if (path == _selectedFilePath && content == _selectedFileContent) {
              return;
            }
            setState(() {
              _selectedFilePath = path;
              _selectedFileContent = content;
            });
          },
          onSave: (path) async {
            try {
              final savedContent = await FileService.readFile(path);
              if (mounted) {
                setState(() {
                  _selectedFileContent = savedContent;
                  _selectedFilePath = path;
                });
              }
            } catch (e) {
              print('❌ Error al sincronizar archivo guardado: $e');
            }
          },
          onClose: () {
            setState(() {
              _selectedFilePath = null;
              _selectedFileContent = null;
              _selectedFileLine = null;
              _selectedFileColumn = null;
            });
          },
      );
    }
    
    // PRIORIDAD 2: Si hay un elemento seleccionado del inspector, mostrar su código HTML
    if (_selectedElement != null) {
      final code = _generateElementCode(_selectedElement!);
      print(
        '📝 _buildCodeTab: Generando código para elemento: ${_selectedElement!.tagName}',
      );
      print('📝 _buildCodeTab: Código generado (${code.length} caracteres)');
      
      return CodeEditorPanel(
        key: ValueKey(
          'element_${_selectedElement!.tagName}_${_selectedElement!.hashCode}',
        ),
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
            mainAxisSize: MainAxisSize.min, // ✅ FIX: Evita altura infinita
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
      buffer.writeln(
        '<!-- Dimensiones: ${element.boundingRect!.width.toInt()}x${element.boundingRect!.height.toInt()}px -->',
      );
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
        if (value.isNotEmpty &&
            value != 'none' &&
            value != 'auto' &&
            value != '0px') {
          styles[key] = value;
        }
      });
      
      // Ordenar estilos: layout primero, luego visuales
      final layoutProps = [
        'width',
        'height',
        'margin',
        'padding',
        'position',
        'top',
        'left',
        'right',
        'bottom',
      ];
      final visualProps = ['color', 'background', 'border', 'font', 'text'];
      
      for (final prop in layoutProps) {
        if (styles.containsKey(prop)) {
          buffer.writeln('  $prop: ${styles[prop]};');
          styles.remove(prop);
        }
      }
      
      for (final prop in visualProps) {
        // Recopilar primero las claves que coinciden para evitar ConcurrentModificationError
        final matchingKeys = styles.keys.where((k) => k.contains(prop)).toList();
        for (final key in matchingKeys) {
          buffer.writeln('  $key: ${styles[key]};');
          styles.remove(key);
        }
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
      case 'ui_builder':
        setState(() {
          final opening = _sidebarView != 'ui_builder';
          _sidebarView = opening ? 'ui_builder' : 'explorer';
          _isSearchMode = false;
          _selectedToolbarIndex = opening ? 0 : -1;
          if (opening) {
            _selectedTab = 0; // Preview al construir
            _inspectorMode = true; // clic = seleccionar para propiedades
            InspectorSelectionService().setActive(true);
          }
        });
        break;
      case 'search':
        _toggleGlobalSearch();
        break;
      case 'git':
        setState(() {
          final openingGit = _sidebarView != 'git';
          _sidebarView = openingGit ? 'git' : 'explorer';
          _isSearchMode = false;
          _selectedToolbarIndex = openingGit ? 2 : -1;
        });
        break;
      case 'supabase':
        _showSupabaseDialog();
        break;
      case 'firebase':
        _showFirebaseDialog();
        break;
    }
  }

  /// Drop de UI Builder → inserta HTML donde se soltó y recarga Preview.
  Future<void> _handleUiBuilderDrop(
    UiBuilderComponent component, {
    Offset? globalOffset,
  }) async {
    final projectPath = _currentProjectPath;
    if (projectPath == null || projectPath.isEmpty) {
      if (mounted) {
        AppToast.warning(context, 'Abre un proyecto web primero');
      }
      return;
    }

    try {
      final target = await UiBuilderInsertService.resolveTargetHtmlPath(
        projectPath: projectPath,
        selectedFilePath: _selectedFilePath,
      );
      if (target == null) {
        if (mounted) {
          AppToast.warning(
            context,
            'No hay archivo .html en el proyecto (crea index.html)',
          );
        }
        return;
      }

      String? parentId;
      String? beforeId;
      String? afterId;

      // Preferir ancla real del punto de soltado en el WebView.
      final previewState = _previewKey.currentState;
      if (previewState != null && globalOffset != null) {
        final box = previewState.context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final local = box.globalToLocal(globalOffset);
          final nx = (local.dx / box.size.width).clamp(0.0, 1.0);
          final ny = (local.dy / box.size.height).clamp(0.0, 1.0);
          final anchor = await previewState.resolveUiBuilderDrop(
            nx: nx,
            ny: ny,
          );
          if (anchor != null) {
            parentId = anchor['parentId']?.toString();
            beforeId = anchor['beforeId']?.toString();
            afterId = anchor['afterId']?.toString();
            if (parentId != null && parentId.isEmpty) parentId = null;
            if (beforeId != null && beforeId.isEmpty) beforeId = null;
            if (afterId != null && afterId.isEmpty) afterId = null;
          }
        }
      }

      // Fallback: contenedor seleccionado.
      if (parentId == null &&
          _voryxelBlockIdOf(_selectedElement) != null &&
          _isUiBuilderContainer(_selectedElement)) {
        parentId = _voryxelBlockIdOf(_selectedElement);
      }

      final result = await UiBuilderInsertService.insertAtAnchor(
        filePath: target,
        snippet: component.htmlSnippet,
        parentId: parentId,
        beforeId: beforeId,
        afterId: afterId,
      );
      final html = result.html;
      final blockId = result.blockId;

      if (!mounted) return;
      setState(() {
        _selectedFilePath = target;
        _selectedFileContent = html;
        _selectedTab = 0;
        _uiBuilderDropHover = false;
        _inspectorMode = true;
      });
      InspectorSelectionService().setActive(true);

      final previewLive = _debugService.isRunning &&
          (_debugService.appUrl?.isNotEmpty ?? false);
      final where = parentId != null
          ? 'dentro de contenedor'
          : (beforeId != null
              ? 'antes de $beforeId'
              : (afterId != null ? 'después de $afterId' : target.split('/').last));

      if (!previewLive) {
        _debugService.addOutput(
          '🧩 UI Builder: ${component.label} → $where '
          '($blockId) · arrancando Preview…',
        );
        AppToast.info(
          context,
          '${component.label} guardado · arrancando Preview…',
        );
        _handleRun();
      } else {
        _debugService.bumpPreviewReload(force: true, hard: false);
        _debugService.addOutput(
          '🧩 UI Builder: ${component.label} → $where ($blockId)',
        );
        AppToast.success(
          context,
          '${component.label} añadido donde soltaste · clic para editar',
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'No se pudo insertar: $e');
      }
    }
  }

  Future<void> _syncUiBuilderPosition(
    String blockId,
    double left,
    double top,
  ) async {
    try {
      final target = await _resolveHtmlFileForEdit();
      if (target == null) return;
      final next = await UiBuilderEditService.updateBlock(
        filePath: target,
        blockId: blockId,
        absolute: true,
        left: '${left.round()}px',
        top: '${top.round()}px',
      );
      if (!mounted) return;
      setState(() {
        _selectedFilePath = target;
        _selectedFileContent = next;
      });
    } catch (e) {
      print('⚠️ sync position: $e');
    }
  }

  Future<void> _syncUiBuilderText(String blockId, String text) async {
    try {
      final target = await _resolveHtmlFileForEdit();
      if (target == null) return;
      final next = await UiBuilderEditService.updateBlock(
        filePath: target,
        blockId: blockId,
        text: text,
      );
      if (!mounted) return;
      setState(() {
        _selectedFilePath = target;
        _selectedFileContent = next;
      });
    } catch (e) {
      print('⚠️ sync text: $e');
    }
  }

  String? _voryxelBlockIdOf(InspectorElement? el) {
    if (el == null) return null;
    final id = el.attributes['data-voryxel-id']?.trim();
    if (id != null && id.isNotEmpty) return id;
    return null;
  }

  Future<String?> _resolveHtmlFileForEdit() async {
    final projectPath = _currentProjectPath;
    if (projectPath == null) return null;
    return UiBuilderInsertService.resolveTargetHtmlPath(
      projectPath: projectPath,
      selectedFilePath: _selectedFilePath,
    );
  }

  Future<void> _applyUiBuilderProps({
    required String blockId,
    String? text,
    String? color,
    String? backgroundColor,
    String? padding,
    String? margin,
    String? width,
    String? height,
    String? fontSize,
    String? borderRadius,
    String? border,
    String? textAlign,
    String? href,
    String? src,
    String? placeholder,
  }) async {
    try {
      final target = await _resolveHtmlFileForEdit();
      if (target == null) {
        if (mounted) {
          AppToast.warning(context, 'No hay HTML destino');
        }
        return;
      }
      final next = await UiBuilderEditService.updateBlock(
        filePath: target,
        blockId: blockId,
        text: text,
        color: color,
        backgroundColor: backgroundColor,
        padding: padding,
        margin: margin,
        width: width,
        height: height,
        fontSize: fontSize,
        borderRadius: borderRadius,
        border: border,
        textAlign: textAlign,
        href: href,
        src: src,
        placeholder: placeholder,
      );
      if (!mounted) return;
      setState(() {
        _selectedFilePath = target;
        _selectedFileContent = next;
      });
      _debugService.bumpPreviewReload(force: true, hard: false);
      AppToast.success(context, 'Propiedades aplicadas');
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'No se pudo aplicar: $e');
      }
    }
  }

  Future<void> _duplicateUiBuilderBlock(String blockId) async {
    try {
      final target = await _resolveHtmlFileForEdit();
      if (target == null) {
        if (mounted) {
          AppToast.warning(context, 'No hay HTML destino');
        }
        return;
      }
      final result = await UiBuilderEditService.duplicateBlock(
        filePath: target,
        blockId: blockId,
      );
      if (!mounted) return;
      setState(() {
        _selectedFilePath = target;
        _selectedFileContent = result.html;
      });
      _debugService.bumpPreviewReload(force: true, hard: false);
      AppToast.success(context, 'Elemento duplicado');
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'No se pudo duplicar: $e');
      }
    }
  }

  bool _isUiBuilderContainer(InspectorElement? el) {
    if (el == null) return false;
    final kind = el.attributes['data-voryxel']?.toLowerCase() ?? '';
    return kind == 'container' || kind == 'card' || kind == 'hero';
  }

  Future<void> _moveUiBuilderBlock(String blockId, int direction) async {
    try {
      final target = await _resolveHtmlFileForEdit();
      if (target == null) {
        if (mounted) {
          AppToast.warning(context, 'No hay HTML destino');
        }
        return;
      }
      final next = await UiBuilderEditService.moveBlock(
        filePath: target,
        blockId: blockId,
        direction: direction,
      );
      if (!mounted) return;
      setState(() {
        _selectedFilePath = target;
        _selectedFileContent = next;
      });
      _debugService.bumpPreviewReload(force: true, hard: false);
      AppToast.info(
        context,
        direction < 0 ? 'Movido arriba' : 'Movido abajo',
      );
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'No se pudo mover: $e');
      }
    }
  }

  Future<void> _deleteUiBuilderBlock(String blockId) async {
    try {
      final target = await _resolveHtmlFileForEdit();
      if (target == null) {
        if (mounted) {
          AppToast.warning(context, 'No hay HTML destino');
        }
        return;
      }
      final next = await UiBuilderEditService.deleteBlock(
        filePath: target,
        blockId: blockId,
      );
      if (!mounted) return;
      setState(() {
        _selectedFilePath = target;
        _selectedFileContent = next;
        _selectedElement = null;
      });
      InspectorSelectionService().clearSelection();
      _debugService.bumpPreviewReload(force: true, hard: false);
      AppToast.success(context, 'Elemento eliminado');
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'No se pudo eliminar: $e');
      }
    }
  }

  /// Abre o cierra Search in Files en el sidebar.
  void _toggleGlobalSearch() {
    setState(() {
      if (_sidebarView == 'search' || _isSearchMode) {
        _sidebarView = 'explorer';
        _isSearchMode = false;
        _selectedToolbarIndex = -1;
      } else {
        _sidebarView = 'search';
        _isSearchMode = true;
        _selectedToolbarIndex = 1;
      }
    });
  }

  /// Abre Search in Files (atajo ⌘⇧F / Ctrl+Shift+F).
  void _openGlobalSearch() {
    setState(() {
      _sidebarView = 'search';
      _isSearchMode = true;
      _selectedToolbarIndex = 1;
    });
  }

  /// Resultado de grep → abrir en CodeEditorPanel en esa línea.
  Future<void> _handleGlobalSearchResult(String filePath, int lineNumber) {
    return _handleFileViewCode(
      filePath,
      line: lineNumber > 0 ? lineNumber : null,
    );
  }
  
  /// Carga un archivo en la pestaña Code.
  /// [switchToCodeTab]=false → lo deja listo en segundo plano (Preview sigue).
  Future<void> _handleFileViewCode(
    String path, {
    int? line,
    int? column,
    bool switchToCodeTab = true,
  }) async {
    print(
      '📁 Ver código: $path${line != null ? ':$line' : ''}'
      '${switchToCodeTab ? '' : ' (2º plano)'}',
    );
    try {
      final content = await FileService.readFile(path);
      if (!mounted) return;
      setState(() {
        _selectedFilePath = path;
        _selectedFileContent = content;
        _selectedFileLine = line;
        _selectedFileColumn = column;
        if (switchToCodeTab) {
          _selectedTab = 1;
        }
      });
    } catch (e) {
      print('❌ Error al leer archivo: $e');
      if (mounted) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        AppToast.error(context, errorMessage);
      }
    }
  }

  /// Resuelve una ruta del agente a un archivo del proyecto (si existe).
  Future<String?> _resolveAgentPathInProject(String rawPath) async {
    final trimmed = rawPath.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty) return null;

    final projectPath =
        (_currentProjectPath ?? await ProjectService.getProjectPath())
            ?.replaceAll('\\', '/');

    // Absoluta
    if (trimmed.startsWith('/')) {
      if (await File(trimmed).exists()) {
        // Si está dentro del proyecto, úsala; si no, busca mismo basename.
        if (projectPath != null && trimmed.startsWith('$projectPath/')) {
          return trimmed;
        }
        final base = trimmed.split('/').last;
        if (projectPath != null && base.isNotEmpty) {
          final found = await _findFileByBasename(projectPath, base);
          if (found != null) return found;
        }
        // Fuera del proyecto (p.ej. .pub-cache): abrir igual en editor.
        return trimmed;
      }
    }

    if (projectPath == null) return null;

    // Relativa al proyecto
    final candidate = '$projectPath/$trimmed';
    if (await File(candidate).exists()) return candidate;

    // Solo basename → buscar en el proyecto
    final base = trimmed.split('/').last;
    if (base.isNotEmpty) {
      final found = await _findFileByBasename(projectPath, base);
      if (found != null) return found;
    }
    return null;
  }

  Future<String?> _findFileByBasename(String root, String basename) async {
    try {
      final dir = Directory(root);
      if (!await dir.exists()) return null;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final p = entity.path.replaceAll('\\', '/');
        if (p.contains('/.') || p.contains('/build/')) continue;
        if (p.split('/').last == basename) return p;
      }
    } catch (_) {}
    return null;
  }

  /// El agente edita/lee: carga el archivo en Code en 2º plano.
  /// Preview se mantiene; el usuario puede pulsar «Ver en Code».
  /// [reveal]=true solo si el usuario pidió ver el archivo (clic en chat).
  Future<void> _openFileFromAgentLive(
    String rawPath, {
    int? line,
    bool reveal = false,
  }) async {
    final trimmed = rawPath.trim();
    // path vacío = el agente terminó → quitar pulso del explorador
    if (trimmed.isEmpty) {
      if (mounted) setState(() => _agentActivePath = null);
      return;
    }

    final resolved = await _resolveAgentPathInProject(trimmed);
    final highlightPath = resolved ?? trimmed;

    if (mounted) {
      setState(() {
        _agentActivePath = highlightPath;
        // No forzar Code: el Preview sigue visible mientras trabaja.
      });
    }

    if (resolved == null || !await File(resolved).exists()) {
      print('⚠️ Agent live view: archivo no encontrado aún: $trimmed');
      return;
    }

    await _handleFileViewCode(
      resolved,
      line: line,
      switchToCodeTab: reveal,
    );
  }

  /// Desde "Compilación fallida" → Ver código: abre el editor sin IA.
  /// Si hay un error con archivo, salta a esa línea; si no, solo pestaña Code.
  Future<void> _openCodeEditorFromErrorDialog() async {
    final errors = _debugService.problemItems
        .where(
          (p) =>
              p.severity == ProblemSeverity.error && p.filePath.trim().isNotEmpty,
        )
        .toList();
    if (errors.isNotEmpty) {
      await _handleProblemTap(errors.first);
      return;
    }

    // Fallback: primer warning con path, o archivo ya abierto / main.dart
    final withPath = _debugService.problemItems
        .where((p) => p.filePath.trim().isNotEmpty)
        .toList();
    if (withPath.isNotEmpty) {
      await _handleProblemTap(withPath.first);
      return;
    }

    if (_selectedFilePath != null && _selectedFilePath!.isNotEmpty) {
      setState(() => _selectedTab = 1);
      return;
    }

    final projectPath =
        _currentProjectPath ?? await ProjectService.getProjectPath();
    if (projectPath != null) {
      final mainDart = File('$projectPath/lib/main.dart');
      if (await mainDart.exists()) {
        await _handleFileViewCode(mainDart.path);
        return;
      }
    }

    setState(() => _selectedTab = 1);
  }

  /// Abre el archivo de un ProblemItem en el editor en la línea indicada.
  Future<void> _handleProblemTap(ProblemItem problem) async {
    if (problem.filePath.isEmpty) return;

    final projectPath = await ProjectService.getProjectPath();
    final absolutePath = problem.filePath.startsWith('/')
        ? problem.filePath
        : (projectPath != null
            ? '$projectPath/${problem.filePath}'
            : problem.filePath);

    await _handleFileViewCode(
      absolutePath,
      line: problem.line > 0 ? problem.line : null,
      column: problem.column > 0 ? problem.column : null,
    );
  }

  /// Muestra la pantalla de configuración de Git
  void _showGitDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const GitSettingsScreen(),
      ),
    );
  }

  Future<void> _showSupabaseDialog() async {
    final projectPath =
        _currentProjectPath ?? await ProjectService.getProjectPath();
    if (projectPath == null || projectPath.isEmpty) {
      if (!mounted) return;
      AppToast.info(context, 'No hay proyecto cargado');
      return;
    }
    final result =
        await BackendProjectInspector.inspectSupabase(projectPath);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => SupabaseConnectorDialog(
        projectPath: projectPath,
        inspection: result,
        onAskAgent: _askAgentNow,
      ),
    );
  }

  Future<void> _showFirebaseDialog() async {
    final projectPath =
        _currentProjectPath ?? await ProjectService.getProjectPath();
    if (projectPath == null || projectPath.isEmpty) {
      if (!mounted) return;
      AppToast.info(context, 'No hay proyecto cargado');
      return;
    }
    final result =
        await BackendProjectInspector.inspectFirebase(projectPath);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => FirebaseConnectorDialog(
        projectPath: projectPath,
        inspection: result,
        onAskAgent: _askAgentNow,
        onDeploy: () => _runFirebaseDeploy(projectPath),
      ),
    );
  }

  Future<void> _runFirebaseDeploy(String projectPath) async {
    _debugService.showOutputTab();
    _debugService.addOutput('🔥 Ejecutando: firebase deploy');
    _debugService.addOutput('📁 cwd: $projectPath');
    try {
      final process = await Process.start(
        'firebase',
        ['deploy'],
        workingDirectory: projectPath,
        runInShell: false,
      );
      process.stdout.transform(utf8.decoder).listen((chunk) {
        for (final line in chunk.split('\n')) {
          if (line.trim().isEmpty) continue;
          _debugService.addOutput(line);
        }
      });
      process.stderr.transform(utf8.decoder).listen((chunk) {
        for (final line in chunk.split('\n')) {
          if (line.trim().isEmpty) continue;
          _debugService.addOutput('ERR: $line');
        }
      });
      final code = await process.exitCode;
      _debugService.addOutput(
        code == 0
            ? '✅ firebase deploy terminó OK'
            : '❌ firebase deploy exit code $code',
      );
    } catch (e) {
      _debugService.addOutput('❌ No se pudo ejecutar firebase deploy: $e');
      _debugService.addOutput(
        '💡 Instala Firebase CLI (`npm i -g firebase-tools`) y asegúrate de estar logueado.',
      );
      if (mounted) {
        AppToast.error(context, 'firebase deploy falló: $e');
      }
    }
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

  /// ⚡ Hot Reload — aplica código en caliente (sin reiniciar estado).
  void _handleHotReload() {
    if (!mounted) return;
    final isHtmlPreview = _debugService.isRunning &&
        _debugService.appUrl != null &&
        _debugService.appUrl!.isNotEmpty &&
        !AdvancedDebuggingService.supportsHotReload;
    AppToast.show(
      context,
      message: isHtmlPreview
          ? '⚡ Hot Reload — refrescando Preview…'
          : '⚡ Hot Reload — aplicando código…',
      icon: Icons.bolt,
      loading: true,
      duration: const Duration(milliseconds: 1200),
    );
    final state = _getActiveChatScreenState();
    if (state != null) {
      try {
        (state as dynamic).handleHotReload();
      } catch (e) {
        print('❌ Error en _handleHotReload: $e');
        // Fallback directo al servicio si el chat no expone el método.
        unawaited(_debugService.requestHotReload());
      }
    } else {
      unawaited(_debugService.requestHotReload());
    }
  }

  /// 🔄 Hot Restart — reinicia la app / Preview desde cero.
  void _handleHotRestart() {
    if (!mounted) return;
    final isHtmlPreview = _debugService.isRunning &&
        _debugService.appUrl != null &&
        _debugService.appUrl!.isNotEmpty &&
        !AdvancedDebuggingService.supportsHotReload;
    AppToast.show(
      context,
      message: isHtmlPreview
          ? '🔄 Hot Restart — recarga el Preview (no deshace ediciones)'
          : '🔄 Hot Restart — reiniciando app…',
      icon: Icons.restart_alt,
      loading: true,
      duration: const Duration(milliseconds: 1800),
    );
    final state = _getActiveChatScreenState();
    if (state != null) {
      try {
        (state as dynamic).handleHotRestart();
      } catch (e) {
        print('❌ Error en _handleHotRestart: $e');
        unawaited(_debugService.requestHotRestart());
      }
    } else {
      unawaited(_debugService.requestHotRestart());
    }
  }

  /// Obtiene el estado de running/debugging del ChatScreen activo
  bool _getIsRunning() {
    if (_debugService.isRunning) return true;
    if (AdvancedDebuggingService.isRunning) return true;
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
        if (platformFromState != null &&
            platformFromState.toString().isNotEmpty) {
          return platformFromState.toString();
        }
      } catch (e) {
        // Ignorar errores
      }
    }
    
    // Fallback a 'android' solo si no hay nada
    return 'android';
  }

  /// Mensaje al chat activo. [autoSend] true = dispara el agente (conectores).
  void _sendMessageToActiveChat(String message, {bool autoSend = false}) {
    if (_activeChatId == null || message.isEmpty) return;

    try {
      final chatKey = _chatScreenKeys[_activeChatId];
      if (chatKey == null || chatKey.currentState == null) {
        print('⚠️ ChatScreen no está disponible aún');
        return;
      }

      Future.microtask(() {
        if (!mounted) return;

        try {
          final state = chatKey.currentState;
          if (state != null) {
            (state as dynamic).sendExternalMessage(
              message,
              autoSend: autoSend,
            );
          }
        } catch (e) {
          print('❌ Error al enviar mensaje al chat: $e');
          if (mounted) {
            AppToast.error(
              context,
              autoSend
                  ? 'Error al disparar el agente: $e'
                  : 'Error al precargar mensaje: $e',
            );
          }
        }
      });
    } catch (e) {
      print('❌ Error en _sendMessageToActiveChat: $e');
    }
  }

  void _askAgentNow(String message) {
    _sendMessageToActiveChat(message, autoSend: true);
  }

  @override
  Widget build(BuildContext context) {
    // Sincronizar ancho del panel con el servicio
    if (_debugService.isVisible && _debugPanelWidth == 0) {
      _debugPanelWidth = 350.0;
    } else if (!_debugService.isVisible && _debugPanelWidth > 0) {
      _debugPanelWidth = 0.0;
    }
    
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: true,
          shift: true,
        ): _openGlobalSearch,
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
          shift: true,
        ): _openGlobalSearch,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
      clipBehavior: Clip
          .none, // Permitir que elementos flotantes se muestren fuera del Stack
      children: [
        Scaffold(
          backgroundColor: CursorTheme.background,
          appBar: AppBar(
        backgroundColor: CursorTheme.surface,
        elevation: 0,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Image.asset(
                VoryxelBrandLogo.assetTile,
                width: 20,
                height: 20,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.code,
                  size: 18,
                  color: CursorTheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _currentProjectPath != null
                    ? 'Proyecto: ${_currentProjectPath!.split('/').last}'
                    : 'Voryxel Code',
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          const Center(child: _CreditBalanceWidget()),
          // Toggle Emulador
          AnimatedBuilder(
            animation: _platformService,
            builder: (context, child) {
              return IconButton(
                icon: Icon(
                      _emulatorVisible
                          ? Icons.phone_android
                          : Icons.phone_android_outlined,
                  size: 18,
                ),
                    color: _emulatorVisible
                        ? CursorTheme.primary
                        : CursorTheme.textSecondary,
                onPressed: () {
                  setState(() {
                    _emulatorVisible = !_emulatorVisible;
                  });
                },
                    tooltip: _emulatorVisible
                        ? 'Ocultar Emulador'
                        : 'Mostrar Emulador',
              );
            },
          ),
          // Toggle Debug Console
          AnimatedBuilder(
            animation: _debugService,
            builder: (context, child) {
              return IconButton(
                icon: Icon(
                      _debugService.isVisible
                          ? Icons.terminal
                          : Icons.terminal_outlined,
                  size: 18,
                ),
                    color: _debugService.isVisible
                        ? CursorTheme.primary
                        : CursorTheme.textSecondary,
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
                    tooltip: _debugService.isVisible
                        ? 'Ocultar Debug Console'
                        : 'Mostrar Debug Console',
              );
            },
          ),
          IconButton(
                icon: const Icon(
                  Icons.folder_open,
                  size: 18,
                  color: CursorTheme.textPrimary,
                ),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _changeProject,
            tooltip: 'Cambiar Proyecto',
          ),
          IconButton(
            icon: const Icon(
              Icons.settings_outlined,
              size: 18,
              color: CursorTheme.textPrimary,
            ),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            tooltip: 'Ajustes',
          ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Anchos que NUNCA deben sumar más que el ancho real del body.
              // El overflow de ~38px venía de forzar mínimos (emulator 300 + chat 250)
              // aunque no cupieran: 280+8+300+250 = 838 > ventana ~800.
              final screenWidth = constraints.maxWidth;
              const dividerWidth = 6.0;
              const softMinChat = 220.0;
              const softMinCenter = 280.0;

              final sidebarWidth = _sidebarWidth.clamp(
                150.0,
                screenWidth * 0.45,
              );
              // Centro (Preview/Code) es Expanded: solo fijamos sidebar + chat.
              final fixedWidth = sidebarWidth + dividerWidth + dividerWidth;
              final remaining =
                  (screenWidth - fixedWidth).clamp(0.0, screenWidth);
              final maxChat =
                  (remaining - softMinCenter).clamp(0.0, remaining);
              final minChat = maxChat >= softMinChat ? softMinChat : 0.0;
              final finalChatWidth =
                  _chatPanelWidth.clamp(minChat, maxChat);

              return Row(
                children: [
                  // Usar el sidebar ya clampeado al ancho disponible
                  // (evita que un drag previo deje un ancho imposible)
          // Panel lateral izquierdo (Explorador)
          Container(
            width: sidebarWidth,
            decoration: BoxDecoration(
              color: CursorTheme.explorerBackground,
              border: Border(
                right: BorderSide(color: CursorTheme.border, width: 1),
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min, // ✅ FIX: Evitar altura infinita
                children: [
                  // Barra de herramientas (foto 2)
                  ExplorerToolbar(
                    selectedIndex: _sidebarView == 'ui_builder'
                        ? 0
                        : (_sidebarView == 'search' || _isSearchMode
                            ? 1
                            : (_sidebarView == 'git'
                                ? 2
                                : _selectedToolbarIndex)),
                    onItemSelected: (index) {
                      setState(() {
                        _selectedToolbarIndex = index;
                      });
                    },
                    onAction: (action) {
                      _handleToolbarAction(action);
                    },
                  ),
                  // UI Builder | Search | Git | Explorador
                  if (_sidebarView == 'ui_builder')
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            flex: _voryxelBlockIdOf(_selectedElement) != null
                                ? 3
                                : 1,
                            child: UiBuilderPanel(
                              enabled: _currentProjectPath != null,
                              hint: _currentProjectPath == null
                                  ? 'Abre un proyecto web (HTML) primero'
                                  : (_debugService.isRunning
                                      ? (_isUiBuilderContainer(_selectedElement)
                                          ? 'Contenedor seleccionado · suelta dentro'
                                          : 'Arrastra al Preview · clic para editar')
                                      : 'Al soltar se inicia el Preview (Run)'),
                            ),
                          ),
                          if (_voryxelBlockIdOf(_selectedElement) != null)
                            Expanded(
                              flex: 2,
                              child: UiBuilderPropertiesPanel(
                                key: ValueKey(
                                  _voryxelBlockIdOf(_selectedElement),
                                ),
                                element: _selectedElement!,
                                blockId: _voryxelBlockIdOf(_selectedElement)!,
                                projectPath: _currentProjectPath,
                                onApply: ({
                                  text,
                                  color,
                                  backgroundColor,
                                  padding,
                                  margin,
                                  width,
                                  height,
                                  fontSize,
                                  borderRadius,
                                  border,
                                  textAlign,
                                  href,
                                  src,
                                  placeholder,
                                }) {
                                  return _applyUiBuilderProps(
                                    blockId:
                                        _voryxelBlockIdOf(_selectedElement)!,
                                    text: text,
                                    color: color,
                                    backgroundColor: backgroundColor,
                                    padding: padding,
                                    margin: margin,
                                    width: width,
                                    height: height,
                                    fontSize: fontSize,
                                    borderRadius: borderRadius,
                                    border: border,
                                    textAlign: textAlign,
                                    href: href,
                                    src: src,
                                    placeholder: placeholder,
                                  );
                                },
                                onDelete: () {
                                  return _deleteUiBuilderBlock(
                                    _voryxelBlockIdOf(_selectedElement)!,
                                  );
                                },
                                onDuplicate: () {
                                  return _duplicateUiBuilderBlock(
                                    _voryxelBlockIdOf(_selectedElement)!,
                                  );
                                },
                                onMoveUp: () {
                                  return _moveUiBuilderBlock(
                                    _voryxelBlockIdOf(_selectedElement)!,
                                    -1,
                                  );
                                },
                                onMoveDown: () {
                                  return _moveUiBuilderBlock(
                                    _voryxelBlockIdOf(_selectedElement)!,
                                    1,
                                  );
                                },
                                onClearSelection: () {
                                  setState(() => _selectedElement = null);
                                  InspectorSelectionService()
                                      .clearSelection();
                                },
                              ),
                            ),
                        ],
                      ),
                    )
                  else if (_sidebarView == 'git')
                    Expanded(
                      child: GitScmPanel(
                        key: ValueKey('git_scm_$_currentProjectPath'),
                        projectPath: _currentProjectPath,
                        onOpenFile: (path) => _handleFileViewCode(path),
                        onOpenSettings: _showGitDialog,
                        onGenerateCommitMessage:
                            OpenAIService.suggestCommitMessage,
                      ),
                    )
                  else if (_sidebarView == 'search' || _isSearchMode)
                    Expanded(
                      child: GlobalSearchPanel(
                        key: ValueKey('global_search_$_currentProjectPath'),
                        projectPath: _currentProjectPath,
                        onSelectResult: _handleGlobalSearchResult,
                      ),
                    )
                  else if (_currentProjectPath != null)
                    Expanded(
                      child: ProjectExplorer(
                        key: ValueKey(
                          '${_currentProjectPath}_${_selectedToolbarIndex}',
                        ),
                        mode: 'explorer',
                        agentActivePath: _agentActivePath,
                        onFileSelected: (path) {
                          print('📁 Archivo seleccionado: $path');
                        },
                        onFileDoubleClick: (path) {
                          print('📁 Doble clic en: $path');
                          _handleFileViewCode(path);
                        },
                        onFileDelete: (path) {
                          // CRUD real lo hace ProjectExplorer; sync UI si el archivo abierto se borró.
                          if (_selectedFilePath == path) {
                            setState(() {
                              _selectedFilePath = null;
                              _selectedFileContent = null;
                            });
                          }
                        },
                        onFileViewCode: _handleFileViewCode,
                        onFileCopy: (_) {},
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
          ),
          // Divisor redimensionable entre explorador y contenido principal
          _buildVerticalResizeHandle(
            onDrag: (dx) {
              setState(() {
                _sidebarWidth += dx;
                final screenWidth = MediaQuery.of(context).size.width;
                const minForRest = 200.0 + 6.0 + 6.0;
                final maxSidebar =
                    (screenWidth - minForRest).clamp(150.0, 480.0);
                if (_sidebarWidth < 150) _sidebarWidth = 150;
                if (_sidebarWidth > maxSidebar) {
                  _sidebarWidth = maxSidebar;
                }
              });
            },
          ),
                  // Panel del medio: Preview/Code — Expanded para crecer al
                  // arrastrar la barra del chat (sin hueco muerto).
          if (_emulatorVisible)
                    Expanded(
                child: Container(
              decoration: BoxDecoration(
                color: CursorTheme.surface,
                border: Border(
                            right: BorderSide(
                              color: CursorTheme.border,
                              width: 1,
                            ),
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min, // ✅ FIX: Evitar altura infinita en web
                  children: [
                  // Pestañas Preview/Code
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: CursorTheme.background,
                      border: Border(
                                  bottom: BorderSide(
                                    color: CursorTheme.border,
                                    width: 1,
                                  ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                    _buildTab(
                                      0,
                                      'Preview',
                                      Icons.phone_android,
                                    ),
                          _buildTab(1, 'Code', Icons.code),
                          const SizedBox(width: 16),
                                    // Inspector (solo visible en Preview)
                          if (_selectedTab == 0)
                                      Builder(
                                        builder: (context) {
                                          final platform = _platformService
                                              .selectedPlatform
                                              .toLowerCase();
                                          final hasWebView =
                                              _debugService.appUrl != null &&
                                                  _debugService
                                                      .appUrl!.isNotEmpty;
                                          final canUseWebInspector =
                                              platform == 'web' || hasWebView;
                                          final hasVmService =
                                              _debugService.vmServiceUri !=
                                                      null &&
                                                  _debugService
                                                      .vmServiceUri!.isNotEmpty;

                                          return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                                'Inspector',
                                  style: TextStyle(
                                                  color:
                                                      CursorTheme.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                              if (canUseWebInspector)
                                                Tooltip(
                                                  message: _inspectorMode
                                                      ? 'Desactivar Inspector\nCon Inspector ON: el mouse selecciona elementos (la app no recibe clics)'
                                                      : 'Activar Inspector\nPasa el mouse y haz clic para señalar un elemento al agente',
                                                  child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _inspectorMode = !_inspectorMode;
                                      InspectorSelectionService()
                                          .setActive(_inspectorMode);
                                      if (!_inspectorMode) {
                                        _selectedElement = null;
                                        InspectorSelectionService().clear();
                                      }
                                    });
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 24,
                                    decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                      color: _inspectorMode 
                                                            ? CursorTheme
                                                                .primary
                                                            : CursorTheme
                                                                .surface
                                                                .withOpacity(
                                                                    0.5),
                                      border: Border.all(
                                        color: _inspectorMode 
                                                              ? CursorTheme
                                                                  .primary
                                                              : CursorTheme
                                                                  .border,
                                        width: 1,
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        AnimatedPositioned(
                                                            duration:
                                                                const Duration(
                                                              milliseconds: 200,
                                                            ),
                                                            curve:
                                                                Curves.easeInOut,
                                                            left: _inspectorMode
                                                                ? 22
                                                                : 2,
                                          top: 2,
                                          child: Container(
                                            width: 20,
                                            height: 20,
                                                              decoration:
                                                                  BoxDecoration(
                                                                color:
                                                                    Colors.white,
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                  10,
                                                                ),
                                              boxShadow: [
                                                BoxShadow(
                                                                    color: Colors
                                                                        .black
                                                                        .withOpacity(
                                                                          0.2,
                                                                        ),
                                                                    blurRadius:
                                                                        4,
                                                                    offset:
                                                                        const Offset(
                                                                      0,
                                                                      2,
                                                                    ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                                    ),
                                                  ),
                                                )
                                              else
                                                Tooltip(
                                                  message: hasVmService
                                                      ? 'Abrir Flutter DevTools (Inspector)'
                                                      : 'Inicia la app en modo Debug para habilitar el Inspector',
                                                  child: GestureDetector(
                                                    onTap: () async {
                                                      if (!hasVmService) {
                                                        AppToast.warning(
                                                          context,
                                                          'No se detectó VM Service. Ejecuta en modo Debug y espera a que la app inicie.',
                                                        );
                                                        return;
                                                      }

                                                      _debugService
                                                          .addDebugConsole(
                                                        '🧩 Abriendo DevTools Inspector...',
                                                      );
                                                      final url =
                                                          await DevToolsService
                                                              .openInspector(
                                                        vmServiceUri: _debugService
                                                            .vmServiceUri!,
                                                        onLog: _debugService
                                                            .addDebugConsole,
                                                      );
                                                      if (!mounted) return;
                                                      if (url == null) {
                                                        AppToast.error(
                                                          context,
                                                          'No se pudo abrir DevTools. Revisa el Debug Console.',
                                                        );
                                                      }
                                                    },
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 10,
                                                        vertical: 4,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        color: hasVmService
                                                            ? CursorTheme
                                                                .surface
                                                            : CursorTheme
                                                                .surface
                                                                .withOpacity(
                                                                    0.5),
                                                        border: Border.all(
                                                          color: hasVmService
                                                              ? CursorTheme
                                                                  .border
                                                              : CursorTheme
                                                                  .border
                                                                  .withOpacity(
                                                                    0.5,
                                                                  ),
                                                          width: 1,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .bug_report_outlined,
                                                            size: 14,
                                                            color: hasVmService
                                                                ? CursorTheme
                                                                    .textPrimary
                                                                : CursorTheme
                                                                    .textSecondary,
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Text(
                                                            'Abrir',
                                                            style: TextStyle(
                                                              color: hasVmService
                                                                  ? CursorTheme
                                                                      .textPrimary
                                                                  : CursorTheme
                                                                      .textSecondary,
                                                              fontSize: 11,
                                  ),
                                ),
                              ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                            ),
                          const SizedBox(width: 8),
                          // Selector de tamaño del emulador (solo visible en Preview)
                          if (_selectedTab == 0)
                            Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 4,
                                        ),
                              decoration: BoxDecoration(
                                color: CursorTheme.surface,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: CursorTheme.border,
                                            width: 1,
                                          ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                            // Botón de zoom out
                                            IconButton(
                                              icon: const Icon(
                                                Icons.remove,
                                                size: 14,
                                              ),
                                              color: CursorTheme.textSecondary,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 24,
                                                minHeight: 24,
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  final next =
                                                      ((_emulatorScale - 0.1) *
                                                              10)
                                                          .round() /
                                                      10;
                                                  _emulatorScale =
                                                      next.clamp(0.5, 2.0);
                                                });
                                              },
                                              tooltip: 'Reducir tamaño',
                                            ),
                                            // Indicador de porcentaje
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
                                              child: Text(
                                                '${(_emulatorScale * 100).round()}%',
                                    style: TextStyle(
                                                  color:
                                                      CursorTheme.textPrimary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                              ),
                                            ),
                                            // Botón de zoom in
                                            IconButton(
                                              icon: const Icon(
                                                Icons.add,
                                                size: 14,
                                              ),
                                              color: CursorTheme.textSecondary,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 24,
                                                minHeight: 24,
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  final next =
                                                      ((_emulatorScale + 0.1) *
                                                              10)
                                                          .round() /
                                                      10;
                                                  _emulatorScale =
                                                      next.clamp(0.5, 2.0);
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
                        // Botón fijo a la derecha: probar la web en el navegador
                        if (_selectedTab == 0 &&
                            _debugService.appUrl != null &&
                            _debugService.appUrl!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Tooltip(
                              message:
                                  'Abrir la Preview en el navegador del sistema',
                              child: Material(
                                color: CursorTheme.surface,
                                borderRadius: BorderRadius.circular(6),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () async {
                                    final url = _debugService.appUrl;
                                    if (url == null || url.isEmpty) return;
                                    final uri = Uri.tryParse(url);
                                    if (uri == null) return;
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(
                                        uri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    }
                                  },
                                  child: Container(
                                    height: 28,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: CursorTheme.border,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.open_in_browser,
                                          size: 14,
                                          color: CursorTheme.primary,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Navegador',
                                          style: TextStyle(
                                            color: CursorTheme.textPrimary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Banner global: siempre visible (Preview o Code) mientras el
                  // agente trabaja — archivo, línea, o "Compilando…".
                  if (_agentActivity.isBusy)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      color: const Color(0xFF1A3A5C),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: CursorTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _agentActivity.bannerText,
                              style: const TextStyle(
                                color: CursorTheme.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_agentActivity.hasFileTarget && _selectedTab != 1)
                            TextButton(
                              onPressed: () {
                                final path = _agentActivity.activePath ??
                                    _selectedFilePath;
                                if (path != null && path.isNotEmpty) {
                                  unawaited(
                                    _openFileFromAgentLive(
                                      path,
                                      line: _agentActivity.focusLine,
                                      reveal: true,
                                    ),
                                  );
                                } else {
                                  setState(() => _selectedTab = 1);
                                }
                              },
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: CursorTheme.primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Ver en Code',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ),
                  // Contenido según la pestaña seleccionada
                  Expanded(
                              child: ClipRect(
                    child: _buildTabContent(),
                              ),
                  ),
                ],
                ),
              ),
            ),
                    ),
                  // Logo central cuando Preview/Code está oculto
                  if (!_emulatorVisible)
                    Expanded(
                      child: Container(
                        color: CursorTheme.background,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const VoryxelBrandLogo(
                                iconSize: 96,
                                fontSize: 32,
                              ),
                              const SizedBox(height: 40),
                              Text(
                                'Activa el emulador para ver la aplicación',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: CursorTheme.textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Divisor: arrastrar ←→ ajusta el ancho del chat (Code/Preview
                  // crece automáticamente al ser Expanded).
          _buildVerticalResizeHandle(
            onDrag: (dx) {
              setState(() {
                _chatPanelWidth -= dx;
                final screenWidth = MediaQuery.of(context).size.width;
                const dividerWidth = 6.0;
                const softMinChat = 220.0;
                const softMinCenter = 280.0;
                final fixedWidth =
                    _sidebarWidth + dividerWidth + dividerWidth;
                final remaining =
                    (screenWidth - fixedWidth).clamp(0.0, screenWidth);
                final maxChat =
                    (remaining - softMinCenter).clamp(0.0, remaining);
                final minChat =
                    maxChat >= softMinChat ? softMinChat : 0.0;
                if (_chatPanelWidth < minChat) {
                  _chatPanelWidth = minChat;
                }
                if (_chatPanelWidth > maxChat) {
                  _chatPanelWidth = maxChat;
                }
              });
            },
          ),
                  // Panel de chat con pestañas - ancho fijo y movible
                  // ✅ FIX: Usar SizedBox con ancho calculado para permitir resize
                  SizedBox(
                    width: finalChatWidth,
                    child: Column(
                      children: [
                        // Barra de pestañas de chat - estilo marcadores/portafolio compacto
                        Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: CursorTheme.explorerBackground,
                            border: Border(
                              bottom: BorderSide(
                                color: CursorTheme.border,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // Pestañas de chat con scroll horizontal - estilo marcadores/portafolio
          Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: _chats.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final chat = entry.value;
                                      final isActive = chat.id == _activeChatId;
                                      
                                      // Colores diferentes para cada pestaña (estilo portafolio)
                                      final colors = [
                                        [const Color(0xFF6366F1), const Color(0xFF818CF8)], // Indigo
                                        [const Color(0xFF10B981), const Color(0xFF34D399)], // Emerald
                                        [const Color(0xFFF59E0B), const Color(0xFFFBBF24)], // Amber
                                        [const Color(0xFFEF4444), const Color(0xFFF87171)], // Red
                                        [const Color(0xFF8B5CF6), const Color(0xFFA78BFA)], // Purple
                                        [const Color(0xFF06B6D4), const Color(0xFF22D3EE)], // Cyan
                                        [const Color(0xFFEC4899), const Color(0xFFF472B6)], // Pink
                                        [const Color(0xFF14B8A6), const Color(0xFF2DD4BF)], // Teal
                                      ];
                                      final colorPair = colors[index % colors.length];
                                      final primaryColor = colorPair[0];
                                      
                                      return Tooltip(
                                        message: chat.name,
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
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
                                              height: isActive ? 36 : 32,
                                              margin: EdgeInsets.only(
                                                right: 4,
                                                top: isActive ? 0 : 4,
                                              ),
                                              constraints: const BoxConstraints(
                                                minWidth: 90,
                                                maxWidth: 160,
                                              ),
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: isActive ? 6 : 5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isActive
                                                    ? CursorTheme.surface
                                                    : CursorTheme.explorerBackground,
                                                borderRadius: const BorderRadius.only(
                                                  topLeft: Radius.circular(8),
                                                  topRight: Radius.circular(8),
                                                ),
                                              ),
                                              child: Stack(
                                                children: [
                                                  // Barra superior de color
                                                  if (isActive)
                                                    Positioned(
                                                      top: 0,
                                                      left: 0,
                                                      right: 0,
                                                      child: Container(
                                                        height: 3,
                                                        decoration: BoxDecoration(
                                                          color: primaryColor,
                                                          borderRadius: const BorderRadius.only(
                                                            topLeft: Radius.circular(8),
                                                            topRight: Radius.circular(8),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  // Contenido de la pestaña
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      // Icono con color único por pestaña
                                                      Container(
                                                        padding: const EdgeInsets.all(3),
                                                        decoration: BoxDecoration(
                                                          color: isActive
                                                              ? primaryColor.withOpacity(0.15)
                                                              : primaryColor.withOpacity(0.08),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Icon(
                                                          isActive
                                                              ? Icons.smart_toy
                                                              : Icons.smart_toy_outlined,
                                                          size: 14,
                                                          color: isActive
                                                              ? primaryColor
                                                              : primaryColor.withOpacity(0.6),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Flexible(
                                                        child: Text(
                                                          chat.name,
                                                          style: TextStyle(
                                                            color: isActive
                                                                ? CursorTheme.textPrimary
                                                                : CursorTheme.textSecondary,
                                                            fontSize: 11,
                                                            fontWeight: isActive
                                                                ? FontWeight.w600
                                                                : FontWeight.w500,
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
                                                                size: 12,
                                                                color: isActive
                                                                    ? CursorTheme.textSecondary
                                                                    : CursorTheme.textSecondary.withOpacity(0.4),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                              // Botón para crear nuevo chat - compacto
                              Tooltip(
                                message: 'Nuevo Chat',
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _createNewChat,
                                    child: Container(
                                      height: 36,
                                      width: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Icon(
                                        Icons.add,
                                        size: 16,
                                        color: CursorTheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Contenido del chat activo
                        Expanded(
                          child:
                              _activeChatId != null &&
                                  _chats.isNotEmpty &&
                                  _currentProjectPath != null
                ? ChatScreen(
                    key: _chatScreenKeys.putIfAbsent(
                      _activeChatId!,
                      () => GlobalKey(),
                    ),
                    chatId: _activeChatId!,
                    projectPath: _currentProjectPath,
                    activeFilePath: _selectedFilePath,
                    activeFileContent: _selectedFileContent,
                    onViewCode: _openCodeEditorFromErrorDialog,
                    onAgentOpenFile: _openFileFromAgentLive,
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
                                          Navigator.of(
                                            context,
                                          ).pushAndRemoveUntil(
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const WelcomeScreen(),
                                            ),
                              (route) => false,
                            );
                          },
                          icon: const Icon(Icons.home, size: 16),
                          label: const Text('Volver a inicio'),
                          style: TextButton.styleFrom(
                                          foregroundColor:
                                              CursorTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ), // ✅ Cierre de Center (del ternario)
                        ), // ✅ Cierre de Expanded (contenido del chat)
                      ], // ✅ Cierre de children del Column (del chat)
                    ), // ✅ Cierre de Column (del chat)
                  ), // ✅ Cierre de SizedBox (panel de chat)
                ], // ✅ Cierre de children del Row principal
              );
            },
        ),
      ),
      // Barra de Run and Debug flotante (visible en toda la app)
      RunDebugToolbar(
          onRun: _handleRun,
          onDebug: _handleDebug,
          onStop: _handleStop,
          onRestart: _handleRestart,
          onHotReload: _handleHotReload,
          onHotRestart: _handleHotRestart,
          onPlatformChanged: (platform) {
          print(
            '🔧 Plataforma seleccionada desde MultiChatScreen: $platform',
          );
            
            // Detener cualquier ejecución en curso antes de cambiar de plataforma
            final state = _getActiveChatScreenState();
            if (state != null) {
              try {
                final isRunning = (state as dynamic).isRunning ?? false;
                if (isRunning) {
                print(
                  '⚠️ Deteniendo ejecución antes de cambiar de plataforma',
                );
                  (state as dynamic).handleStop();
                }
              } catch (e) {
                print('⚠️ Error al detener ejecución: $e');
              }
            }
            
            // Actualizar plataforma en el servicio (única forma desde la UI)
            _platformService.setPlatform(platform);

            // Limpiar Preview al cambiar de target (Android/iOS Preview
            // también usan URL de web-server; se regenera en el próximo Run).
            _debugService.setAppUrl(null);
          },
          selectedPlatform: _getSelectedPlatform(),
          isRunning: _getIsRunning(),
          isDebugging: _getIsDebugging(),
        ),
      ],
        ),
      ),
    );
  }
}

// ✅ ELIMINADOS: Diálogos no funcionales (_GitDialog, _SupabaseDialog, _FirebaseDialog)
// Solo mostraban "próximamente disponible" sin funcionalidad real
