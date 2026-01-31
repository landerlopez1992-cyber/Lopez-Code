import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'cursor_theme.dart';

/// Panel inferior con tabs para Debug Console, Output, Problems
/// Similar a Cursor IDE - muestra consola, output y problemas
class DebugConsolePanel extends StatefulWidget {
  final double? height;
  final Function(double)? onHeightChanged;
  final List<String>? problems;
  final List<String>? output;
  final List<String>? debugConsole;
  final Function(String message)? onSendToChat; // Callback para enviar errores al chat

  const DebugConsolePanel({
    super.key,
    this.height,
    this.onHeightChanged,
    this.problems,
    this.output,
    this.debugConsole,
    this.onSendToChat,
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedTabIndex = _tabController.index;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _problemsScrollController.dispose();
    _outputScrollController.dispose();
    _debugConsoleScrollController.dispose();
    _filterController.dispose();
    super.dispose();
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
                child: Container(
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
          // Header con tabs
          _buildHeader(),
          
          // Filtro (solo en Debug Console)
          if (_selectedTabIndex == 2) _buildFilter(),
          
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
                _buildTab(
                  'Problems',
                  widget.problems?.length ?? 0,
                  Colors.red,
                ),
                const Tab(text: 'Output'),
                const Tab(text: 'Debug Console'),
              ],
            ),
          ),
          
          // Botones de acción (más pequeños para evitar overflow)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Botón "Enviar al Chat IA" - Solo visible si hay errores
              if ((widget.problems?.isNotEmpty ?? false) || 
                  (widget.debugConsole?.any((line) => 
                    line.contains('❌') || 
                    line.contains('Compilación fallida') ||
                    line.toLowerCase().contains('error') ||
                    line.toLowerCase().contains('failed') ||
                    line.toLowerCase().contains('exception')
                  ) ?? false))
                IconButton(
                  icon: const Icon(Icons.smart_toy, size: 14),
                  color: CursorTheme.primary,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => _sendErrorsToChat(),
                  tooltip: 'Precargar errores en el Chat IA',
                ),
              
              // Botón de búsqueda
              IconButton(
                icon: const Icon(Icons.search, size: 14),
                color: CursorTheme.textSecondary,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  // TODO: Implementar búsqueda
                },
                tooltip: 'Buscar',
              ),
              
              // Botón de filtro
              IconButton(
                icon: const Icon(Icons.filter_list, size: 14),
                color: CursorTheme.textSecondary,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  // TODO: Implementar filtro
                },
                tooltip: 'Filtrar',
              ),
              
              // Botón de limpiar
              IconButton(
                icon: const Icon(Icons.clear_all, size: 14),
                color: CursorTheme.textSecondary,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  // TODO: Limpiar contenido
                },
                tooltip: 'Limpiar',
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

  Widget _buildFilter() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
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
        style: const TextStyle(
          fontSize: 12,
          color: CursorTheme.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Filter (e.g. text, !exclu...)',
          hintStyle: TextStyle(
            fontSize: 12,
            color: CursorTheme.textSecondary,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          prefixIcon: Icon(
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
        onChanged: (value) {
          setState(() {});
        },
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
      ],
    );
  }

  Widget _buildProblemsTab() {
    final problems = widget.problems ?? [];
    final filter = _filterController.text.toLowerCase();

    final filteredProblems = filter.isEmpty
        ? problems
        : problems.where((p) => p.toLowerCase().contains(filter)).toList();

    if (filteredProblems.isEmpty) {
      return Center(
        child: Text(
          'No problems found',
          style: TextStyle(
            color: CursorTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _problemsScrollController,
      itemCount: filteredProblems.length,
      itemBuilder: (context, index) {
        final problem = filteredProblems[index];
        final isError = problem.toLowerCase().contains('error');
        final isWarning = problem.toLowerCase().contains('warning');

        return Container(
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
                        : Colors.transparent,
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
                child: Text(
                  problem,
                  style: TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOutputTab() {
    final output = widget.output ?? [];
    final filter = _filterController.text.toLowerCase();

    final filteredOutput = filter.isEmpty
        ? output
        : output.where((o) => o.toLowerCase().contains(filter)).toList();

    return Container(
      color: CursorTheme.codeBackground,
      child: ListView.builder(
        controller: _outputScrollController,
        padding: const EdgeInsets.all(8),
        itemCount: filteredOutput.length,
        itemBuilder: (context, index) {
          final line = filteredOutput[index];
          return SelectableText(
            line,
            style: TextStyle(
              color: CursorTheme.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.5,
            ),
          );
        },
      ),
    );
  }

  Widget _buildDebugConsoleTab() {
    final console = widget.debugConsole ?? [];
    final filter = _filterController.text.toLowerCase();

    final filteredConsole = filter.isEmpty
        ? console
        : console.where((c) => c.toLowerCase().contains(filter)).toList();

    return Container(
      color: CursorTheme.codeBackground,
      child: ListView.builder(
        controller: _debugConsoleScrollController,
        padding: const EdgeInsets.all(8),
        itemCount: filteredConsole.length,
        itemBuilder: (context, index) {
          final line = filteredConsole[index];
          final isFlutterLog = line.startsWith('flutter:');
          
          return SelectableText(
            line,
            style: TextStyle(
              color: isFlutterLog
                  ? Colors.blue
                  : CursorTheme.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.5,
            ),
          );
        },
      ),
    );
  }

  /// Precarga los errores en el chat (no envía automáticamente)
  void _sendErrorsToChat() {
    if (widget.onSendToChat == null) return;

    // Recopilar todos los errores
    final problems = widget.problems ?? [];
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

    // Instrucciones claras para la IA
    message.writeln('---\n');
    message.writeln('**INSTRUCCIONES PARA EL ANÁLISIS:**\n');
    message.writeln('1. **Analiza DIRECTAMENTE los errores mostrados arriba**');
    message.writeln('2. **Identifica la causa raíz** de cada error');
    message.writeln('3. **Proporciona soluciones específicas** con código corregido');
    message.writeln('4. **NO pidas leer archivos** - analiza los errores directamente');
    message.writeln('5. **Sé específico y directo** como el agente de Cursor IDE');
    message.writeln('\n**Ejemplo de respuesta esperada:**');
    message.writeln('- "El error indica que falta el import X en el archivo Y"');
    message.writeln('- "La línea Z tiene un error de sintaxis: [mostrar corrección]"');
    message.writeln('- "El problema es que la función A no está definida, necesitas [solución]"');

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
