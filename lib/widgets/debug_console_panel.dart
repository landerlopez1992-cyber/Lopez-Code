import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/problem_item.dart';
import '../services/debug_console_service.dart';
import 'cursor_theme.dart';
import 'integrated_terminal_panel.dart';
import 'light_ray_progress_bar.dart';

/// Panel inferior con tabs para Problems, Output, Debug Console y Terminal
/// Similar a Cursor IDE - muestra consola, output, problemas y shell interactiva
class DebugConsolePanel extends StatefulWidget {
  final double? height;
  final Function(double)? onHeightChanged;
  /// Problemas estructurados de `flutter analyze` (preferido).
  final List<ProblemItem>? problemItems;
  /// Compatibilidad legacy (strings); se usan solo si [problemItems] es null.
  final List<String>? problems;
  final List<String>? output;
  final List<String>? debugConsole;
  final Function(String message)? onSendToChat; // Callback para enviar errores al chat
  /// Al hacer click en un problema, abrir archivo en el editor en esa línea.
  final void Function(ProblemItem problem)? onProblemTap;
  final VoidCallback? onRefreshAnalyze;
  /// CWD de la Terminal integrada (ruta del proyecto abierto).
  final String? projectPath;

  const DebugConsolePanel({
    super.key,
    this.height,
    this.onHeightChanged,
    this.problemItems,
    this.problems,
    this.output,
    this.debugConsole,
    this.onSendToChat,
    this.onProblemTap,
    this.onRefreshAnalyze,
    this.projectPath,
  });

  @override
  State<DebugConsolePanel> createState() => _DebugConsolePanelState();
}

class _DebugConsolePanelState extends State<DebugConsolePanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTabIndex = 0;
  // Separate ScrollControllers for each tab to avoid "attached to multiple ScrollPosition" error
  final ScrollController _problemsScrollController = ScrollController();
  final ScrollController _outputScrollController = ScrollController();
  final ScrollController _debugConsoleScrollController = ScrollController();
  final TextEditingController _filterController = TextEditingController();
  bool _filterVisible = false;
  final GlobalKey<IntegratedTerminalPanelState> _terminalKey =
      GlobalKey<IntegratedTerminalPanelState>();

  final DebugConsoleService _debugService = DebugConsoleService();

  /// Seguir el final del log en tiempo real (se pausa si el usuario sube).
  bool _followOutput = true;
  bool _followDebug = true;
  int _lastOutputLen = 0;
  int _lastDebugLen = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedTabIndex = _tabController.index;
      });
    });
    _outputScrollController.addListener(_onOutputUserScroll);
    _debugConsoleScrollController.addListener(_onDebugUserScroll);
    _debugService.addListener(_onDebugServiceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPreferredTab();
      _scrollLogsToEnd(force: true);
    });
  }

  void _onOutputUserScroll() {
    if (!_outputScrollController.hasClients) return;
    final pos = _outputScrollController.position;
    _followOutput = pos.maxScrollExtent - pos.pixels < 48;
  }

  void _onDebugUserScroll() {
    if (!_debugConsoleScrollController.hasClients) return;
    final pos = _debugConsoleScrollController.position;
    _followDebug = pos.maxScrollExtent - pos.pixels < 48;
  }

  void _scrollLogsToEnd({bool force = false}) {
    if (force || _followOutput) {
      _scrollControllerToEnd(_outputScrollController);
    }
    if (force || _followDebug) {
      _scrollControllerToEnd(_debugConsoleScrollController);
    }
  }

  void _scrollControllerToEnd(ScrollController controller) {
    if (!controller.hasClients) return;
    try {
      final target = controller.position.maxScrollExtent;
      if (target <= 0) return;
      controller.jumpTo(target);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !controller.hasClients) return;
        final t2 = controller.position.maxScrollExtent;
        if (t2 > controller.position.pixels) {
          controller.jumpTo(t2);
        }
      });
    } catch (_) {}
  }

  void _onDebugServiceChanged() {
    if (!mounted) return;
    final outLen = widget.output?.length ?? _debugService.output.length;
    final dbgLen =
        widget.debugConsole?.length ?? _debugService.debugConsole.length;
    final outputGrew = outLen > _lastOutputLen;
    final debugGrew = dbgLen > _lastDebugLen;
    _lastOutputLen = outLen;
    _lastDebugLen = dbgLen;

    setState(() {}); // progreso / status / logs
    _syncPreferredTab();

    if (outputGrew || debugGrew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (outputGrew && _followOutput) {
          _scrollControllerToEnd(_outputScrollController);
        }
        if (debugGrew && _followDebug) {
          _scrollControllerToEnd(_debugConsoleScrollController);
        }
      });
    }
  }

  bool get _showCompilationStrip {
    final progress = _debugService.compilationProgress;
    final status = _debugService.compilationStatus;
    final statusLower = status.toLowerCase();
    final hasError = status.contains('❌') ||
        statusLower.contains('error') ||
        statusLower.contains('falló') ||
        statusLower.contains('fallida');
    if (hasError) return false;
    if (progress > 0.0 && progress < 1.0) return true;
    if (_debugService.isRunning && progress < 1.0 && status.isNotEmpty) {
      return true;
    }
    // Fases de build sin URL lista todavía
    if (status.isNotEmpty &&
        progress < 1.0 &&
        (statusLower.contains('instal') ||
            statusLower.contains('compil') ||
            statusLower.contains('lanzand') ||
            statusLower.contains('resolv') ||
            statusLower.contains('descarg') ||
            statusLower.contains('building') ||
            statusLower.contains('running'))) {
      return true;
    }
    return false;
  }

  void _syncPreferredTab() {
    if (!mounted) return;
    final preferred = _debugService.preferredConsoleTab.clamp(0, 3);
    if (_tabController.index != preferred) {
      _tabController.animateTo(preferred);
    }
  }

  @override
  void dispose() {
    _debugService.removeListener(_onDebugServiceChanged);
    _outputScrollController.removeListener(_onOutputUserScroll);
    _debugConsoleScrollController.removeListener(_onDebugUserScroll);
    _tabController.dispose();
    _problemsScrollController.dispose();
    _outputScrollController.dispose();
    _debugConsoleScrollController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DebugConsolePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final outLen = widget.output?.length ?? 0;
    final dbgLen = widget.debugConsole?.length ?? 0;
    final oldOut = oldWidget.output?.length ?? 0;
    final oldDbg = oldWidget.debugConsole?.length ?? 0;
    if (outLen > oldOut || dbgLen > oldDbg) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (outLen > oldOut && _followOutput) {
          _scrollControllerToEnd(_outputScrollController);
        }
        if (dbgLen > oldDbg && _followDebug) {
          _scrollControllerToEnd(_debugConsoleScrollController);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.height ?? 200.0;
    final isVertical = height == double.infinity;

    return Container(
      height: isVertical ? null : height,
      constraints: isVertical ? const BoxConstraints.expand() : null,
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        border: isVertical
            ? Border(
                right: BorderSide(
                  color: CursorTheme.border,
                  width: 1,
                ),
              )
            : Border(
                top: BorderSide(
                  color: CursorTheme.border,
                  width: 1,
                ),
              ),
      ),
      child: Column(
        children: [
          // Barra redimensionable horizontal (solo cuando está en modo horizontal)
          if (!isVertical)
            GestureDetector(
              onVerticalDragUpdate: (details) {
                if (widget.onHeightChanged != null) {
                  final newHeight = height - details.delta.dy;
                  // Limitar altura entre 100 y 600 píxeles
                  if (newHeight >= 100 && newHeight <= 600) {
                    widget.onHeightChanged!(newHeight);
                  }
                }
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: _showCompilationStrip
                    // Durante build: handle fino + franja de progreso con rayos
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 3,
                            color: const Color(0xFFE8A838).withValues(alpha: 0.45),
                          ),
                          CompilationProgressStrip(
                            progress: _debugService.compilationProgress,
                            status: _debugService.compilationStatus,
                            visible: true,
                          ),
                        ],
                      )
                    : Container(
                        height: 4,
                        color: CursorTheme.border,
                        child: Center(
                          child: Container(
                            height: 1,
                            color: CursorTheme.textDisabled,
                          ),
                        ),
                      ),
              ),
            ),
          // En layout vertical no hay handle: mostrar franja de progreso igual
          if (isVertical && _showCompilationStrip)
            CompilationProgressStrip(
              progress: _debugService.compilationProgress,
              status: _debugService.compilationStatus,
              visible: true,
            ),
          // Header con tabs
          _buildHeader(),

          // Filtro de búsqueda (Problems / Output / Debug Console)
          if (_filterVisible && _selectedTabIndex != 3) _buildFilter(),

          // Contenido de tabs
          Expanded(
            child: _buildTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
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
          // Tabs
          Expanded(
            child: TabBar(
              controller: _tabController,
              indicatorColor: CursorTheme.primary,
              labelColor: CursorTheme.textPrimary,
              unselectedLabelColor: CursorTheme.textSecondary,
              labelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 11,
              ),
              isScrollable: false,
              tabs: [
                Tooltip(
                  message: 'Errores/warnings de flutter analyze',
                  child: _buildTab(
                    'Problems',
                    _resolvedProblemItems.length,
                    Colors.red,
                  ),
                ),
                const Tooltip(
                  message: 'Log crudo completo: flutter tool, build, dependencias',
                  child: Tab(text: 'Output'),
                ),
                const Tooltip(
                  message:
                      'Trazas en vivo de la app: print, excepciones, carga, hot reload',
                  child: Tab(text: 'Debug Console'),
                ),
                const Tooltip(
                  message: 'Shell interactiva (zsh) en el proyecto',
                  child: Tab(text: 'Terminal'),
                ),
              ],
            ),
          ),
          
          // Botones de acción (más pequeños para evitar overflow)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Botón "Enviar al Chat IA" - errores o contenido de la pestaña activa
              if (_selectedTabIndex != 3 &&
                  widget.onSendToChat != null &&
                  (_resolvedProblemItems.isNotEmpty ||
                      _activeTabHasContent ||
                      (widget.debugConsole?.any((line) =>
                              line.contains('❌') ||
                              line.contains('Compilación fallida') ||
                              line.toLowerCase().contains('error') ||
                              line.toLowerCase().contains('failed') ||
                              line.toLowerCase().contains('exception')) ??
                          false)))
                IconButton(
                  icon: const Icon(Icons.smart_toy, size: 14),
                  color: CursorTheme.primary,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: _sendActiveTabToChat,
                  tooltip: _selectedTabIndex == 0
                      ? 'Precargar errores en el Chat IA'
                      : 'Enviar ${_selectedTabIndex == 1 ? 'Output' : 'Debug Console'} al Chat IA',
                ),

              // Copiar pestaña activa al portapapeles (pegar en el agente)
              if (_selectedTabIndex != 3 && _activeTabHasContent)
                IconButton(
                  icon: const Icon(Icons.content_copy, size: 14),
                  color: CursorTheme.textSecondary,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: _copyActiveTabToClipboard,
                  tooltip: 'Copiar pestaña actual',
                ),

              if (widget.onRefreshAnalyze != null)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 14),
                  color: CursorTheme.textSecondary,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: widget.onRefreshAnalyze,
                  tooltip: 'flutter analyze',
                ),
              
              // Botón de búsqueda / filtro (no aplica a Terminal)
              if (_selectedTabIndex != 3)
                IconButton(
                  icon: const Icon(Icons.search, size: 14),
                  color: _filterVisible
                      ? CursorTheme.primary
                      : CursorTheme.textSecondary,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    setState(() {
                      _filterVisible = !_filterVisible;
                      if (!_filterVisible) {
                        _filterController.clear();
                      }
                    });
                  },
                  tooltip: _filterVisible ? 'Ocultar filtro' : 'Buscar / filtrar',
                ),

              if (_selectedTabIndex != 3)
                IconButton(
                  icon: const Icon(Icons.filter_list, size: 14),
                  color: _filterController.text.isNotEmpty
                      ? CursorTheme.primary
                      : CursorTheme.textSecondary,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    setState(() {
                      _filterVisible = true;
                    });
                  },
                  tooltip: 'Mostrar filtro',
                ),

              // Limpiar pestaña activa
              IconButton(
                icon: const Icon(Icons.clear_all, size: 14),
                color: CursorTheme.textSecondary,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _clearActiveTab,
                tooltip: 'Limpiar pestaña actual',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int count, Color badgeColor) {
    return Tab(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: badgeColor.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _clearActiveTab() {
    switch (_tabController.index) {
      case 0:
        _debugService.clearProblems();
        break;
      case 1:
        _debugService.clearOutput();
        break;
      case 2:
        _debugService.clearDebugConsole();
        break;
      case 3:
        _terminalKey.currentState?.clearScreen();
        break;
    }
    setState(() {});
  }

  bool get _activeTabHasContent => _activeTabLines.isNotEmpty;

  List<String> get _activeTabLines {
    final filter = _filterController.text.toLowerCase();
    List<String> lines;
    switch (_tabController.index) {
      case 0:
        lines = _resolvedProblemItems.map((p) => p.toString()).toList();
        if (lines.isEmpty && widget.problems != null) {
          lines = List<String>.from(widget.problems!);
        }
        break;
      case 1:
        lines = List<String>.from(widget.output ?? []);
        break;
      case 2:
        lines = List<String>.from(widget.debugConsole ?? []);
        break;
      default:
        lines = const [];
    }
    if (filter.isEmpty) return lines;
    return lines.where((l) => l.toLowerCase().contains(filter)).toList();
  }

  Future<void> _copyActiveTabToClipboard() async {
    final lines = _activeTabLines;
    if (lines.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copiado (${lines.length} líneas). Pégalo en el Chat del agente.',
          style: const TextStyle(fontSize: 13),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: CursorTheme.surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _sendActiveTabToChat() {
    if (widget.onSendToChat == null) return;
    // En Problems → flujo de errores detallado; en Output/Console → texto completo
    if (_tabController.index == 0) {
      _sendErrorsToChat();
      return;
    }
    final lines = _activeTabLines;
    if (lines.isEmpty) return;
    final tabName = _tabController.index == 1 ? 'Output' : 'Debug Console';
    final buffer = StringBuffer()
      ..writeln('📎 **$tabName del proyecto** (${lines.length} líneas)')
      ..writeln()
      ..writeln('```')
      ..writeln(lines.join('\n'))
      ..writeln('```')
      ..writeln()
      ..writeln('Analiza este log y dime la causa y cómo corregirlo.');
    widget.onSendToChat!(buffer.toString());
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: CursorTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: CursorTheme.border, width: 1),
        ),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: CursorTheme.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$tabName precargado',
                style: TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'El contenido de $tabName está en el Chat. Presiona Enviar para que el agente lo analice.',
          style: TextStyle(
            color: CursorTheme.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Entendido', style: TextStyle(color: CursorTheme.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildFilter() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: CursorTheme.background,
        border: Border(
          bottom: BorderSide(
            color: CursorTheme.border,
            width: 1,
          ),
        ),
      ),
      child: TextField(
        controller: _filterController,
        autofocus: true,
        style: const TextStyle(
          fontSize: 12,
          color: CursorTheme.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Filtrar texto en la pestaña actual…',
          hintStyle: const TextStyle(
            fontSize: 12,
            color: CursorTheme.textSecondary,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          prefixIcon: const Icon(
            Icons.search,
            size: 16,
            color: CursorTheme.textSecondary,
          ),
          suffixIcon: _filterController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  color: CursorTheme.textSecondary,
                  onPressed: () {
                    _filterController.clear();
                    setState(() {});
                  },
                )
              : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        // Problems Tab
        _buildProblemsTab(),
        
        // Output Tab
        _buildOutputTab(),
        
        // Debug Console Tab
        _buildDebugConsoleTab(),

        // Terminal interactiva (PTY)
        IntegratedTerminalPanel(
          key: _terminalKey,
          workingDirectory: widget.projectPath,
        ),
      ],
    );
  }

  List<ProblemItem> get _resolvedProblemItems {
    if (widget.problemItems != null) {
      return widget.problemItems!;
    }
    // Legacy: strings → ProblemItem mínimo para render/click
    return (widget.problems ?? [])
        .map(
          (p) => ProblemItem(
            filePath: '',
            line: 0,
            column: 0,
            severity: p.toLowerCase().contains('error')
                ? ProblemSeverity.error
                : p.toLowerCase().contains('warning')
                    ? ProblemSeverity.warning
                    : ProblemSeverity.info,
            message: p,
          ),
        )
        .toList();
  }

  Widget _buildProblemsTab() {
    final problems = _resolvedProblemItems;
    final filter = _filterController.text.toLowerCase();

    final filteredProblems = filter.isEmpty
        ? problems
        : problems
            .where((p) => p.toString().toLowerCase().contains(filter))
            .toList();

    if (filteredProblems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sin problemas de análisis',
              style: TextStyle(
                color: CursorTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Solo errores/warnings de flutter analyze (no el log de run)',
              style: TextStyle(
                color: CursorTheme.textDisabled,
                fontSize: 10,
              ),
            ),
            if (widget.onRefreshAnalyze != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: widget.onRefreshAnalyze,
                icon: const Icon(Icons.analytics_outlined, size: 14),
                label: const Text('Run flutter analyze', style: TextStyle(fontSize: 11)),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _problemsScrollController,
      itemCount: filteredProblems.length,
      itemBuilder: (context, index) {
        final problem = filteredProblems[index];
        final isError = problem.severity == ProblemSeverity.error;
        final isWarning = problem.severity == ProblemSeverity.warning;
        final canOpen = problem.filePath.isNotEmpty && widget.onProblemTap != null;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: canOpen ? () => widget.onProblemTap!(problem) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: index % 2 == 0
                    ? CursorTheme.background
                    : CursorTheme.surface,
                border: Border(
                  left: BorderSide(
                    color: isError
                        ? Colors.red
                        : isWarning
                            ? Colors.orange
                            : Colors.blueGrey,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isError
                        ? Icons.error
                        : isWarning
                            ? Icons.warning
                            : Icons.info,
                    size: 16,
                    color: isError
                        ? Colors.red
                        : isWarning
                            ? Colors.orange
                            : CursorTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          problem.message,
                          style: TextStyle(
                            color: CursorTheme.textPrimary,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (problem.filePath.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${problem.filePath}:${problem.line}:${problem.column}'
                            '${problem.code.isNotEmpty ? ' • ${problem.code}' : ''}',
                            style: TextStyle(
                              color: canOpen
                                  ? CursorTheme.primary
                                  : CursorTheme.textSecondary,
                              fontSize: 11,
                              fontFamily: 'monospace',
                              decoration: canOpen
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (canOpen)
                    Icon(
                      Icons.open_in_new,
                      size: 12,
                      color: CursorTheme.textSecondary,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOutputTab() {
    final filter = _filterController.text.toLowerCase();
    final output = widget.output ?? [];
    final filteredOutput = filter.isEmpty
        ? output
        : output.where((o) => o.toLowerCase().contains(filter)).toList();

    if (filteredOutput.isEmpty) {
      return Container(
        color: CursorTheme.codeBackground,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sin output',
              style: TextStyle(color: CursorTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Log crudo del toolchain (pub get, compile, flutter run)',
              style: TextStyle(color: CursorTheme.textDisabled, fontSize: 10),
            ),
          ],
        ),
      );
    }

    // Un solo SelectableText → se puede seleccionar el stack trace completo
    return Container(
      color: CursorTheme.codeBackground,
      child: SingleChildScrollView(
        controller: _outputScrollController,
        padding: const EdgeInsets.all(8),
        child: SelectableText(
          filteredOutput.join('\n'),
          style: TextStyle(
            color: CursorTheme.textPrimary,
            fontSize: 12,
            fontFamily: 'monospace',
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildDebugConsoleTab() {
    final filter = _filterController.text.toLowerCase();
    final console = widget.debugConsole ?? [];
    final filteredConsole = filter.isEmpty
        ? console
        : console.where((c) => c.toLowerCase().contains(filter)).toList();

    if (filteredConsole.isEmpty) {
      return Container(
        color: CursorTheme.codeBackground,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sin trazas aún',
              style: TextStyle(color: CursorTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Aquí verás print/debugPrint, excepciones y carga en vivo de la app',
              style: TextStyle(color: CursorTheme.textDisabled, fontSize: 10),
            ),
          ],
        ),
      );
    }

    return Container(
      color: CursorTheme.codeBackground,
      child: SingleChildScrollView(
        controller: _debugConsoleScrollController,
        padding: const EdgeInsets.all(8),
        child: SelectableText(
          filteredConsole.join('\n'),
          style: TextStyle(
            color: CursorTheme.textPrimary,
            fontSize: 12,
            fontFamily: 'monospace',
            height: 1.5,
          ),
        ),
      ),
    );
  }

  /// Precarga los errores en el chat (no envía automáticamente)
  void _sendErrorsToChat() {
    if (widget.onSendToChat == null) return;

    // Recopilar todos los errores
    final problemItems = _resolvedProblemItems;
    final problems = problemItems.map((p) => p.toString()).toList();
    final debugLines = widget.debugConsole ?? [];
    final outputLines = widget.output ?? [];

    // Filtrar mensajes informativos que NO son errores
    final informationalPatterns = [
      'changing current working directory',
      'no devices found yet',
      'checking for wireless devices',
      'the following devices were found',
      'flutter run key commands',
      'an observatory debugger',
      'syncing files',
      'waiting for',
      'launching',
      'running',
      'building',
      'compiling',
      'assembling',
      'downloading',
      'resolving dependencies',
      // NO filtrar mensajes sobre dispositivos disponibles - estos son importantes
      // 'dispositivos disponibles', // COMENTADO - necesitamos esta info
    ];

    // Filtrar líneas con errores REALES - excluir mensajes informativos
    final errorLines = debugLines.where((line) {
      final lowerLine = line.toLowerCase();
      
      // Excluir mensajes informativos
      if (informationalPatterns.any((pattern) => lowerLine.contains(pattern))) {
        return false;
      }
      
      // Incluir solo líneas que son errores reales
      return line.contains('❌') || 
        line.contains('Compilación fallida') ||
        (lowerLine.contains('error') && !lowerLine.contains('no error')) ||
        (lowerLine.contains('failed') && !lowerLine.contains('no devices found')) ||
        lowerLine.contains('exception') ||
        (lowerLine.contains('warning') && (lowerLine.contains('undefined') || lowerLine.contains('missing'))) ||
        lowerLine.contains('undefined name') ||
        lowerLine.contains('undefined class') ||
        lowerLine.contains('undefined method') ||
        lowerLine.contains('undefined getter') ||
        lowerLine.contains('missing') ||
        (lowerLine.contains('cannot') && (lowerLine.contains('find') || lowerLine.contains('resolve'))) ||
        (lowerLine.contains('not found') && !lowerLine.contains('devices')) ||
        // Errores de compilación de Dart/Flutter
        RegExp(r'\.dart:\d+:\d+:\s*(error|warning):').hasMatch(line) ||
        // Errores de sintaxis
        lowerLine.contains('syntax error') ||
        lowerLine.contains('expected') ||
        lowerLine.contains('unexpected');
    }).toList();

    // También buscar errores en output - filtrar mensajes informativos
    final outputErrors = outputLines.where((line) {
      final lowerLine = line.toLowerCase();
      
      // Excluir mensajes informativos
      if (informationalPatterns.any((pattern) => lowerLine.contains(pattern))) {
        return false;
      }
      
      // Incluir solo errores reales
      return (lowerLine.contains('error') && !lowerLine.contains('no error')) ||
        (lowerLine.contains('failed') && !lowerLine.contains('no devices found')) ||
        lowerLine.contains('exception') ||
        (lowerLine.contains('warning') && (lowerLine.contains('undefined') || lowerLine.contains('missing'))) ||
        RegExp(r'\.dart:\d+:\d+:\s*(error|warning):').hasMatch(line);
    }).toList();

    // Construir mensaje DETALLADO para el chat - estilo Cursor IDE
    final StringBuffer message = StringBuffer();
    message.writeln('🔴 **ANÁLISIS DE ERRORES DE COMPILACIÓN**\n');
    message.writeln('La compilación del proyecto ha fallado. A continuación se muestran los errores completos:\n');
    
    // Incluir información sobre dispositivos detectados si está disponible
    final deviceInfo = debugLines.where((line) => 
      line.contains('Dispositivos disponibles') || 
      line.contains('dispositivo') ||
      line.contains('device')
    ).toList();
    
    if (deviceInfo.isNotEmpty) {
      message.writeln('## 📱 INFORMACIÓN DE DISPOSITIVOS:');
      message.writeln('```');
      for (var info in deviceInfo) {
        message.writeln(info);
      }
      message.writeln('```');
      message.writeln();
    }
    
    // Priorizar problemas detectados (estos son los errores reales parseados)
    if (problems.isNotEmpty) {
      message.writeln('## 📋 ERRORES DE COMPILACIÓN (${problems.length}):');
      message.writeln('```');
      for (var problem in problems) {
        message.writeln(problem);
      }
      message.writeln('```');
      message.writeln();
    }

    // Incluir errores del Debug Console (solo errores reales, no mensajes informativos)
    if (errorLines.isNotEmpty) {
      message.writeln('## 🔍 ERRORES EN DEBUG CONSOLE:');
      message.writeln('```');
      // Incluir contexto alrededor de los errores (5 líneas antes, 10 después)
      final errorIndices = <int>[];
      for (int i = 0; i < debugLines.length; i++) {
        if (errorLines.contains(debugLines[i])) {
          errorIndices.add(i);
        }
      }
      
      // Si hay errores específicos, incluir contexto alrededor
      if (errorIndices.isNotEmpty) {
        final startIndex = (errorIndices.first - 5).clamp(0, debugLines.length);
        final endIndex = (errorIndices.last + 15).clamp(0, debugLines.length);
        for (int i = startIndex; i < endIndex; i++) {
          // Resaltar líneas de error
          if (errorIndices.contains(i)) {
            message.writeln('>>> ${debugLines[i]}');
          } else {
            message.writeln(debugLines[i]);
          }
        }
      } else {
        // Si no hay errores específicos pero hay errorLines, mostrarlos todos
        for (var line in errorLines) {
          message.writeln('>>> $line');
        }
      }
      message.writeln('```');
      message.writeln();
    }

    if (outputErrors.isNotEmpty) {
      message.writeln('## 📤 OUTPUT CON ERRORES:');
      message.writeln('```');
      for (var line in outputErrors.take(30)) {
        message.writeln(line);
      }
      message.writeln('```');
      message.writeln();
    }

    // Orden agéntica directa (sin preguntar preferencias)
    message.writeln('---\n');
    message.writeln(
      'La compilación/ejecución falló con este error. Diagnostica la causa raíz '
      'exacta y aplica la solución necesaria automáticamente (si falta emulador '
      'Android/iOS pero Chrome/Web está disponible, ejecútalo en Chrome/Web; si '
      'es un error de código o dependencias, corrígelo y verifica con '
      'flutter pub get / flutter analyze hasta que compile limpio). '
      'No preguntes qué prefiero: actúa.',
    );

    // Precargar en el chat (no enviar automáticamente)
    widget.onSendToChat!(message.toString());

    // Mostrar diálogo modal en lugar de SnackBar
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: CursorTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: CursorTheme.border, width: 1),
        ),
        title: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: CursorTheme.primary,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Errores precargados',
                style: TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Los errores han sido precargados en el Chat. Presiona "Enviar" para que la IA los analice.',
          style: TextStyle(
            color: CursorTheme.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: CursorTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }
}
