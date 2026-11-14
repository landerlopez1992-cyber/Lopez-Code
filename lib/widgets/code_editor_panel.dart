import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/agent_activity_service.dart';
import '../services/agent_diff_review_service.dart';
import '../services/file_service.dart';
import '../services/openai_service.dart';
import '../services/project_service.dart';
import 'app_toast.dart';
import 'code_language.dart';
import 'code_syntax_controller.dart';
import 'cursor_theme.dart';
import 'diff_review_bar.dart';
import 'editor_backdrop_painter.dart';
import 'editor_breadcrumbs.dart';
import 'editor_symbols.dart';
import 'inline_edit_bar.dart';

/// Estado de una pestaña abierta en el editor.
class EditorOpenTab {
  String? filePath;
  String content;
  String savedContent;
  TextSelection selection;

  EditorOpenTab({
    this.filePath,
    required this.content,
    String? savedContent,
    this.selection = const TextSelection.collapsed(offset: 0),
  }) : savedContent = savedContent ?? content;

  bool get isDirty => content != savedContent;

  String get label {
    if (filePath == null || filePath!.isEmpty) return 'Untitled';
    return filePath!.split('/').last;
  }
}

class CodeEditorPanel extends StatefulWidget {
  final String? filePath;
  final String? initialContent;
  /// Línea 1-based a la que posicionarse al abrir (p. ej. desde Problems).
  final int? initialLine;
  final int? initialColumn;
  final Function(String)? onSave;
  final Function()? onClose;

  /// Notifica al padre qué archivo está activo (path + contenido).
  final void Function(String? path, String content)? onActiveFileChanged;

  const CodeEditorPanel({
    super.key,
    this.filePath,
    this.initialContent,
    this.initialLine,
    this.initialColumn,
    this.onSave,
    this.onClose,
    this.onActiveFileChanged,
  });

  @override
  State<CodeEditorPanel> createState() => _CodeEditorPanelState();
}

class _CodeEditorPanelState extends State<CodeEditorPanel>
    with SingleTickerProviderStateMixin {
  late CodeSyntaxController _codeController;
  final ScrollController _lineNumbersScrollController = ScrollController();
  final ScrollController _codeScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  bool _isDirty = false;
  String? _currentFilePath;
  bool _isSaving = false;
  bool _isProgrammaticUpdate = false;
  String _savedContent = '';
  StreamSubscription<FileSystemEvent>? _fileWatchSubscription;
  Timer? _fileWatchDebounce;
  DateTime? _lastLocalSave;
  bool _isScrolling = false; // Flag para evitar loops infinitos al sincronizar

  // ── Multi-file tabs ─────────────────────────────────────────────
  final List<EditorOpenTab> _tabs = [];
  int _activeTabIndex = 0;
  String? _lastParentOpenPath;
  int? _lastParentLine;
  int? _lastParentColumn;

  // ── Resaltado en vivo del agente (línea preseleccionada + pulso) ──
  final AgentActivityService _agentActivity = AgentActivityService();
  late final AnimationController _agentPulse;
  int? _agentFocusLine0; // 0-based; null = agente no está en este archivo

  // ── Inline Edit (Cmd+K / Ctrl+K) ─────────────────────────────────
  bool _inlineEditVisible = false;
  InlineEditPhase _inlineEditPhase = InlineEditPhase.prompt;
  int _inlineEditStart = 0;
  int _inlineEditEnd = 0;
  String _inlineEditOriginal = '';
  String? _inlineEditProposed;
  String? _inlineEditError;

  // ── Estado derivado del cursor (línea actual, ocurrencias, breadcrumbs) ──
  static const EdgeInsets _codePadding = EdgeInsets.fromLTRB(10, 8, 24, 8);
  static final RegExp _identifierRe = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');
  String? _linesSource;
  List<String> _lines = const [''];
  int _cursorLine = 0;
  int _cursorColumn = 0;
  bool _selectionSingleLine = true;
  String? _highlightWord;
  List<EditorSymbol> _symbols = const [];
  String? _projectRoot;
  late final double _charWidth = _measureCharWidth();
  final AgentDiffReviewService _diffReview = AgentDiffReviewService();

  FileDiffReview? get _activeReview => _diffReview.reviewFor(_currentFilePath);
  List<DiffHunk> get _activeHunks => _activeReview?.hunks ?? const [];

  @override
  void initState() {
    super.initState();
    _currentFilePath = widget.filePath;
    _savedContent = widget.initialContent ?? '';
    _codeController = CodeSyntaxController(
      text: _savedContent,
      language: CodeLanguage.forPath(widget.filePath),
    );
    _codeController.addListener(_handleCodeChanged);
    _codeController.addListener(_refreshCursorState);
    _diffReview.addListener(_onDiffReviewChanged);
    _agentPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _agentActivity.addListener(_onAgentActivityChanged);
    _refreshCursorState(notify: false);
    ProjectService.getProjectPath().then((root) {
      if (mounted) setState(() => _projectRoot = root);
    });
    _lineNumbersScrollController.addListener(_syncLineNumbersScroll);
    _codeScrollController.addListener(_syncCodeScroll);

    _tabs.add(EditorOpenTab(
      filePath: widget.filePath,
      content: _savedContent,
      savedContent: _savedContent,
    ));
    _activeTabIndex = 0;
    _lastParentOpenPath = widget.filePath;
    _lastParentLine = widget.initialLine;
    _lastParentColumn = widget.initialColumn;

    _watchCurrentFile();
    print('📝 CodeEditorPanel.initState: Contenido inicial (${widget.initialContent?.length ?? 0} caracteres)');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToLine(widget.initialLine, widget.initialColumn);
      _notifyActiveFile();
      _syncAgentFocusFromService(selectLine: true);
    });
  }

  @override
  void didUpdateWidget(CodeEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pathChanged = widget.filePath != _lastParentOpenPath;
    final lineChanged = widget.initialLine != _lastParentLine ||
        widget.initialColumn != _lastParentColumn;
    // Agente reescribió el mismo archivo en disco → refrescar buffer en vivo.
    final contentReload = widget.filePath != null &&
        widget.initialContent != null &&
        widget.filePath == _lastParentOpenPath &&
        widget.initialContent != oldWidget.initialContent;
    final contentFromParent = widget.initialContent != null &&
        widget.filePath != null &&
        (pathChanged || contentReload);

    if (widget.filePath != null &&
        (pathChanged || lineChanged || contentReload)) {
      _lastParentOpenPath = widget.filePath;
      // Forzar re-salto aunque sea la misma línea tras un edit del agente.
      if (contentReload) {
        _lastParentLine = null;
        _lastParentColumn = null;
      }
      _lastParentLine = widget.initialLine;
      _lastParentColumn = widget.initialColumn;
      _openOrFocusTab(
        path: widget.filePath,
        content: contentFromParent
            ? widget.initialContent!
            : (widget.initialContent ??
                _findTabContent(widget.filePath) ??
                ''),
        line: widget.initialLine,
        column: widget.initialColumn,
        preferParentContent: contentFromParent,
      );
      // Tras reload del agente: mantener pulso / preselección de línea.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncAgentFocusFromService(selectLine: true);
      });
    }
  }

  String? _findTabContent(String? path) {
    if (path == null) return null;
    for (final t in _tabs) {
      if (t.filePath == path) return t.content;
    }
    return null;
  }

  void _notifyActiveFile() {
    widget.onActiveFileChanged?.call(_currentFilePath, _codeController.text);
  }

  static double _measureCharWidth() {
    const sample = 'MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM';
    final tp = TextPainter(
      text: const TextSpan(text: sample, style: EditorMetrics.textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = tp.width / sample.length;
    tp.dispose();
    return width;
  }

  /// Recalcula línea/columna del cursor, palabra a resaltar y símbolos del
  /// breadcrumb. Corre en cada cambio de texto o selección.
  void _refreshCursorState({bool notify = true}) {
    final text = _codeController.text;
    if (!identical(text, _linesSource)) {
      _linesSource = text;
      _lines = text.split('\n');
    }
    final sel = _codeController.selection;
    final offset = (sel.isValid ? sel.extentOffset : 0).clamp(0, text.length);

    var line = 0;
    var lineStart = 0;
    for (var i = 0; i < offset; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        line++;
        lineStart = i + 1;
      }
    }
    final column = offset - lineStart;
    final singleLine = !sel.isValid ||
        sel.isCollapsed ||
        !text
            .substring(
              sel.start.clamp(0, text.length),
              sel.end.clamp(0, text.length),
            )
            .contains('\n');
    final word = _wordForSelection(text, sel);
    final lineChanged = line != _cursorLine;

    final changed = lineChanged ||
        column != _cursorColumn ||
        word != _highlightWord ||
        singleLine != _selectionSingleLine ||
        !identical(_lines, _linesForSymbols);
    if (!changed) return;

    _cursorLine = line;
    _cursorColumn = column;
    _highlightWord = word;
    _selectionSingleLine = singleLine;
    _linesForSymbols = _lines;
    _symbols = EditorSymbolFinder.symbolsAt(
      _lines,
      line,
      _codeController.language,
    );
    if (notify && mounted) setState(() {});
  }

  List<String>? _linesForSymbols;

  String? _wordForSelection(String text, TextSelection sel) {
    if (!sel.isValid || text.isEmpty) return null;
    if (!sel.isCollapsed) {
      final selected = text.substring(
        sel.start.clamp(0, text.length),
        sel.end.clamp(0, text.length),
      );
      return _identifierRe.hasMatch(selected) ? selected : null;
    }
    bool isIdent(int c) =>
        (c >= 0x61 && c <= 0x7A) ||
        (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x30 && c <= 0x39) ||
        c == 0x5F ||
        c == 0x24;
    var start = sel.extentOffset.clamp(0, text.length);
    var end = start;
    while (start > 0 && isIdent(text.codeUnitAt(start - 1))) {
      start--;
    }
    while (end < text.length && isIdent(text.codeUnitAt(end))) {
      end++;
    }
    if (end - start < 2) return null;
    final word = text.substring(start, end);
    return _identifierRe.hasMatch(word) ? word : null;
  }

  /// Posiciona el caret y el scroll en línea/columna 1-based.
  /// [selectWholeLine] preselecciona toda la línea (feedback del agente).
  void _jumpToLine(
    int? targetLine,
    int? targetColumn, {
    bool selectWholeLine = false,
  }) {
    if (targetLine == null || targetLine < 1) return;

    final text = _codeController.text;
    if (text.isEmpty) return;

    final lines = text.split('\n');
    final lineIndex = (targetLine - 1).clamp(0, lines.length - 1);
    var lineStart = 0;
    for (var i = 0; i < lineIndex; i++) {
      lineStart += lines[i].length + 1; // +1 por '\n'
    }
    final col =
        ((targetColumn ?? 1) - 1).clamp(0, lines[lineIndex].length);
    final caret = (lineStart + col).clamp(0, text.length);
    final lineEnd =
        (lineStart + lines[lineIndex].length).clamp(0, text.length);

    _isProgrammaticUpdate = true;
    _codeController.selection = selectWholeLine
        ? TextSelection(baseOffset: lineStart, extentOffset: lineEnd)
        : TextSelection.collapsed(offset: caret);
    _isProgrammaticUpdate = false;

    final jumpY = (lineIndex * EditorMetrics.lineHeight) - 40;
    if (_codeScrollController.hasClients) {
      _codeScrollController.jumpTo(
        jumpY.clamp(0.0, _codeScrollController.position.maxScrollExtent),
      );
    }
  }

  void _persistActiveTabBuffer() {
    if (_tabs.isEmpty || _activeTabIndex < 0 || _activeTabIndex >= _tabs.length) {
      return;
    }
    final tab = _tabs[_activeTabIndex];
    tab.content = _codeController.text;
    tab.selection = _codeController.selection;
  }

  void _loadTabIntoEditor(EditorOpenTab tab, {int? line, int? column}) {
    _isProgrammaticUpdate = true;
    _codeController.language = CodeLanguage.forPath(tab.filePath);
    _codeController.value = TextEditingValue(
      text: tab.content,
      selection: tab.selection.isValid
          ? tab.selection
          : TextSelection.collapsed(offset: 0),
    );
    _currentFilePath = tab.filePath;
    _savedContent = tab.savedContent;
    _isDirty = tab.isDirty;
    _isProgrammaticUpdate = false;
    _watchCurrentFile();
    if (line != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToLine(line, column);
      });
    }
    _notifyActiveFile();
  }

  void _openOrFocusTab({
    required String? path,
    required String content,
    int? line,
    int? column,
    bool preferParentContent = false,
  }) {
    _persistActiveTabBuffer();

    final existingIndex = path == null
        ? -1
        : _tabs.indexWhere((t) => t.filePath == path);

    if (existingIndex >= 0) {
      setState(() {
        _activeTabIndex = existingIndex;
        if (preferParentContent) {
          // Reload desde disco/agente: el contenido del padre es la verdad.
          _tabs[existingIndex].content = content;
          _tabs[existingIndex].savedContent = content;
        }
      });
      _loadTabIntoEditor(_tabs[existingIndex], line: line, column: column);
      setState(() {});
      return;
    }

    final tab = EditorOpenTab(
      filePath: path,
      content: content,
      savedContent: content,
    );
    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
    });
    _loadTabIntoEditor(tab, line: line, column: column);
    setState(() {});
  }

  Future<void> _switchToTab(int index) async {
    if (index < 0 || index >= _tabs.length || index == _activeTabIndex) return;
    _closeInlineEdit();
    _persistActiveTabBuffer();
    setState(() => _activeTabIndex = index);
    _loadTabIntoEditor(_tabs[index]);
    setState(() {});
  }

  Future<void> _requestCloseTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];

    // Persistir buffer activo antes de evaluar dirty
    if (index == _activeTabIndex) {
      _persistActiveTabBuffer();
    }

    if (tab.isDirty) {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: CursorTheme.surface,
          title: Text(
            '¿Cerrar ${tab.label}?',
            style: const TextStyle(color: CursorTheme.textPrimary, fontSize: 16),
          ),
          content: const Text(
            'Hay cambios sin guardar. ¿Qué deseas hacer?',
            style: TextStyle(color: CursorTheme.textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('No guardar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: CursorTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
      if (action == null || action == 'cancel') return;
      if (action == 'save') {
        if (index != _activeTabIndex) {
          await _switchToTab(index);
        }
        await _saveFile();
        if (_tabs[index].isDirty) return; // save failed / cancelled
      }
    }

    _closeTabAt(index);
  }

  void _closeTabAt(int index) {
    if (_tabs.isEmpty) return;
    final closingActive = index == _activeTabIndex;
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _activeTabIndex = 0;
      } else if (closingActive) {
        _activeTabIndex = index.clamp(0, _tabs.length - 1);
      } else if (index < _activeTabIndex) {
        _activeTabIndex -= 1;
      }
    });

    if (_tabs.isEmpty) {
      widget.onClose?.call();
      return;
    }

    _loadTabIntoEditor(_tabs[_activeTabIndex]);
    setState(() {});
  }

  void _handleCodeChanged() {
    if (_isProgrammaticUpdate || !mounted) return;
    if (_tabs.isNotEmpty &&
        _activeTabIndex >= 0 &&
        _activeTabIndex < _tabs.length) {
      _tabs[_activeTabIndex].content = _codeController.text;
      _tabs[_activeTabIndex].selection = _codeController.selection;
    }
    final nextDirty = _codeController.text != _savedContent;
    if (nextDirty != _isDirty) {
      setState(() {
        _isDirty = nextDirty;
      });
    } else {
      // Actualiza números de línea / tabs dirty.
      setState(() {});
    }
    // No notificar al padre en cada tecla (evita rebuilds); solo en
    // cambio de pestaña / guardar / abrir.
  }

  void _replaceEditorContent(String content) {
    _isProgrammaticUpdate = true;
    final selectionOffset =
        _codeController.selection.baseOffset.clamp(0, content.length);
    _codeController.value = TextEditingValue(
      text: content,
      selection: TextSelection.collapsed(offset: selectionOffset),
    );
    _savedContent = content;
    _isDirty = false;
    if (_tabs.isNotEmpty &&
        _activeTabIndex >= 0 &&
        _activeTabIndex < _tabs.length) {
      _tabs[_activeTabIndex].content = content;
      _tabs[_activeTabIndex].savedContent = content;
    }
    _isProgrammaticUpdate = false;
    if (mounted) setState(() {});
    _notifyActiveFile();
  }

  Future<void> _watchCurrentFile() async {
    await _fileWatchSubscription?.cancel();
    _fileWatchSubscription = null;

    final path = _currentFilePath;
    if (path == null || path.isEmpty) return;

    final file = File(path);
    final parent = file.parent;
    if (!await parent.exists()) return;

    _fileWatchSubscription = parent.watch().listen((event) {
      if (event.path != file.path) return;
      _fileWatchDebounce?.cancel();
      _fileWatchDebounce = Timer(
        const Duration(milliseconds: 250),
        _reloadOpenFileFromDisk,
      );
    });
  }

  Future<void> _reloadOpenFileFromDisk() async {
    final path = _currentFilePath;
    if (path == null || path.isEmpty) return;

    // Evita que nuestro propio Guardar provoque una recarga redundante.
    final localSave = _lastLocalSave;
    if (localSave != null &&
        DateTime.now().difference(localSave) < const Duration(seconds: 1)) {
      return;
    }

    final file = File(path);
    if (!await file.exists()) return;
    final diskContent = await file.readAsString();
    if (!mounted || diskContent == _codeController.text) return;
    _replaceEditorContent(diskContent);
  }

  void _syncLineNumbersScroll() {
    if (!_isScrolling && _lineNumbersScrollController.hasClients) {
      _isScrolling = true;
      if (_codeScrollController.hasClients) {
        _codeScrollController.jumpTo(_lineNumbersScrollController.offset);
      }
      _isScrolling = false;
    }
  }

  void _syncCodeScroll() {
    if (!_isScrolling && _codeScrollController.hasClients) {
      _isScrolling = true;
      if (_lineNumbersScrollController.hasClients) {
        _lineNumbersScrollController.jumpTo(_codeScrollController.offset);
      }
      _isScrolling = false;
    }
  }

  @override
  void dispose() {
    _fileWatchDebounce?.cancel();
    _fileWatchSubscription?.cancel();
    _agentActivity.removeListener(_onAgentActivityChanged);
    _agentPulse.dispose();
    _diffReview.removeListener(_onDiffReviewChanged);
    _codeController.removeListener(_handleCodeChanged);
    _codeController.removeListener(_refreshCursorState);
    _codeController.dispose();
    _lineNumbersScrollController.removeListener(_syncLineNumbersScroll);
    _codeScrollController.removeListener(_syncCodeScroll);
    _lineNumbersScrollController.dispose();
    _codeScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _onDiffReviewChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onAgentActivityChanged() {
    if (!mounted) return;
    _syncAgentFocusFromService(selectLine: true);
  }

  bool _pathMatchesAgent(String? filePath, String? agentPath) {
    if (filePath == null || agentPath == null) return false;
    final a = agentPath.replaceAll('\\', '/');
    final c = filePath.replaceAll('\\', '/');
    if (a.isEmpty || c.isEmpty) return false;
    if (a == c) return true;
    final aBase = a.split('/').last;
    final cBase = c.split('/').last;
    if (aBase.isNotEmpty && aBase == cBase) {
      if (c.endsWith('/$aBase') || a.endsWith('/$cBase')) return true;
      // Match relativo vs absoluto.
      if (c.endsWith(a) || a.endsWith(c)) return true;
    }
    return false;
  }

  void _syncAgentFocusFromService({bool selectLine = false}) {
    final agentPath = _agentActivity.activePath;
    final line1 = _agentActivity.focusLine;
    final onThisFile = _pathMatchesAgent(_currentFilePath, agentPath);

    if (!onThisFile || agentPath == null || agentPath.isEmpty) {
      if (_agentFocusLine0 != null) {
        setState(() => _agentFocusLine0 = null);
      }
      if (_agentPulse.isAnimating) {
        _agentPulse.stop();
        _agentPulse.value = 0;
      }
      return;
    }

    final lines = _codeController.text.split('\n');
    final maxIdx = math.max(0, lines.length - 1);
    final line0 = ((line1 ?? 1) - 1).clamp(0, maxIdx).toInt();
    final changed = _agentFocusLine0 != line0;
    setState(() => _agentFocusLine0 = line0);
    if (!_agentPulse.isAnimating) {
      _agentPulse.repeat(reverse: true);
    }
    if (selectLine || changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _jumpToLine(
          line0 + 1,
          1,
          selectWholeLine: true,
        );
      });
    }
  }

  void _jumpToDiffHunk(DiffHunk hunk) {
    final line = hunk.hasAdditions ? hunk.startLine : hunk.startLine;
    // Dejar aire arriba para las líneas fantasma eliminadas.
    final ghost = hunk.removedLines.length;
    final targetLine = (line - ghost) < 1 ? 1 : (line - ghost);
    _jumpToLine(targetLine, 1);
  }

  Future<void> _reloadAfterDiffMutation() async {
    final path = _currentFilePath;
    if (path == null || path.isEmpty) return;
    _lastLocalSave = DateTime.now();
    final file = File(path);
    if (!await file.exists()) return;
    final content = await file.readAsString();
    if (!mounted) return;
    _replaceEditorContent(content);
  }

  Future<void> _keepActiveHunk() async {
    final review = _activeReview;
    final hunk = review?.activeHunk;
    final path = _currentFilePath;
    if (review == null || hunk == null || path == null) return;
    _diffReview.acceptHunk(path, hunk.id);
  }

  Future<void> _undoActiveHunk() async {
    final review = _activeReview;
    final hunk = review?.activeHunk;
    final path = _currentFilePath;
    if (review == null || hunk == null || path == null) return;
    final ok = await _diffReview.rejectHunk(path, hunk.id);
    if (ok) await _reloadAfterDiffMutation();
  }

  Future<void> _keepAllHunks() async {
    final path = _currentFilePath;
    if (path == null) return;
    _diffReview.acceptAll(path);
  }

  Future<void> _undoAllHunks() async {
    final path = _currentFilePath;
    if (path == null) return;
    final ok = await _diffReview.rejectAll(path);
    if (ok) await _reloadAfterDiffMutation();
  }

  void _selectHunk(DiffHunk hunk) {
    final path = _currentFilePath;
    final review = _activeReview;
    if (path == null || review == null) return;
    final index = review.hunks.indexWhere((h) => h.id == hunk.id);
    if (index < 0) return;
    _diffReview.setActiveHunk(path, index);
    _jumpToDiffHunk(hunk);
  }

  Future<void> _saveFile() async {
    if (_currentFilePath == null || _currentFilePath!.isEmpty) {
      _showSaveAsDialog();
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Verificar que el archivo está en el proyecto
      final isInProject = await ProjectService.isPathInProject(_currentFilePath!);
      if (!isInProject) {
        throw Exception('El archivo debe estar dentro del proyecto seleccionado');
      }

      await FileService.writeFile(_currentFilePath!, _codeController.text);
      _lastLocalSave = DateTime.now();
      _savedContent = _codeController.text;
      if (_tabs.isNotEmpty &&
          _activeTabIndex >= 0 &&
          _activeTabIndex < _tabs.length) {
        _tabs[_activeTabIndex].content = _codeController.text;
        _tabs[_activeTabIndex].savedContent = _codeController.text;
      }
      
      setState(() {
        _isDirty = false;
        _isSaving = false;
      });
      _notifyActiveFile();

      widget.onSave?.call(_currentFilePath!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Archivo guardado: ${_currentFilePath!.split('/').last}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSaveAsDialog() {
    final TextEditingController pathController = TextEditingController(
      text: _currentFilePath ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guardar archivo como'),
        content: TextField(
          controller: pathController,
          decoration: const InputDecoration(
            labelText: 'Ruta del archivo',
            hintText: '/ruta/al/archivo.ext',
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final path = pathController.text.trim();
              if (path.isNotEmpty) {
                _codeController.language = CodeLanguage.forPath(path);
                setState(() {
                  _currentFilePath = path;
                  if (_tabs.isNotEmpty &&
                      _activeTabIndex >= 0 &&
                      _activeTabIndex < _tabs.length) {
                    _tabs[_activeTabIndex].filePath = path;
                  }
                });
                Navigator.of(context).pop();
                await _saveFile();
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _codeController.text));
    AppToast.show(context, message: 'Código copiado');
  }

  void _selectAll() {
    _codeController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _codeController.text.length,
    );
  }

  void _insertTab() {
    final value = _codeController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    const indentation = '  ';
    final nextText = value.text.replaceRange(start, end, indentation);
    _codeController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(
        offset: start + indentation.length,
      ),
    );
  }

  /// Abre la barra Inline Edit sobre la selección (o la línea del cursor).
  void _openInlineEdit() {
    final text = _codeController.text;
    final sel = _codeController.selection;
    var start = sel.isValid ? sel.start : text.length;
    var end = sel.isValid ? sel.end : text.length;
    if (start > end) {
      final tmp = start;
      start = end;
      end = tmp;
    }

    // Sin selección → línea completa del cursor.
    if (start == end) {
      final lineStart =
          start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
      var lineEnd = text.indexOf('\n', start);
      if (lineEnd < 0) lineEnd = text.length;
      start = lineStart;
      end = lineEnd;
    }

    setState(() {
      _inlineEditVisible = true;
      _inlineEditPhase = InlineEditPhase.prompt;
      _inlineEditStart = start;
      _inlineEditEnd = end;
      _inlineEditOriginal = text.substring(start, end);
      _inlineEditProposed = null;
      _inlineEditError = null;
    });
  }

  void _closeInlineEdit() {
    if (!_inlineEditVisible) return;
    setState(() {
      _inlineEditVisible = false;
      _inlineEditPhase = InlineEditPhase.prompt;
      _inlineEditProposed = null;
      _inlineEditError = null;
    });
  }

  Future<void> _submitInlineEditInstruction(String instruction) async {
    setState(() {
      _inlineEditPhase = InlineEditPhase.generating;
      _inlineEditError = null;
    });

    try {
      final text = _codeController.text;
      final before = _contextLinesBefore(text, _inlineEditStart, 15);
      final after = _contextLinesAfter(text, _inlineEditEnd, 15);

      final proposed = await OpenAIService.generateInlineEdit(
        selectedCode: _inlineEditOriginal,
        instruction: instruction,
        beforeContext: before,
        afterContext: after,
        filePath: _currentFilePath,
      );

      if (!mounted) return;
      setState(() {
        _inlineEditProposed = proposed;
        _inlineEditPhase = InlineEditPhase.preview;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineEditError = e.toString().replaceFirst('Exception: ', '');
        _inlineEditPhase = InlineEditPhase.prompt;
      });
    }
  }

  void _acceptInlineEdit() {
    final proposed = _inlineEditProposed;
    if (proposed == null) return;

    final text = _codeController.text;
    final start = _inlineEditStart.clamp(0, text.length);
    final end = _inlineEditEnd.clamp(start, text.length);
    final next = text.replaceRange(start, end, proposed);

    _isProgrammaticUpdate = true;
    _codeController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + proposed.length,
      ),
    );
    _isProgrammaticUpdate = false;
    if (_tabs.isNotEmpty &&
        _activeTabIndex >= 0 &&
        _activeTabIndex < _tabs.length) {
      _tabs[_activeTabIndex].content = next;
      _tabs[_activeTabIndex].selection =
          TextSelection.collapsed(offset: start + proposed.length);
    }

    setState(() {
      _isDirty = next != _savedContent;
      _inlineEditVisible = false;
      _inlineEditProposed = null;
      _inlineEditPhase = InlineEditPhase.prompt;
    });
    _notifyActiveFile();
  }

  String _contextLinesBefore(String text, int offset, int lineCount) {
    if (offset <= 0 || lineCount <= 0) return '';
    final before = text.substring(0, offset);
    final lines = before.split('\n');
    if (lines.isEmpty) return '';
    // Si el offset cae al inicio de línea, la última entrada suele ser ''.
    final meaningful = lines.last.isEmpty && lines.length > 1
        ? lines.sublist(0, lines.length - 1)
        : lines;
    final take = meaningful.length < lineCount
        ? meaningful
        : meaningful.sublist(meaningful.length - lineCount);
    return take.join('\n');
  }

  String _contextLinesAfter(String text, int offset, int lineCount) {
    if (offset >= text.length || lineCount <= 0) return '';
    final after = text.substring(offset);
    final lines = after.split('\n');
    // Si empieza justo tras '\n', la primera puede ser el resto; si offset
    // estaba a mitad de línea no incluimos esa línea parcial como "after".
    final startIndex = after.startsWith('\n') ? 1 : 0;
    final slice = lines.skip(startIndex).take(lineCount).toList();
    return slice.join('\n');
  }

  static const Color _lineNumberColor = Color(0xFF6E7681);
  static const Color _activeLineNumberColor = Color(0xFFCCCCCC);
  static const Color _agentLineNumberColor = Color(0xFF4FC3F7);

  Widget _buildLineNumbers(int lineCount) {
    final active =
        _cursorLine.clamp(0, math.max(0, lineCount - 1)).toInt();
    final agent = _agentFocusLine0;
    String range(int from, int to) =>
        List.generate(to - from, (i) => '${from + i + 1}').join('\n');
    const numberStyle = TextStyle(
      fontFamily: EditorMetrics.fontFamily,
      fontFamilyFallback: EditorMetrics.fontFamilyFallback,
      fontSize: 12,
      height: EditorMetrics.lineHeightFactor,
      color: _lineNumberColor,
    );

    // Si el agente está en otra línea, pintar números con span especial.
    if (agent != null &&
        agent >= 0 &&
        agent < lineCount &&
        agent != active) {
      final spans = <InlineSpan>[];
      for (var i = 0; i < lineCount; i++) {
        if (i > 0) spans.add(const TextSpan(text: '\n'));
        final isAgent = i == agent;
        final isCursor = i == active;
        spans.add(
          TextSpan(
            text: '${i + 1}',
            style: TextStyle(
              color: isAgent
                  ? _agentLineNumberColor
                  : (isCursor ? _activeLineNumberColor : _lineNumberColor),
              fontWeight:
                  isAgent || isCursor ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        );
      }
      return Text.rich(
        TextSpan(style: numberStyle, children: spans),
        textAlign: TextAlign.right,
        strutStyle: EditorMetrics.strut,
      );
    }

    return Text.rich(
      TextSpan(
        style: numberStyle,
        children: [
          if (active > 0) TextSpan(text: '${range(0, active)}\n'),
          TextSpan(
            text: '${active + 1}',
            style: TextStyle(
              color: agent == active
                  ? _agentLineNumberColor
                  : _activeLineNumberColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (active < lineCount - 1)
            TextSpan(text: '\n${range(active + 1, lineCount)}'),
        ],
      ),
      textAlign: TextAlign.right,
      strutStyle: EditorMetrics.strut,
    );
  }

  Widget _buildEditableEditor() {
    final lines = _lines;
    final lineCount = lines.isEmpty ? 1 : lines.length;
    final digits = lineCount.toString().length.clamp(2, 6);
    final lineNumberWidth = 8 + digits * _charWidth + 14;
    final longestLineLength = lines.fold<int>(
      0,
      (longest, line) => line.length > longest ? line.length : longest,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: lineNumberWidth,
          color: CursorTheme.editorBackground,
          child: SingleChildScrollView(
            controller: _lineNumbersScrollController,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              8,
              _codePadding.top,
              14,
              _codePadding.bottom,
            ),
            child: _buildLineNumbers(lineCount),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final estimatedContentWidth = longestLineLength * _charWidth * 1.05 +
                  _codePadding.horizontal +
                  80;
              final editorWidth = estimatedContentWidth > constraints.maxWidth
                  ? estimatedContentWidth
                  : constraints.maxWidth;

              return CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
                      _saveFile,
                  const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                      _saveFile,
                  const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                      _openInlineEdit,
                  const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                      _openInlineEdit,
                  const SingleActivator(LogicalKeyboardKey.tab): _insertTab,
                  if (_inlineEditVisible)
                    const SingleActivator(LogicalKeyboardKey.escape):
                        _closeInlineEdit,
                },
                child: Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _horizontalScrollController,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: editorWidth,
                              height: constraints.maxHeight,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: AnimatedBuilder(
                                      animation: _agentPulse,
                                      builder: (context, _) {
                                        return CustomPaint(
                                          painter: EditorBackdropPainter(
                                            lines: lines,
                                            verticalScroll:
                                                _codeScrollController,
                                            padding: _codePadding,
                                            charWidth: _charWidth,
                                            cursorLine: _cursorLine,
                                            showCurrentLine:
                                                _selectionSingleLine,
                                            highlightWord: _highlightWord,
                                            hunks: _activeHunks,
                                            activeHunkId:
                                                _activeReview?.activeHunk?.id,
                                            agentFocusLine: _agentFocusLine0,
                                            agentPulse: _agentPulse.value,
                                            repaint: Listenable.merge([
                                              _codeScrollController,
                                              _agentPulse,
                                            ]),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  TextField(
                                    controller: _codeController,
                                    scrollController: _codeScrollController,
                                    expands: true,
                                    minLines: null,
                                    maxLines: null,
                                    keyboardType: TextInputType.multiline,
                                    textAlignVertical: TextAlignVertical.top,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    style: EditorMetrics.textStyle,
                                    strutStyle: EditorMetrics.strut,
                                    cursorColor: const Color(0xFFAEAFAD),
                                    cursorWidth: 2,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isCollapsed: true,
                                      contentPadding: _codePadding,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_activeHunks.isNotEmpty)
                          DiffOverviewRuler(
                            hunks: _activeHunks,
                            lineCount: lineCount,
                            activeHunkId: _activeReview?.activeHunk?.id,
                            onTapHunk: _selectHunk,
                          ),
                      ],
                    ),
                    if (_inlineEditVisible)
                      Positioned(
                        left: 24,
                        right: 24,
                        top: 12,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: InlineEditBar(
                            phase: _inlineEditPhase,
                            originalCode: _inlineEditOriginal,
                            proposedCode: _inlineEditProposed,
                            errorMessage: _inlineEditError,
                            onCancel: _closeInlineEdit,
                            onAccept: _acceptInlineEdit,
                            onSubmitInstruction: _submitInlineEditInstruction,
                          ),
                        ),
                      ),
                    if (_activeHunks.isNotEmpty &&
                        _activeReview != null &&
                        !_inlineEditVisible)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: DiffReviewBar(
                            review: _activeReview!,
                            onPrevious: () {
                              final path = _currentFilePath;
                              if (path == null) return;
                              _diffReview.selectPrevious(path);
                              final hunk = _activeReview?.activeHunk;
                              if (hunk != null) _jumpToDiffHunk(hunk);
                            },
                            onNext: () {
                              final path = _currentFilePath;
                              if (path == null) return;
                              _diffReview.selectNext(path);
                              final hunk = _activeReview?.activeHunk;
                              if (hunk != null) _jumpToDiffHunk(hunk);
                            },
                            onUndo: () => unawaited(_undoActiveHunk()),
                            onKeep: () => unawaited(_keepActiveHunk()),
                            onUndoAll: () => unawaited(_undoAllHunks()),
                            onKeepAll: () => unawaited(_keepAllHunks()),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Parsing legacy (HTML/CSS) — conservado por si se reutiliza en previews.
  List<TextSpan> _parseCodeOptimized(String code) {
    // Colores exactos de Cursor IDE Dark+ theme
    const tagColor = Color(0xFF569CD6); // Azul para tags HTML
    const attributeColor = Color(0xFF92C5F7); // Azul claro para atributos
    const valueColor = Color(0xFFCE9178); // Naranja para valores de atributos
    const commentColor = Color(0xFF6A9955); // Verde para comentarios
    const textColor = Color(0xFFD4D4D4); // Gris claro para texto normal
    const keywordColor = Color(0xFFC586C0); // Morado para palabras clave CSS
    const stringColor = Color(0xFFCE9178); // Naranja para strings
    const punctuationColor = Color(0xFFD4D4D4); // Gris para puntuación

    final spans = <TextSpan>[];
    final lines = code.split('\n');
    
    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      
      if (line.isEmpty) {
        spans.add(const TextSpan(text: '\n'));
        continue;
      }

      int i = 0;
      while (i < line.length) {
        // PRIORIDAD 1: Detectar comentarios HTML: <!-- ... -->
        if (i < line.length - 3 && line.substring(i, i + 4) == '<!--') {
          final commentEnd = line.indexOf('-->', i);
          if (commentEnd != -1) {
            spans.add(TextSpan(
              text: line.substring(i, commentEnd + 3),
              style: const TextStyle(color: commentColor),
            ));
            i = commentEnd + 3;
            continue;
          } else {
            // Comentario sin cerrar, aplicar color hasta el final
            spans.add(TextSpan(
              text: line.substring(i),
              style: const TextStyle(color: commentColor),
            ));
            i = line.length;
            continue;
          }
        }

        // PRIORIDAD 2: Detectar comentarios CSS: /* ... */
        if (i < line.length - 1 && line.substring(i, i + 2) == '/*') {
          final commentEnd = line.indexOf('*/', i);
          if (commentEnd != -1) {
            spans.add(TextSpan(
              text: line.substring(i, commentEnd + 2),
              style: const TextStyle(color: commentColor),
            ));
            i = commentEnd + 2;
            continue;
          } else {
            spans.add(TextSpan(
              text: line.substring(i),
              style: const TextStyle(color: commentColor),
            ));
            i = line.length;
            continue;
          }
        }

        // PRIORIDAD 3: Detectar tags HTML: <tag> o </tag>
        if (line[i] == '<') {
          final tagEnd = line.indexOf('>', i);
          if (tagEnd != -1) {
            final tagContent = line.substring(i, tagEnd + 1);
            
            // Tag de cierre: </tag>
            if (tagContent.startsWith('</')) {
              spans.add(const TextSpan(text: '</', style: TextStyle(color: tagColor)));
              final tagName = tagContent.substring(2, tagContent.length - 1).trim();
              if (tagName.isNotEmpty) {
                spans.add(TextSpan(
                  text: tagName,
                  style: const TextStyle(color: tagColor, fontWeight: FontWeight.w500),
                ));
              }
              spans.add(const TextSpan(text: '>', style: TextStyle(color: tagColor)));
              i = tagEnd + 1;
              continue;
            }
            
            // Tag de apertura o auto-cerrado: <tag> o <tag />
            final isSelfClosing = tagContent.endsWith('/>');
            final tagNameEnd = tagContent.indexOf(' ', 1);
            final tagNameEnd2 = tagContent.indexOf('>', 1);
            final tagNameEnd3 = isSelfClosing ? tagContent.indexOf('/', 1) : -1;
            
            int tagNameEndFinal = tagNameEnd;
            if (tagNameEnd == -1 || (tagNameEnd2 != -1 && tagNameEnd2 < tagNameEnd)) {
              tagNameEndFinal = tagNameEnd2 != -1 ? tagNameEnd2 : tagContent.length - 1;
            }
            if (isSelfClosing && tagNameEnd3 != -1 && tagNameEnd3 < tagNameEndFinal) {
              tagNameEndFinal = tagNameEnd3;
            }
            
            spans.add(const TextSpan(text: '<', style: TextStyle(color: tagColor)));
            
            if (tagNameEndFinal > 1) {
              final tagName = tagContent.substring(1, tagNameEndFinal).trim();
              if (tagName.isNotEmpty) {
                spans.add(TextSpan(
                  text: tagName,
                  style: const TextStyle(color: tagColor, fontWeight: FontWeight.w500),
                ));
              }
            }
            
            // Parsear atributos si existen
            if (tagNameEndFinal < tagContent.length - (isSelfClosing ? 2 : 1)) {
              final attrsStart = tagNameEndFinal;
              final attrsEnd = isSelfClosing ? tagContent.length - 2 : tagContent.length - 1;
              if (attrsEnd > attrsStart) {
                final attrs = tagContent.substring(attrsStart, attrsEnd);
                _parseAttributes(attrs, spans, attributeColor, valueColor, stringColor, punctuationColor);
              }
            }
            
            if (isSelfClosing) {
              spans.add(const TextSpan(text: ' />', style: TextStyle(color: tagColor)));
            } else {
              spans.add(const TextSpan(text: '>', style: TextStyle(color: tagColor)));
            }
            
            i = tagEnd + 1;
            continue;
          }
        }
        
        // PRIORIDAD 4: Detectar propiedades CSS: property: value;
        // Solo si no estamos dentro de un tag HTML
        if (line.contains(':') && !line.substring(0, i).contains('<')) {
          final colonIndex = line.indexOf(':', i);
          if (colonIndex != -1) {
            // Verificar que no sea parte de un atributo HTML (dentro de comillas)
            final beforeColon = line.substring(0, colonIndex);
            final doubleQuotes = beforeColon.split('"').length - 1;
            final singleQuotes = beforeColon.split("'").length - 1;
            
            // Si hay un número impar de comillas antes de ':', estamos dentro de un atributo
            if (doubleQuotes % 2 == 0 && singleQuotes % 2 == 0) {
              final property = line.substring(i, colonIndex).trim();
              final semicolonIndex = line.indexOf(';', colonIndex);
              final value = semicolonIndex != -1 
                  ? line.substring(colonIndex + 1, semicolonIndex).trim()
                  : line.substring(colonIndex + 1).trim();
              
              if (property.isNotEmpty) {
                spans.add(TextSpan(
                  text: property,
                  style: const TextStyle(color: keywordColor),
                ));
                spans.add(const TextSpan(text: ':', style: TextStyle(color: punctuationColor)));
                if (value.isNotEmpty) {
                  spans.add(TextSpan(
                    text: ' $value',
                    style: const TextStyle(color: valueColor),
                  ));
                }
                if (semicolonIndex != -1) {
                  spans.add(const TextSpan(text: ';', style: TextStyle(color: punctuationColor)));
                  i = semicolonIndex + 1;
                } else {
                  i = line.length;
                }
                continue;
              }
            }
          }
        }
        
        // Texto normal
        spans.add(TextSpan(
          text: line[i],
          style: const TextStyle(color: textColor),
        ));
        i++;
      }
      
      if (lineIndex < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    
    return spans;
  }

  /// Editor simplificado para archivos grandes (sin syntax highlighting completo)
  Widget _buildSimpleEditor(String code) {
    final lines = code.split('\n');
    final lineCount = lines.length;
    final lineNumbers = List.generate(lineCount, (index) => '${index + 1}');
    final maxLineNumberWidth = lineNumbers.last.length;
    final lineNumberWidth = 50 + (maxLineNumberWidth * 8.0);
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Panel de números de línea
        SingleChildScrollView(
          controller: _lineNumbersScrollController,
          child: Container(
            width: lineNumberWidth,
            padding: const EdgeInsets.only(left: 16, right: 8, top: 16, bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              border: Border(
                right: BorderSide(color: CursorTheme.border, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: lineNumbers.map((lineNum) {
                return Container(
                  height: 20.8,
                  alignment: Alignment.centerRight,
                  child: Text(
                    lineNum,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: CursorTheme.editorLineNumber,
                      height: 1.6,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // Panel de código (sin syntax highlighting para mejor rendimiento)
        Expanded(
          child: SingleChildScrollView(
            controller: _codeScrollController,
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 16, right: 16),
            child: SelectableText(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: CursorTheme.codeText,
                height: 1.6,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Construye el editor con numeración de líneas
  Widget _buildEditorWithLineNumbers(String code, List<TextSpan> spans) {
    final lineCount = code.isEmpty ? 1 : code.split('\n').length;
    final lineNumbers = List.generate(lineCount, (index) => '${index + 1}');
    final maxLineNumberWidth = lineNumbers.isEmpty ? 1 : lineNumbers.last.length;
    final lineNumberWidth = 50 + (maxLineNumberWidth * 8.0);
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Panel de números de línea con scroll sincronizado
        SingleChildScrollView(
          controller: _lineNumbersScrollController,
          child: Container(
            width: lineNumberWidth,
            padding: const EdgeInsets.only(left: 16, right: 8, top: 16, bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              border: Border(
                right: BorderSide(color: CursorTheme.border, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: lineNumbers.map((lineNum) {
                return Container(
                  height: 20.8, // height: 1.6 * 13 (fontSize)
                  alignment: Alignment.centerRight,
                  child: Text(
                    lineNum,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: CursorTheme.editorLineNumber,
                      height: 1.6,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // Panel de código con scroll sincronizado
        Expanded(
          child: SingleChildScrollView(
            controller: _codeScrollController,
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 16, right: 16),
            child: SelectableText.rich(
              TextSpan(
                children: spans,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.6,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Parsea atributos HTML y crea TextSpans con colores (mejorado)
  void _parseAttributes(String attrs, List<TextSpan> spans, Color attributeColor, Color valueColor, Color stringColor, Color punctuationColor) {
    if (attrs.trim().isEmpty) return;
    
    // Buscar atributos en el formato: attr="value" o attr='value' o attr=value
    final regexDouble = RegExp(r'(\S+)\s*=\s*"([^"]*)"');
    final regexSingle = RegExp(r"(\S+)\s*=\s*'([^']*)'");
    final regexNoQuotes = RegExp(r"(\S+)\s*=\s*(\S+)");
    
    int lastIndex = 0;
    final allMatches = <RegExpMatch>[];
    
    // Buscar todos los matches
    allMatches.addAll(regexDouble.allMatches(attrs));
    allMatches.addAll(regexSingle.allMatches(attrs));
    allMatches.addAll(regexNoQuotes.allMatches(attrs));
    
    // Ordenar por posición de inicio
    allMatches.sort((a, b) => a.start.compareTo(b.start));
    
    // Eliminar duplicados (preferir comillas sobre sin comillas)
    final filteredMatches = <RegExpMatch>[];
    for (int i = 0; i < allMatches.length; i++) {
      bool isDuplicate = false;
      for (int j = 0; j < i; j++) {
        if (allMatches[i].start < allMatches[j].end && allMatches[i].end > allMatches[j].start) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        filteredMatches.add(allMatches[i]);
      }
    }
    
    for (final match in filteredMatches) {
      // Texto antes del atributo (espacios, etc.)
      if (match.start > lastIndex) {
        final beforeText = attrs.substring(lastIndex, match.start);
        spans.add(TextSpan(
          text: beforeText,
          style: TextStyle(color: punctuationColor),
        ));
      }
      
      // Nombre del atributo
      final attrName = match.group(1)!;
      spans.add(TextSpan(
        text: attrName,
        style: TextStyle(color: attributeColor),
      ));
      
      // Signo = y espacios alrededor
      final equalsIndex = attrs.indexOf('=', match.start);
      if (equalsIndex != -1) {
        final beforeEquals = attrs.substring(match.start + attrName.length, equalsIndex);
        spans.add(TextSpan(
          text: beforeEquals,
          style: TextStyle(color: punctuationColor),
        ));
        spans.add(TextSpan(
          text: '=',
          style: TextStyle(color: punctuationColor),
        ));
        
        // Valor del atributo
        final afterEquals = attrs.substring(equalsIndex + 1, match.end);
        final trimmedAfter = afterEquals.trim();
        
        if (trimmedAfter.startsWith('"') || trimmedAfter.startsWith("'")) {
          // Atributo con comillas
          final quote = trimmedAfter[0];
          spans.add(TextSpan(
            text: quote,
            style: TextStyle(color: stringColor),
          ));
          if (trimmedAfter.length > 2) {
            spans.add(TextSpan(
              text: trimmedAfter.substring(1, trimmedAfter.length - 1),
              style: TextStyle(color: valueColor),
            ));
          }
          spans.add(TextSpan(
            text: quote,
            style: TextStyle(color: stringColor),
          ));
        } else {
          // Atributo sin comillas
          spans.add(TextSpan(
            text: trimmedAfter,
            style: TextStyle(color: valueColor),
          ));
        }
      }
      
      lastIndex = match.end;
    }
    
    // Texto restante
    if (lastIndex < attrs.length) {
      spans.add(TextSpan(
        text: attrs.substring(lastIndex),
        style: TextStyle(color: punctuationColor),
      ));
    }
  }

  static const Color _modifiedColor = Color(0xFFE2C08D);

  Widget _buildTabBar() {
    return Container(
      height: 35,
      decoration: const BoxDecoration(
        color: CursorTheme.background,
        border: Border(
          bottom: BorderSide(color: CursorTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              itemBuilder: (context, index) {
                final tab = _tabs[index];
                final selected = index == _activeTabIndex;
                final dirty = tab.isDirty || (selected && _isDirty);
                final pendingReview =
                    _diffReview.hasPending(tab.filePath);
                final fileIcon = FileTypeIcon.forPath(tab.filePath);
                final labelColor = dirty
                    ? _modifiedColor
                    : selected
                        ? CursorTheme.textPrimary
                        : CursorTheme.textSecondary;
                return Material(
                  color: selected
                      ? CursorTheme.editorBackground
                      : CursorTheme.surface,
                  child: InkWell(
                    onTap: () => _switchToTab(index),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          right: const BorderSide(
                            color: CursorTheme.border,
                            width: 1,
                          ),
                          top: BorderSide(
                            color: selected
                                ? CursorTheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            fileIcon.icon,
                            size: 14,
                            color: selected
                                ? fileIcon.color
                                : fileIcon.color.withValues(alpha: 0.75),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              tab.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: labelColor,
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (pendingReview) ...[
                            const SizedBox(width: 6),
                            const _DiffTabBadge(),
                          ] else if (dirty) ...[
                            const SizedBox(width: 6),
                            const Text(
                              'M',
                              style: TextStyle(
                                color: _modifiedColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => _requestCloseTab(index),
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: CursorTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.auto_fix_high, size: 16),
            color: CursorTheme.primary,
            onPressed: _openInlineEdit,
            tooltip: 'Inline Edit (Cmd/Ctrl+K)',
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.select_all, size: 16),
            color: CursorTheme.textSecondary,
            onPressed: _selectAll,
            tooltip: 'Seleccionar todo',
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            color: CursorTheme.textSecondary,
            onPressed: _copyToClipboard,
            tooltip: 'Copiar',
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.save, size: 16),
            color: _isDirty ? Colors.green : CursorTheme.textSecondary,
            onPressed: _isDirty ? _saveFile : null,
            tooltip: 'Guardar (Cmd/Ctrl+S)',
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CursorTheme.editorBackground,
      child: Column(
        children: [
          _buildTabBar(),
          EditorBreadcrumbs(
            filePath: _currentFilePath,
            projectRoot: _projectRoot,
            symbols: _symbols,
          ),

          // Editor multilínea editable con números de línea sincronizados.
          Expanded(
            child: Container(
              color: CursorTheme.editorBackground,
              child: _buildEditableEditor(),
            ),
          ),

          // Barra de estado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: CursorTheme.primary,
              border: Border(
                top: BorderSide(color: CursorTheme.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                if (_currentFilePath != null) ...[
                  Icon(Icons.insert_drive_file, size: 12, color: Colors.white70),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _currentFilePath!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  'Ln ${_cursorLine + 1}, Col ${_cursorColumn + 1}   '
                  '${_lines.length} líneas   '
                  '${_codeController.language.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge verde/rojo en la pestaña mientras haya hunks sin revisar.
class _DiffTabBadge extends StatelessWidget {
  const _DiffTabBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFF3FB950),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 2),
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFFF85149),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

