import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ui_builder_component.dart';
import 'cursor_theme.dart';

/// Panel izquierdo: catálogo estilo FlutterFlow (búsqueda + categorías + tiles).
class UiBuilderPanel extends StatefulWidget {
  final bool enabled;
  final String? hint;

  const UiBuilderPanel({
    super.key,
    this.enabled = true,
    this.hint,
  });

  @override
  State<UiBuilderPanel> createState() => _UiBuilderPanelState();
}

class _UiBuilderPanelState extends State<UiBuilderPanel> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  final Set<String> _collapsed = {};

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<UiBuilderComponent> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return UiBuilderComponent.catalog;
    return UiBuilderComponent.catalog.where((c) {
      return c.label.toLowerCase().contains(q) ||
          c.category.toLowerCase().contains(q) ||
          c.id.toLowerCase().contains(q);
    }).toList();
  }

  Map<String, List<UiBuilderComponent>> _group(
    List<UiBuilderComponent> items,
  ) {
    final byCategory = <String, List<UiBuilderComponent>>{};
    for (final c in items) {
      byCategory.putIfAbsent(c.category, () => []).add(c);
    }
    final ordered = <String, List<UiBuilderComponent>>{};
    for (final name in UiBuilderComponent.categoryOrder) {
      final list = byCategory.remove(name);
      if (list != null && list.isNotEmpty) ordered[name] = list;
    }
    // Categorías extra (si las hubiera).
    for (final entry in byCategory.entries) {
      ordered[entry.key] = entry.value;
    }
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _group(_filtered);
    final searching = _query.trim().isNotEmpty;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          _searchFocus.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _searchFocus.requestFocus();
        },
      },
      child: Focus(
        autofocus: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.hint ??
                        (widget.enabled
                            ? 'Arrastra al Preview · clic para editar'
                            : 'Abre un proyecto web (HTML)'),
                    style: const TextStyle(
                      color: CursorTheme.textSecondary,
                      fontSize: 10,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    style: const TextStyle(
                      color: CursorTheme.textPrimary,
                      fontSize: 12,
                    ),
                    cursorColor: CursorTheme.primary,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search for widget… (⌘F)',
                      hintStyle: const TextStyle(
                        color: CursorTheme.textDisabled,
                        fontSize: 11,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 15,
                        color: CursorTheme.textSecondary,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 30,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 14),
                              color: CursorTheme.textSecondary,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                      filled: true,
                      fillColor: const Color(0xFF2A2D2E),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: CursorTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: CursorTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: CursorTheme.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: grouped.isEmpty
                  ? const Center(
                      child: Text(
                        'Sin widgets',
                        style: TextStyle(
                          color: CursorTheme.textDisabled,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // 3 columnas como FlutterFlow cuando hay ancho.
                        const gap = 6.0;
                        const hPad = 8.0;
                        final usable = constraints.maxWidth - hPad * 2;
                        final cols = usable >= 210 ? 3 : 2;
                        final tileW =
                            ((usable - gap * (cols - 1)) / cols).clamp(56.0, 96.0);
                        final tileH = (tileW * 0.95).clamp(56.0, 82.0);

                        return ListView(
                          padding:
                              const EdgeInsets.fromLTRB(hPad, 4, hPad, 16),
                          children: [
                            for (final entry in grouped.entries) ...[
                              _CategoryHeader(
                                title: entry.key,
                                count: entry.value.length,
                                expanded: searching ||
                                    !_collapsed.contains(entry.key),
                                onToggle: searching
                                    ? null
                                    : () {
                                        setState(() {
                                          if (_collapsed.contains(entry.key)) {
                                            _collapsed.remove(entry.key);
                                          } else {
                                            _collapsed.add(entry.key);
                                          }
                                        });
                                      },
                              ),
                              if (searching ||
                                  !_collapsed.contains(entry.key))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Wrap(
                                    spacing: gap,
                                    runSpacing: gap,
                                    children: [
                                      for (final component in entry.value)
                                        SizedBox(
                                          width: tileW,
                                          height: tileH,
                                          child: _ComponentChip(
                                            component: component,
                                            enabled: widget.enabled,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool expanded;
  final VoidCallback? onToggle;

  const _CategoryHeader({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                color: CursorTheme.textDisabled,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
              size: 16,
              color: CursorTheme.textSecondary,
            ),
          ],
        ),
      ),
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
      color: const Color(0xFF2A2D2E),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: null,
        hoverColor: Colors.white.withValues(alpha: 0.04),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: CursorTheme.border.withValues(alpha: 0.9),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                component.icon,
                size: 22,
                color: enabled
                    ? const Color(0xFFB8BCC0)
                    : CursorTheme.textDisabled,
              ),
              const SizedBox(height: 5),
              Text(
                component.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: enabled
                      ? CursorTheme.textPrimary
                      : CursorTheme.textDisabled,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!enabled) return Opacity(opacity: 0.5, child: tile);

    return Draggable<UiBuilderComponent>(
      data: component,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF2A2D2E),
        child: Container(
          width: 72,
          height: 66,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: CursorTheme.primary, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(component.icon, size: 20, color: CursorTheme.primary),
              const SizedBox(height: 4),
              Text(
                component.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }
}
