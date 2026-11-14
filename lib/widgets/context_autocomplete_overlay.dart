import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/context_mention.dart';
import '../services/context_builder_service.dart';
import 'cursor_theme.dart';

/// Modo activo del popup de autocompletado.
enum ContextAutocompleteMode { none, mention, slash }

/// Query detectada en el input (`@login` o `/fix`).
class ContextAutocompleteQuery {
  final ContextAutocompleteMode mode;

  /// Texto tras `@` o `/` (sin el trigger).
  final String filter;

  /// Índice del carácter `@` o `/` en el input.
  final int triggerIndex;

  /// Rango a reemplazar en el TextField (trigger + filter).
  final TextRange replacementRange;

  const ContextAutocompleteQuery({
    required this.mode,
    required this.filter,
    required this.triggerIndex,
    required this.replacementRange,
  });

  bool get isActive => mode != ContextAutocompleteMode.none;
}

/// Ítem unificado mostrado en el overlay.
class ContextAutocompleteItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final ContextMention? mention;
  final SlashCommand? slashCommand;

  const ContextAutocompleteItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.mention,
    this.slashCommand,
  });
}

/// Popup estilo Cursor para menciones `@` y slash commands `/`.
///
/// Uso típico (desde chat_screen / CursorChatInput):
/// ```dart
/// ContextAutocompleteOverlay(
///   inputText: controller.text,
///   cursorOffset: controller.selection.baseOffset,
///   projectPath: projectPath,
///   onMentionSelected: (m, query) { … insertar m.label … },
///   onSlashCommandSelected: (cmd, expanded) { … reemplazar input … },
/// )
/// ```
class ContextAutocompleteOverlay extends StatefulWidget {
  final String inputText;
  final int cursorOffset;
  final String projectPath;
  final String? activeFilePath;

  /// Máximo de resultados de archivos/carpetas (además de especiales).
  final int maxFileResults;

  final void Function(
    ContextMention mention,
    ContextAutocompleteQuery query,
  )? onMentionSelected;

  final void Function(
    SlashCommand command,
    String expandedPrompt,
    ContextAutocompleteQuery query,
  )? onSlashCommandSelected;

  final VoidCallback? onDismiss;

  const ContextAutocompleteOverlay({
    super.key,
    required this.inputText,
    required this.cursorOffset,
    required this.projectPath,
    this.activeFilePath,
    this.maxFileResults = 40,
    this.onMentionSelected,
    this.onSlashCommandSelected,
    this.onDismiss,
  });

  /// Detecta si el cursor está en una mención `@…` o un slash command `/…`.
  static ContextAutocompleteQuery detectQuery(
    String text,
    int cursorOffset,
  ) {
    final offset = cursorOffset.clamp(0, text.length);
    final before = text.substring(0, offset);

    // Slash solo al inicio del input (o tras whitespace inicial).
    final slashMatch = RegExp(r'^\s*/([^\s]*)$').firstMatch(before);
    if (slashMatch != null) {
      final filter = slashMatch.group(1) ?? '';
      final triggerIndex = before.lastIndexOf('/');
      return ContextAutocompleteQuery(
        mode: ContextAutocompleteMode.slash,
        filter: filter,
        triggerIndex: triggerIndex,
        replacementRange: TextRange(start: triggerIndex, end: offset),
      );
    }

    // @mención: último @ sin espacios hasta el cursor.
    final atIndex = before.lastIndexOf('@');
    if (atIndex >= 0) {
      final afterAt = before.substring(atIndex + 1);
      // No atraviesa whitespace ni otro @
      if (!afterAt.contains(RegExp(r'\s')) && !afterAt.contains('@')) {
        // Evitar emails simples: char antes de @ alfanumérico
        final charBefore =
            atIndex > 0 ? before[atIndex - 1] : ' ';
        if (!RegExp(r'[A-Za-z0-9_]').hasMatch(charBefore)) {
          return ContextAutocompleteQuery(
            mode: ContextAutocompleteMode.mention,
            filter: afterAt,
            triggerIndex: atIndex,
            replacementRange: TextRange(start: atIndex, end: offset),
          );
        }
      }
    }

    return ContextAutocompleteQuery(
      mode: ContextAutocompleteMode.none,
      filter: '',
      triggerIndex: -1,
      replacementRange: TextRange(start: offset, end: offset),
    );
  }

  @override
  State<ContextAutocompleteOverlay> createState() =>
      _ContextAutocompleteOverlayState();
}

class _ContextAutocompleteOverlayState
    extends State<ContextAutocompleteOverlay> {
  static List<_IndexedPath>? _cachedIndex;
  static String? _cachedProjectPath;
  static DateTime? _cachedAt;

  final FocusNode _focusNode = FocusNode();
  int _selectedIndex = 0;
  List<ContextAutocompleteItem> _items = const [];
  ContextAutocompleteQuery _query = const ContextAutocompleteQuery(
    mode: ContextAutocompleteMode.none,
    filter: '',
    triggerIndex: -1,
    replacementRange: TextRange(start: 0, end: 0),
  );
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant ContextAutocompleteOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inputText != widget.inputText ||
        oldWidget.cursorOffset != widget.cursorOffset ||
        oldWidget.projectPath != widget.projectPath) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 60), _refresh);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final query = ContextAutocompleteOverlay.detectQuery(
      widget.inputText,
      widget.cursorOffset,
    );
    if (!query.isActive) {
      if (mounted) {
        setState(() {
          _query = query;
          _items = const [];
          _selectedIndex = 0;
          _loading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _query = query;
        _loading = query.mode == ContextAutocompleteMode.mention;
      });
    }

    final items = query.mode == ContextAutocompleteMode.slash
        ? _buildSlashItems(query.filter)
        : await _buildMentionItems(query.filter);

    if (!mounted) return;
    setState(() {
      _items = items;
      _selectedIndex = items.isEmpty ? 0 : _selectedIndex.clamp(0, items.length - 1);
      _loading = false;
    });
  }

  List<ContextAutocompleteItem> _buildSlashItems(String filter) {
    final q = filter.toLowerCase();
    return SlashCommand.builtins
        .where((c) {
          if (q.isEmpty) return true;
          return c.trigger.substring(1).contains(q) ||
              c.title.toLowerCase().contains(q) ||
              c.id.contains(q);
        })
        .map(
          (c) => ContextAutocompleteItem(
            id: c.id,
            title: c.trigger,
            subtitle: c.description,
            icon: _slashIcon(c.id),
            slashCommand: c,
          ),
        )
        .toList();
  }

  IconData _slashIcon(String id) {
    switch (id) {
      case 'fix':
        return Icons.build_circle_outlined;
      case 'explain':
        return Icons.menu_book_outlined;
      case 'refactor':
        return Icons.auto_fix_high;
      case 'analyze':
        return Icons.analytics_outlined;
      default:
        return Icons.flash_on;
    }
  }

  Future<List<ContextAutocompleteItem>> _buildMentionItems(String filter) async {
    final q = filter.toLowerCase();
    final items = <ContextAutocompleteItem>[];

    // Especiales siempre primero si matchean.
    final specials = <ContextAutocompleteItem>[
      ContextAutocompleteItem(
        id: 'special:problems',
        title: '@problems',
        subtitle: 'Errores actuales del analyzer / Problems',
        icon: Icons.warning_amber_rounded,
        mention: ContextMention.problems(),
      ),
      ContextAutocompleteItem(
        id: 'special:structure',
        title: '@structure',
        subtitle: 'Árbol del proyecto (codebase)',
        icon: Icons.account_tree_outlined,
        mention: ContextMention.codebase(label: '@structure'),
      ),
      ContextAutocompleteItem(
        id: 'special:codebase',
        title: '@codebase',
        subtitle: 'Estructura completa del proyecto',
        icon: Icons.folder_special_outlined,
        mention: ContextMention.codebase(label: '@codebase'),
      ),
    ];

    for (final s in specials) {
      final name = s.title.substring(1).toLowerCase();
      if (q.isEmpty || name.contains(q) || s.subtitle.toLowerCase().contains(q)) {
        items.add(s);
      }
    }

    final index = await _ensureIndex();
    final matched = <ContextAutocompleteItem>[];

    for (final entry in index) {
      if (matched.length >= widget.maxFileResults) break;
      final hay = '${entry.relative} ${entry.name}'.toLowerCase();
      if (q.isNotEmpty && !hay.contains(q)) continue;

      if (entry.isDirectory) {
        matched.add(
          ContextAutocompleteItem(
            id: 'folder:${entry.relative}',
            title: '@${entry.name}/',
            subtitle: entry.relative.isEmpty ? '/' : entry.relative,
            icon: Icons.folder_outlined,
            mention: ContextMention.folder(relativePath: entry.relative),
          ),
        );
      } else {
        matched.add(
          ContextAutocompleteItem(
            id: 'file:${entry.relative}',
            title: '@${entry.name}',
            subtitle: entry.relative,
            icon: Icons.insert_drive_file_outlined,
            mention: ContextMention.file(relativePath: entry.relative),
          ),
        );
      }
    }

    // Priorizar matches que empiezan con el filtro.
    matched.sort((a, b) {
      final aStarts = a.title.toLowerCase().startsWith('@$q');
      final bStarts = b.title.toLowerCase().startsWith('@$q');
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return a.subtitle.compareTo(b.subtitle);
    });

    items.addAll(matched);
    return items;
  }

  Future<List<_IndexedPath>> _ensureIndex() async {
    final now = DateTime.now();
    final cacheFresh = _cachedProjectPath == widget.projectPath &&
        _cachedIndex != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < const Duration(seconds: 30);

    if (cacheFresh) return _cachedIndex!;

    final index = await _scanProject(widget.projectPath);
    _cachedProjectPath = widget.projectPath;
    _cachedIndex = index;
    _cachedAt = now;
    return index;
  }

  Future<List<_IndexedPath>> _scanProject(String projectPath) async {
    final results = <_IndexedPath>[];
    final root = Directory(projectPath);
    if (!await root.exists()) return results;

    Future<void> walk(Directory dir) async {
      List<FileSystemEntity> children;
      try {
        children = await dir.list(followLinks: false).toList();
      } catch (_) {
        return;
      }

      for (final child in children) {
        final name = child.path.split('/').last;
        if (_ignoredNames.contains(name)) continue;

        final relative = child.path.replaceAll('\\', '/');
        final rootNorm = projectPath.replaceAll('\\', '/');
        final rel = relative.startsWith('$rootNorm/')
            ? relative.substring(rootNorm.length + 1)
            : relative;

        if (child is Directory) {
          results.add(_IndexedPath(
            relative: rel,
            name: name,
            isDirectory: true,
          ));
          await walk(child);
        } else if (child is File) {
          results.add(_IndexedPath(
            relative: rel,
            name: name,
            isDirectory: false,
          ));
        }
      }
    }

    await walk(root);
    return results;
  }

  static const Set<String> _ignoredNames = {
    '.git',
    'build',
    '.dart_tool',
    'node_modules',
    '.idea',
    '.vscode',
    '.symlinks',
    'Pods',
    '.gradle',
    'DerivedData',
    '.DS_Store',
    'ephemeral',
  };

  void _moveSelection(int delta) {
    if (_items.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta) % _items.length;
      if (_selectedIndex < 0) _selectedIndex = _items.length - 1;
    });
  }

  void _activateSelected() {
    if (_items.isEmpty) return;
    _activate(_items[_selectedIndex]);
  }

  void _activate(ContextAutocompleteItem item) {
    if (item.mention != null) {
      widget.onMentionSelected?.call(item.mention!, _query);
      return;
    }
    if (item.slashCommand != null) {
      final expanded = ContextBuilderService.expandSlashCommand(
        command: item.slashCommand!,
        activeFilePath: widget.activeFilePath,
      );
      widget.onSlashCommandSelected?.call(
        item.slashCommand!,
        expanded,
        _query,
      );
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_query.isActive || _items.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _activateSelected();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!_query.isActive) {
      return const SizedBox.shrink();
    }

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 280),
          decoration: BoxDecoration(
            color: CursorTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: CursorTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const Divider(height: 1, color: CursorTheme.border),
              Expanded(
                child: _loading
                    ? const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _items.isEmpty
                        ? Center(
                            child: Text(
                              _query.mode == ContextAutocompleteMode.slash
                                  ? 'No slash commands'
                                  : 'No matches',
                              style: const TextStyle(
                                color: CursorTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              final selected = index == _selectedIndex;
                              return _SuggestionTile(
                                item: item,
                                selected: selected,
                                onTap: () => _activate(item),
                                onHover: () {
                                  if (_selectedIndex != index) {
                                    setState(() => _selectedIndex = index);
                                  }
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isSlash = _query.mode == ContextAutocompleteMode.slash;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            isSlash ? Icons.flash_on : Icons.alternate_email,
            size: 14,
            color: CursorTheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isSlash
                  ? 'Slash commands'
                  : 'Add context ${_query.filter.isEmpty ? '' : '· ${_query.filter}'}',
              style: const TextStyle(
                color: CursorTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${_items.length}',
            style: const TextStyle(
              color: CursorTheme.textDisabled,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final ContextAutocompleteItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _SuggestionTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: selected
              ? CursorTheme.explorerItemSelected
              : Colors.transparent,
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 16,
                color: selected
                    ? CursorTheme.primary
                    : CursorTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        color: CursorTheme.textPrimary,
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        color: CursorTheme.textSecondary,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IndexedPath {
  final String relative;
  final String name;
  final bool isDirectory;

  const _IndexedPath({
    required this.relative,
    required this.name,
    required this.isDirectory,
  });
}
