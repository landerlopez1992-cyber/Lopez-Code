import 'dart:async';

import 'package:flutter/material.dart';

import '../services/codebase_search_service.dart';
import 'cursor_theme.dart';

/// Panel lateral "Search" estilo Cursor / VS Code.
///
/// Combina:
/// - Archivos y carpetas por **nombre**
/// - Texto **dentro** de archivos (grep)
class GlobalSearchPanel extends StatefulWidget {
  final String? projectPath;

  /// Abre el archivo en la línea indicada (ruta absoluta recomendada).
  final void Function(String filePath, int lineNumber)? onSelectResult;

  const GlobalSearchPanel({
    super.key,
    this.projectPath,
    this.onSelectResult,
  });

  @override
  State<GlobalSearchPanel> createState() => _GlobalSearchPanelState();
}

class _GlobalSearchPanelState extends State<GlobalSearchPanel> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _extensionController = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  Timer? _debounce;
  bool _caseSensitive = false;
  bool _useRegex = false;
  bool _searching = false;
  String? _error;

  /// Resultados por nombre (archivos + carpetas).
  List<Map<String, dynamic>> _nameResults = [];

  /// Resultados de grep (texto en archivos).
  List<Map<String, dynamic>> _rawResults = [];

  /// Archivos expandido/colapsado (clave = relative path).
  final Set<String> _collapsedFiles = {};

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _queryFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant GlobalSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectPath != widget.projectPath) {
      _nameResults = [];
      _rawResults = [];
      _error = null;
      if (_queryController.text.trim().isNotEmpty) {
        _scheduleSearch();
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.removeListener(_onQueryChanged);
    _queryController.dispose();
    _extensionController.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    setState(() {}); // Actualiza botón clear / status
    _scheduleSearch();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), _runSearch);
  }

  Future<void> _runSearch() async {
    final projectPath = widget.projectPath;
    final query = _queryController.text;
    if (projectPath == null || projectPath.isEmpty) {
      setState(() {
        _nameResults = [];
        _rawResults = [];
        _searching = false;
        _error = 'No hay proyecto abierto';
      });
      return;
    }
    if (query.trim().isEmpty) {
      setState(() {
        _nameResults = [];
        _rawResults = [];
        _searching = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final ext = _extensionController.text.trim();
      final effectiveQuery = _useRegex ? query : RegExp.escape(query);

      // Nombre + contenido en paralelo.
      final nameFuture = CodebaseSearchService.findByName(
        projectPath: projectPath,
        query: query,
        caseSensitive: _caseSensitive,
        maxResults: 60,
      );
      final grepFuture = CodebaseSearchService.grepSearch(
        projectPath: projectPath,
        query: effectiveQuery,
        caseSensitive: _caseSensitive,
        fileExtension: ext.isEmpty ? null : ext,
        maxResults: 200,
      );

      final nameHits = await nameFuture;
      final contentHits = await grepFuture;

      if (!mounted) return;
      if (_queryController.text != query) return;

      // Filtro opcional de extensión también en nombres de archivo.
      var filteredNames = nameHits;
      if (ext.isNotEmpty) {
        final normalized = ext.startsWith('.')
            ? ext.toLowerCase()
            : '.${ext.toLowerCase()}';
        filteredNames = nameHits.where((hit) {
          if (hit['type'] == 'directory') return true;
          final path = (hit['filePath'] as String? ?? '').toLowerCase();
          return path.endsWith(normalized);
        }).toList();
      }

      setState(() {
        _nameResults = filteredNames;
        _rawResults = contentHits;
        _searching = false;
        _collapsedFiles.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _nameResults = [];
        _rawResults = [];
        _searching = false;
        _error = e.toString();
      });
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupByFile() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final hit in _rawResults) {
      final file = hit['filePath'] as String? ?? '';
      grouped.putIfAbsent(file, () => []).add(hit);
    }
    return grouped;
  }

  String _absolutePath(String relative) {
    final root = (widget.projectPath ?? '').replaceAll('\\', '/');
    var rel = relative.replaceAll('\\', '/');
    if (rel.endsWith('/')) {
      rel = rel.substring(0, rel.length - 1);
    }
    if (rel.startsWith('/')) return rel;
    if (root.isEmpty) return rel;
    return '$root/$rel';
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByFile();
    final fileCount = grouped.length;
    final matchCount = _rawResults.length;
    final nameCount = _nameResults.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        _buildSearchBox(),
        _buildOptionsRow(),
        _buildStatusBar(nameCount, fileCount, matchCount),
        const Divider(height: 1, color: CursorTheme.border),
        Expanded(child: _buildResults(grouped)),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          const Text(
            'SEARCH',
            style: TextStyle(
              color: CursorTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          if (_searching)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: CursorTheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: TextField(
        controller: _queryController,
        focusNode: _queryFocus,
        style: const TextStyle(
          color: CursorTheme.textPrimary,
          fontSize: 13,
        ),
        cursorColor: CursorTheme.primary,
        decoration: InputDecoration(
          hintText: 'Archivos, carpetas o texto…',
          hintStyle: const TextStyle(
            color: CursorTheme.textDisabled,
            fontSize: 13,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          prefixIcon: const Icon(
            Icons.search,
            size: 16,
            color: CursorTheme.textSecondary,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 28,
          ),
          suffixIcon: _queryController.text.isEmpty
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
                    _queryController.clear();
                  },
                ),
          filled: true,
          fillColor: CursorTheme.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: CursorTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: CursorTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: CursorTheme.primary),
          ),
        ),
        onSubmitted: (_) => _runSearch(),
      ),
    );
  }

  Widget _buildOptionsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Row(
        children: [
          _ToggleChip(
            label: 'Aa',
            tooltip: 'Match Case',
            selected: _caseSensitive,
            onTap: () {
              setState(() => _caseSensitive = !_caseSensitive);
              _scheduleSearch();
            },
          ),
          const SizedBox(width: 4),
          _ToggleChip(
            label: '.*',
            tooltip: 'Use Regular Expression (texto)',
            selected: _useRegex,
            onTap: () {
              setState(() => _useRegex = !_useRegex);
              _scheduleSearch();
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _extensionController,
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 12,
                ),
                cursorColor: CursorTheme.primary,
                decoration: InputDecoration(
                  hintText: 'files to include (e.g. .dart)',
                  hintStyle: const TextStyle(
                    color: CursorTheme.textDisabled,
                    fontSize: 11,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  filled: true,
                  fillColor: CursorTheme.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: CursorTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: CursorTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: CursorTheme.primary),
                  ),
                ),
                onChanged: (_) => _scheduleSearch(),
                onSubmitted: (_) => _runSearch(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(int nameCount, int fileCount, int matchCount) {
    String text;
    if (_error != null) {
      text = _error!;
    } else if (_queryController.text.trim().isEmpty) {
      text = 'Busca por nombre o por texto dentro de archivos';
    } else if (_searching) {
      text = 'Buscando…';
    } else if (nameCount == 0 && matchCount == 0) {
      text = 'Sin resultados';
    } else {
      text =
          '$nameCount nombre(s) · $matchCount texto en $fileCount archivo(s)';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Text(
        text,
        style: TextStyle(
          color: _error != null ? Colors.redAccent : CursorTheme.textSecondary,
          fontSize: 11,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildResults(Map<String, List<Map<String, dynamic>>> grouped) {
    final queryEmpty = _queryController.text.trim().isEmpty;
    if (queryEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 36, color: CursorTheme.textDisabled),
              SizedBox(height: 12),
              Text(
                'Escribe un nombre de archivo,\ncarpeta o un fragmento de código',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: CursorTheme.textDisabled,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_nameResults.isEmpty && grouped.isEmpty && !_searching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No results found.',
            style: TextStyle(
              color: CursorTheme.textDisabled,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    final children = <Widget>[];

    if (_nameResults.isNotEmpty) {
      children.add(
        const _SectionHeader(
          title: 'ARCHIVOS Y CARPETAS',
          icon: Icons.folder_outlined,
        ),
      );
      for (final hit in _nameResults) {
        final relative = hit['filePath'] as String? ?? '';
        final name = hit['name'] as String? ?? relative;
        final isDir = hit['type'] == 'directory';
        final dir = relative.contains('/')
            ? relative
                .replaceAll(RegExp(r'/+$'), '')
                .replaceAll(RegExp(r'[^/]+$'), '')
                .replaceAll(RegExp(r'/+$'), '')
            : '';
        children.add(
          InkWell(
            onTap: () {
              if (isDir) return;
              widget.onSelectResult?.call(_absolutePath(relative), 1);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                children: [
                  Icon(
                    isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                    size: 14,
                    color: isDir
                        ? const Color(0xFFFFB800)
                        : CursorTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: name,
                            style: const TextStyle(
                              color: CursorTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (dir.isNotEmpty)
                            TextSpan(
                              text: '  $dir',
                              style: const TextStyle(
                                color: CursorTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    if (grouped.isNotEmpty) {
      children.add(
        const _SectionHeader(
          title: 'TEXTO EN ARCHIVOS',
          icon: Icons.code,
        ),
      );
      final files = grouped.keys.toList();
      for (final file in files) {
        final hits = grouped[file]!;
        final collapsed = _collapsedFiles.contains(file);
        children.add(
          _FileResultGroup(
            relativePath: file,
            hits: hits,
            collapsed: collapsed,
            query: _queryController.text,
            caseSensitive: _caseSensitive,
            useRegex: _useRegex,
            onToggle: () {
              setState(() {
                if (collapsed) {
                  _collapsedFiles.remove(file);
                } else {
                  _collapsedFiles.add(file);
                }
              });
            },
            onSelect: (lineNumber) {
              widget.onSelectResult?.call(_absolutePath(file), lineNumber);
            },
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: children,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Row(
        children: [
          Icon(icon, size: 12, color: CursorTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              color: CursorTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? CursorTheme.primary.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? CursorTheme.primary : CursorTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? CursorTheme.primary
                  : CursorTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _FileResultGroup extends StatelessWidget {
  final String relativePath;
  final List<Map<String, dynamic>> hits;
  final bool collapsed;
  final String query;
  final bool caseSensitive;
  final bool useRegex;
  final VoidCallback onToggle;
  final void Function(int lineNumber) onSelect;

  const _FileResultGroup({
    required this.relativePath,
    required this.hits,
    required this.collapsed,
    required this.query,
    required this.caseSensitive,
    required this.useRegex,
    required this.onToggle,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final fileName = relativePath.contains('/')
        ? relativePath.split('/').last
        : relativePath;
    final dir = relativePath.contains('/')
        ? relativePath.substring(0, relativePath.lastIndexOf('/'))
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: CursorTheme.surfaceHover,
            child: Row(
              children: [
                Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 16,
                  color: CursorTheme.textSecondary,
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.insert_drive_file_outlined,
                  size: 14,
                  color: CursorTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: RichText(
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: fileName,
                          style: const TextStyle(
                            color: CursorTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (dir.isNotEmpty)
                          TextSpan(
                            text: '  $dir',
                            style: const TextStyle(
                              color: CursorTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: CursorTheme.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${hits.length}',
                    style: const TextStyle(
                      color: CursorTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!collapsed)
          ...hits.map((hit) {
            final lineNumber = hit['lineNumber'] as int? ?? 0;
            final lineContent = hit['lineContent'] as String? ?? '';
            return InkWell(
              onTap: () => onSelect(lineNumber),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 3, 10, 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        '$lineNumber',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: CursorTheme.textDisabled,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HighlightedLine(
                        text: lineContent,
                        query: query,
                        caseSensitive: caseSensitive,
                        useRegex: useRegex,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _HighlightedLine extends StatelessWidget {
  final String text;
  final String query;
  final bool caseSensitive;
  final bool useRegex;

  const _HighlightedLine({
    required this.text,
    required this.query,
    required this.caseSensitive,
    required this.useRegex,
  });

  @override
  Widget build(BuildContext context) {
    final spans = _buildSpans();
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

  List<TextSpan> _buildSpans() {
    const base = TextStyle(
      color: CursorTheme.textPrimary,
      fontSize: 12,
      fontFamily: 'monospace',
    );
    const highlight = TextStyle(
      color: CursorTheme.textPrimary,
      fontSize: 12,
      fontFamily: 'monospace',
      backgroundColor: Color(0xFF5A4A1A),
      fontWeight: FontWeight.w600,
    );

    if (query.isEmpty || text.isEmpty) {
      return [TextSpan(text: text, style: base)];
    }

    RegExp? pattern;
    try {
      pattern = RegExp(
        useRegex ? query : RegExp.escape(query),
        caseSensitive: caseSensitive,
      );
    } on FormatException {
      return [TextSpan(text: text, style: base)];
    }

    final spans = <TextSpan>[];
    var start = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(
          TextSpan(text: text.substring(start, match.start), style: base),
        );
      }
      spans.add(TextSpan(text: match.group(0), style: highlight));
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: base));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text, style: base));
    }
    return spans;
  }
}
