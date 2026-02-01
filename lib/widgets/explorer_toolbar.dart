import 'package:flutter/material.dart';
import 'cursor_theme.dart';

/// Barra de herramientas del explorador
/// Similar a Cursor IDE - iconos para diferentes acciones
class ExplorerToolbar extends StatelessWidget {
  final int selectedIndex;
  final Function(int)? onItemSelected;
  final Function(String)? onAction; // Nueva callback para acciones específicas

  const ExplorerToolbar({
    super.key,
    this.selectedIndex = 0,
    this.onItemSelected,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      {
        'icon': Icons.search_outlined,
        'tooltip': 'Buscar archivos',
        'selectedIcon': Icons.search,
        'action': 'search',
      },
      // ✅ ELIMINADOS: Git, Supabase, Firebase - Solo mostraban "próximamente disponible"
    ];

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: CursorTheme.explorerBackground,
        border: Border(
          bottom: BorderSide(color: CursorTheme.border, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: List.generate(items.length, (index) {
          final isSelected = index == selectedIndex;
          final item = items[index];
          
          return Expanded(
            child: Tooltip(
              message: item['tooltip'] as String,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    onItemSelected?.call(index);
                    // Ejecutar acción específica si está definida
                    final action = item['action'] as String?;
                    if (action != null) {
                      onAction?.call(action);
                    }
                  },
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? CursorTheme.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      isSelected
                          ? item['selectedIcon'] as IconData
                          : item['icon'] as IconData,
                      size: 18,
                      color: isSelected
                          ? CursorTheme.primary
                          : CursorTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
