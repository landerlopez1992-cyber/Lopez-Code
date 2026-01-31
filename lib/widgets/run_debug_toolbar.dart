import 'package:flutter/material.dart';
import 'cursor_theme.dart';

/// Barra de herramientas de Run and Debug
/// Similar a Cursor IDE - botones para ejecutar, depurar, etc.
/// Ahora es arrastrable como en Cursor IDE
class RunDebugToolbar extends StatefulWidget {
  final VoidCallback? onRun;
  final VoidCallback? onDebug;
  final VoidCallback? onStop;
  final VoidCallback? onRestart;
  final Function(String)? onPlatformChanged;
  final String? selectedPlatform;
  final bool isRunning;
  final bool isDebugging;

  const RunDebugToolbar({
    super.key,
    this.onRun,
    this.onDebug,
    this.onStop,
    this.onRestart,
    this.onPlatformChanged,
    this.selectedPlatform,
    this.isRunning = false,
    this.isDebugging = false,
  });

  @override
  State<RunDebugToolbar> createState() => _RunDebugToolbarState();
}

class _RunDebugToolbarState extends State<RunDebugToolbar> {
  late Offset _position;
  bool _isDragging = false;
  
  @override
  void initState() {
    super.initState();
    // Posición inicial: se calculará dinámicamente en build() para alinearse con el icono del chat
    // Por defecto, usar posición que se calculará en build()
    _position = const Offset(0, 0); // Se calculará en build()
  }

  @override
  Widget build(BuildContext context) {
    // Calcular posición relativa al panel de chat
    // Sidebar (280px) + Emulador (550px) = 830px (inicio del panel de chat)
    // La barra debe estar alineada horizontalmente con los botones del AppBar (esquina superior derecha)
    // y verticalmente con la barra del chat (que está justo debajo del AppBar)
    final chatPanelStart = 280.0 + 550.0; // Sidebar + Emulador
    final left = chatPanelStart + 12.0; // Alineado con el inicio del panel de chat
    // Top: Alineada con el AppBar (los botones están en el AppBar, altura ~56px)
    // La barra debe estar a la misma altura que los botones del AppBar
    final top = 8.0; // Pequeño margen desde arriba para alinearse con los botones del AppBar
    
    // Si la posición fue arrastrada (dx > 0 y dy > 0), usar esa posición, sino usar la calculada
    final finalLeft = _position.dx > 0 && _position.dx != chatPanelStart + 12.0 ? _position.dx : left;
    final finalTop = _position.dy > 0 && _position.dy != 8.0 ? _position.dy : top;
    
    // Actualizar posición inicial si no ha sido arrastrada
    if (_position.dx == 0 && _position.dy == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _position = Offset(finalLeft, finalTop);
          });
        }
      });
    }
    
    return Positioned(
      left: finalLeft,
      top: finalTop,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            setState(() {
              _isDragging = true;
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _position += details.delta;
              // Limitar el movimiento dentro de la pantalla
              final screenSize = MediaQuery.of(context).size;
              final toolbarWidth = 350.0; // Ancho aproximado de la barra
              final toolbarHeight = 50.0; // Alto aproximado de la barra
              _position = Offset(
                _position.dx.clamp(0.0, screenSize.width - toolbarWidth),
                _position.dy.clamp(0.0, screenSize.height - toolbarHeight),
              );
            });
          },
          onPanEnd: (details) {
            setState(() {
              _isDragging = false;
            });
          },
          child: MouseRegion(
          cursor: _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
          child: Material(
            color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 32, maxWidth: 600),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: CursorTheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isDragging ? CursorTheme.primary : CursorTheme.border,
                  width: _isDragging ? 2 : 1,
                ),
                boxShadow: _isDragging
                    ? [
                        BoxShadow(
                          color: CursorTheme.primary.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Indicador de arrastre (solo visible cuando se arrastra)
                if (_isDragging)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.drag_handle,
                      size: 12,
                      color: CursorTheme.primary,
                    ),
                  ),
                // Botón Run
                _ToolbarButton(
                  icon: Icons.play_arrow,
                  label: 'Run',
                  onPressed: widget.isRunning ? null : widget.onRun,
                  color: Colors.green,
                  tooltip: 'Ejecutar aplicación',
                ),
                const SizedBox(width: 3),
                
                // Botón Debug
                _ToolbarButton(
                  icon: Icons.bug_report,
                  label: 'Debug',
                  onPressed: widget.isRunning ? null : widget.onDebug,
                  color: Colors.orange,
                  tooltip: 'Depurar aplicación',
                ),
                const SizedBox(width: 3),
                
                // Botón Stop
                _ToolbarButton(
                  icon: Icons.stop,
                  label: 'Stop',
                  onPressed: widget.isRunning ? widget.onStop : null,
                  color: Colors.red,
                  tooltip: 'Detener ejecución',
                  isEnabled: widget.isRunning,
                ),
                const SizedBox(width: 3),
                
                // Botón Restart
                _ToolbarButton(
                  icon: Icons.refresh,
                  label: 'Restart',
                  onPressed: widget.isRunning ? widget.onRestart : null,
                  color: Colors.blue,
                  tooltip: 'Reiniciar aplicación',
                  isEnabled: widget.isRunning,
                ),
                
                const SizedBox(width: 6),
                
                // Separador
                Container(
                  width: 1,
                  height: 20,
                  color: CursorTheme.border,
                ),
                
                const SizedBox(width: 6),
                
                // Selector de plataforma - sin Flexible para evitar problemas
                _PlatformSelector(
                  selectedPlatform: widget.selectedPlatform ?? 'macos',
                  onChanged: widget.onPlatformChanged,
                  isEnabled: !widget.isRunning,
                ),
                
                // Indicador de estado - sin Flexible, usar constraints
                if (widget.isRunning) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 100),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.green.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          widget.isDebugging ? 'Debugging...' : 'Running...',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Botón de la barra de herramientas
class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final String tooltip;
  final bool isEnabled;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.onPressed,
    required this.color,
    required this.tooltip,
    this.isEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null;
    
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isDisabled ? null : onPressed,
          borderRadius: BorderRadius.circular(4),
            child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: isEnabled
                  ? color.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: isEnabled
                  ? Border.all(
                      color: color.withOpacity(0.3),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: isDisabled
                      ? CursorTheme.textSecondary.withOpacity(0.3)
                      : isEnabled
                          ? color
                          : CursorTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isDisabled
                        ? CursorTheme.textSecondary.withOpacity(0.3)
                        : isEnabled
                            ? color
                            : CursorTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: isEnabled ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Selector de plataforma
class _PlatformSelector extends StatelessWidget {
  final String selectedPlatform;
  final Function(String)? onChanged;
  final bool isEnabled;

  const _PlatformSelector({
    required this.selectedPlatform,
    this.onChanged,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final platforms = [
      {'value': 'macos', 'label': 'macOS', 'icon': Icons.desktop_mac},
      {'value': 'ios', 'label': 'iOS', 'icon': Icons.phone_iphone},
      {'value': 'android', 'label': 'Android', 'icon': Icons.android},
      {'value': 'web', 'label': 'Web', 'icon': Icons.language},
    ];

    return PopupMenuButton<String>(
      enabled: isEnabled,
      initialValue: selectedPlatform,
      tooltip: 'Seleccionar plataforma',
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: CursorTheme.border, width: 1),
      ),
      color: CursorTheme.surface,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 100),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: CursorTheme.background,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: CursorTheme.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              platforms.firstWhere((p) => p['value'] == selectedPlatform)['icon'] as IconData,
              size: 12,
              color: isEnabled
                  ? CursorTheme.textPrimary
                  : CursorTheme.textSecondary.withOpacity(0.3),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                platforms.firstWhere((p) => p['value'] == selectedPlatform)['label'] as String,
                style: TextStyle(
                  color: isEnabled
                      ? CursorTheme.textPrimary
                      : CursorTheme.textSecondary.withOpacity(0.3),
                  fontSize: 10,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 12,
              color: isEnabled
                  ? CursorTheme.textSecondary
                  : CursorTheme.textSecondary.withOpacity(0.3),
            ),
          ],
        ),
      ),
      onSelected: (value) {
        print('🔧 PopupMenuButton seleccionado: $value');
        onChanged?.call(value);
      },
      itemBuilder: (context) {
        return platforms.map((platform) {
          final isSelected = platform['value'] == selectedPlatform;
          return PopupMenuItem<String>(
            value: platform['value'] as String,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  platform['icon'] as IconData,
                  size: 18,
                  color: isSelected
                      ? CursorTheme.primary
                      : CursorTheme.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  platform['label'] as String,
                  style: TextStyle(
                    color: isSelected
                        ? CursorTheme.primary
                        : CursorTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 12),
                  Icon(
                    Icons.check,
                    size: 18,
                    color: CursorTheme.primary,
                  ),
                ],
              ],
            ),
          );
        }).toList();
      },
    );
  }
}
