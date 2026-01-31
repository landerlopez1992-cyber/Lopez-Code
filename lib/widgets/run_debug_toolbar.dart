import 'package:flutter/material.dart';
import 'cursor_theme.dart';

/// Barra de herramientas de Run and Debug
/// Similar a Cursor IDE - botones para ejecutar, depurar, etc.
class RunDebugToolbar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: CursorTheme.border,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Botón Run
          _ToolbarButton(
            icon: Icons.play_arrow,
            label: 'Run',
            onPressed: isRunning ? null : onRun,
            color: Colors.green,
            tooltip: 'Ejecutar aplicación',
          ),
          const SizedBox(width: 3),
          
          // Botón Debug
          _ToolbarButton(
            icon: Icons.bug_report,
            label: 'Debug',
            onPressed: isRunning ? null : onDebug,
            color: Colors.orange,
            tooltip: 'Depurar aplicación',
          ),
          const SizedBox(width: 3),
          
          // Botón Stop
          _ToolbarButton(
            icon: Icons.stop,
            label: 'Stop',
            onPressed: isRunning ? onStop : null,
            color: Colors.red,
            tooltip: 'Detener ejecución',
            isEnabled: isRunning,
          ),
          const SizedBox(width: 3),
          
          // Botón Restart
          _ToolbarButton(
            icon: Icons.refresh,
            label: 'Restart',
            onPressed: isRunning ? onRestart : null,
            color: Colors.blue,
            tooltip: 'Reiniciar aplicación',
            isEnabled: isRunning,
          ),
          
          const SizedBox(width: 8),
          
          // Separador
          Container(
            width: 1,
            height: 20,
            color: CursorTheme.border,
          ),
          
          const SizedBox(width: 8),
          
          // Selector de plataforma - Flexible para evitar overflow
          Flexible(
            child: _PlatformSelector(
              selectedPlatform: selectedPlatform ?? 'macos',
              onChanged: onPlatformChanged,
              isEnabled: !isRunning,
            ),
          ),
          
          // Indicador de estado - Flexible para evitar overflow
          if (isRunning) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
                    Flexible(
                      child: Text(
                        isDebugging ? 'Debugging...' : 'Running...',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
            Text(
              platforms.firstWhere((p) => p['value'] == selectedPlatform)['label'] as String,
              style: TextStyle(
                color: isEnabled
                    ? CursorTheme.textPrimary
                    : CursorTheme.textSecondary.withOpacity(0.3),
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
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
