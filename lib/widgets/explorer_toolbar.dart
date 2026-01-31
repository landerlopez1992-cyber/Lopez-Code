import 'package:flutter/material.dart';
import 'cursor_theme.dart';

/// Barra de herramientas del explorador
/// Similar a Cursor IDE - iconos para diferentes acciones
class ExplorerToolbar extends StatelessWidget {
  final int selectedIndex;
  final Function(int)? onItemSelected;

  const ExplorerToolbar({
    super.key,
    this.selectedIndex = 0,
    this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      {
        'icon': Icons.description_outlined,
        'tooltip': 'Explorador de archivos',
        'selectedIcon': Icons.description,
      },
      {
        'icon': Icons.search_outlined,
        'tooltip': 'Buscar',
        'selectedIcon': Icons.search,
      },
      {
        'icon': Icons.account_tree_outlined,
        'tooltip': 'Ramas y dependencias',
        'selectedIcon': Icons.account_tree,
      },
      {
        'icon': Icons.grid_view_outlined,
        'tooltip': 'Vista de grid',
        'selectedIcon': Icons.grid_view,
      },
      {
        'icon': Icons.preview_outlined,
        'tooltip': 'Vista previa',
        'selectedIcon': Icons.preview,
      },
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
                  onTap: () => onItemSelected?.call(index),
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
