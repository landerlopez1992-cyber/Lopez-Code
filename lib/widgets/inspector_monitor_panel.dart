import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/inspector_element.dart';
import '../services/inspector_selection_service.dart';
import 'cursor_theme.dart';

/// Monitor lateral del Inspector (tipo DevTools) junto al Preview.
class InspectorMonitorPanel extends StatelessWidget {
  final double width;

  const InspectorMonitorPanel({
    super.key,
    this.width = 240,
  });

  @override
  Widget build(BuildContext context) {
    final service = InspectorSelectionService();
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final selected = service.selected;
        final hovered = service.hovered;
        final focus = selected ?? hovered;
        final isSelected = selected != null;

        return Container(
          width: width,
          margin: const EdgeInsets.only(left: 8, right: 4),
          decoration: BoxDecoration(
            color: CursorTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? CursorTheme.primary.withOpacity(0.7)
                  : CursorTheme.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                isSelected: isSelected,
                hasFocus: focus != null,
                onClear: focus == null
                    ? null
                    : () => service.clearSelection(),
              ),
              const Divider(height: 1, color: CursorTheme.border),
              Expanded(
                child: focus == null
                    ? const _EmptyState()
                    : _ElementDetails(
                        element: focus,
                        isSelected: isSelected,
                      ),
              ),
              if (focus != null) ...[
                const Divider(height: 1, color: CursorTheme.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Text(
                    isSelected
                        ? 'El agente ya ve este elemento en el contexto.'
                        : 'Clic para fijar la selección al agente.',
                    style: TextStyle(
                      color: CursorTheme.textSecondary.withOpacity(0.9),
                      fontSize: 10,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final bool isSelected;
  final bool hasFocus;
  final VoidCallback? onClear;

  const _Header({
    required this.isSelected,
    required this.hasFocus,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Row(
        children: [
          Icon(
            Icons.center_focus_strong,
            size: 14,
            color: isSelected
                ? CursorTheme.primary
                : CursorTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isSelected
                  ? 'Seleccionado'
                  : hasFocus
                      ? 'Apuntando'
                      : 'Inspector',
              style: TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              tooltip: 'Limpiar selección',
              icon: const Icon(Icons.close, size: 14),
              color: CursorTheme.textSecondary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pasa el mouse sobre la app y haz clic en un elemento.',
            style: TextStyle(
              color: CursorTheme.textSecondary,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Ese elemento queda en contexto para el agente.',
            style: TextStyle(
              color: CursorTheme.textSecondary.withOpacity(0.75),
              fontSize: 10,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ElementDetails extends StatelessWidget {
  final InspectorElement element;
  final bool isSelected;

  const _ElementDetails({
    required this.element,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final text = element.textContent?.trim();
    final rect = element.boundingRect;
    final styles = element.computedStyles;

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: CursorTheme.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF22C55E).withOpacity(0.5)
                  : const Color(0xFF3B82F6).withOpacity(0.45),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? const Color(0xFF22C55E)
                      : const Color(0xFF3B82F6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  element.displayName,
                  style: const TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Copiar selector',
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: element.fullSelector),
                  );
                },
                icon: const Icon(Icons.copy, size: 12),
                color: CursorTheme.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Row(label: 'tag', value: element.tagName.toLowerCase()),
        if (element.id != null && element.id!.isNotEmpty)
          _Row(label: 'id', value: element.id!),
        if (element.className != null && element.className!.isNotEmpty)
          _Row(label: 'class', value: element.className!),
        if (text != null && text.isNotEmpty)
          _Row(
            label: 'text',
            value: text.length > 80 ? '${text.substring(0, 80)}…' : text,
          ),
        if (rect != null)
          _Row(
            label: 'size',
            value:
                '${rect.width.toStringAsFixed(0)} × ${rect.height.toStringAsFixed(0)}',
          ),
        if (rect != null)
          _Row(
            label: 'pos',
            value:
                '${rect.x.toStringAsFixed(0)}, ${rect.y.toStringAsFixed(0)}',
          ),
        const SizedBox(height: 8),
        Text(
          'Styles',
          style: TextStyle(
            color: CursorTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        for (final key in const [
          'color',
          'backgroundColor',
          'fontSize',
          'borderRadius',
          'padding',
          'display',
        ])
          if ((styles[key] ?? '').isNotEmpty)
            _Row(label: key, value: styles[key]!),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                color: CursorTheme.textSecondary.withOpacity(0.85),
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 10,
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
