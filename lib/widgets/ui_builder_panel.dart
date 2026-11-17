import 'package:flutter/material.dart';

import '../models/ui_builder_component.dart';
import 'cursor_theme.dart';

/// Panel izquierdo: catálogo de componentes arrastrables (Nivel 1).
class UiBuilderPanel extends StatelessWidget {
  final bool enabled;
  final String? hint;

  const UiBuilderPanel({
    super.key,
    this.enabled = true,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final byCategory = <String, List<UiBuilderComponent>>{};
    for (final c in UiBuilderComponent.catalog) {
      byCategory.putIfAbsent(c.category, () => []).add(c);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: CursorTheme.border),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'UI Builder',
                style: TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hint ??
                    (enabled
                        ? 'Arrastra un elemento al Preview'
                        : 'Abre un proyecto web (HTML) y pon Run'),
                style: const TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            children: [
              for (final entry in byCategory.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  child: Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(
                      color: CursorTheme.textDisabled,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final component in entry.value)
                      _ComponentChip(
                        component: component,
                        enabled: enabled,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ComponentChip extends StatelessWidget {
  final UiBuilderComponent component;
  final bool enabled;

  const _ComponentChip({
    required this.component,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Material(
      color: CursorTheme.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: enabled ? null : null,
        child: Container(
          width: 108,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: CursorTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                component.icon,
                size: 16,
                color: enabled
                    ? CursorTheme.primary
                    : CursorTheme.textDisabled,
              ),
              const SizedBox(height: 6),
              Text(
                component.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled
                      ? CursorTheme.textPrimary
                      : CursorTheme.textDisabled,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!enabled) return Opacity(opacity: 0.55, child: tile);

    return Draggable<UiBuilderComponent>(
      data: component,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(6),
        color: CursorTheme.surface,
        child: Container(
          width: 120,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: CursorTheme.primary),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(component.icon, size: 14, color: CursorTheme.primary),
              const SizedBox(width: 6),
              Text(
                component.label,
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 12,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: tile,
    );
  }
}
