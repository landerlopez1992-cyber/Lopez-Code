import 'code_language.dart';

enum EditorSymbolKind { classLike, method, field, block, heading }

class EditorSymbol {
  final String name;
  final EditorSymbolKind kind;

  const EditorSymbol(this.name, this.kind);
}

/// Símbolos que contienen a una línea (clase › método › campo, bloques de
/// Gradle, claves YAML/JSON, títulos Markdown), deducidos por sangría.
class EditorSymbolFinder {
  static const int _maxLookback = 4000;
  static const int _maxDepth = 4;

  static List<EditorSymbol> symbolsAt(
    List<String> lines,
    int lineIndex,
    CodeLanguage lang,
  ) {
    if (lines.isEmpty || lineIndex < 0 || lineIndex >= lines.length) {
      return const [];
    }
    if (lang.mode == LexerMode.markdown) return _markdownChain(lines, lineIndex);
    if (lang.mode == LexerMode.plain || lang.mode == LexerMode.xml) {
      return const [];
    }

    final result = <EditorSymbol>[];
    final cursorLine = lines[lineIndex];
    var limitIndent = 1 << 30;
    EditorSymbol? ownField;

    if (cursorLine.trim().isNotEmpty) {
      final own = _match(cursorLine, lang);
      if (own != null) {
        result.add(own);
        limitIndent = _indent(cursorLine);
      } else {
        ownField = _matchField(cursorLine, lang);
        if (ownField != null) limitIndent = _indent(cursorLine);
      }
    }

    final stop = (lineIndex - _maxLookback).clamp(0, lineIndex);
    for (var i = lineIndex - 1; i >= stop && limitIndent > 0; i--) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty || _isNoise(trimmed)) continue;
      final indent = _indent(line);
      if (indent >= limitIndent) continue;
      limitIndent = indent;
      final symbol = _match(line, lang);
      if (symbol != null) result.insert(0, symbol);
    }

    if (ownField != null &&
        (result.isEmpty || result.last.kind == EditorSymbolKind.classLike)) {
      result.add(ownField);
    }
    return result.length > _maxDepth
        ? result.sublist(result.length - _maxDepth)
        : result;
  }

  static bool _isNoise(String trimmed) {
    final c = trimmed[0];
    return c == '}' ||
        c == ')' ||
        c == ']' ||
        c == '@' ||
        c == '*' ||
        trimmed.startsWith('//') ||
        trimmed.startsWith('/*') ||
        trimmed.startsWith('#');
  }

  static int _indent(String line) {
    var n = 0;
    for (var i = 0; i < line.length; i++) {
      final c = line.codeUnitAt(i);
      if (c == 0x20) {
        n++;
      } else if (c == 0x09) {
        n += 4;
      } else {
        break;
      }
    }
    return n;
  }

  // ── Patrones por lenguaje ────────────────────────────────────────────

  static final _dartClass = RegExp(
    r'^\s*(?:(?:abstract|base|sealed|final|interface|mixin)\s+)*'
    r'(?:class|mixin|enum|extension(?:\s+type)?)\s+([A-Za-z_]\w*)',
  );
  static final _dartGetter = RegExp(r'\bget\s+([A-Za-z_]\w*)\s*(?:=>|\{|$)');
  static final _dartMethod = RegExp(
    r'^\s*((?:[\w<>?,\[\]]+\s+)*?)(?:set\s+|operator\s*)?'
    r'([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)\s*(?:<[^>]*>)?\s*\(',
  );
  static final _dartField = RegExp(
    r'^\s*(?:(?:static|final|const|late|var|external|covariant)\s+)*'
    r'(?:[\w<>?,\[\]]+\s+)?([A-Za-z_]\w*)\s*(?:=(?![=>])|;)',
  );

  static final _kotlinClass = RegExp(
    r'\b(?:class|object|interface)\s+([A-Za-z_]\w*)',
  );
  static final _kotlinFun = RegExp(
    r'\bfun\s+(?:<[^>]*>\s*)?(?:[\w.]+\.)?([A-Za-z_]\w*)',
  );
  static final _kotlinField = RegExp(r'^\s*(?:[\w]+\s+)*(?:val|var)\s+([A-Za-z_]\w*)');

  static final _swiftClass = RegExp(
    r'\b(?:class|struct|enum|protocol|extension|actor)\s+([A-Za-z_]\w*)',
  );
  static final _swiftFunc = RegExp(r'\bfunc\s+([A-Za-z_]\w*)');
  static final _swiftInit = RegExp(r'^\s*(?:[\w]+\s+)*(init|deinit)\b');
  static final _swiftField = RegExp(r'^\s*(?:[\w@]+\s+)*(?:let|var)\s+([A-Za-z_]\w*)');

  static final _groovyClass = RegExp(r'\b(?:class|interface|enum)\s+([A-Za-z_]\w*)');
  static final _groovyDef = RegExp(r'\bdef\s+([A-Za-z_]\w*)\s*\(');
  static final _groovyBlock = RegExp(
    r'^\s*([A-Za-z_][\w.]*)\s*(?:\([^)]*\))?\s*\{',
  );

  static final _shellFunction = RegExp(
    r'^\s*(?:function\s+)?([A-Za-z_][\w-]*)\s*\(\)\s*\{?',
  );

  static final _yamlKey = RegExp(
    r'''^\s*(?:-\s+)?("[^"]*"|'[^']*'|[^\s#:'"][^#:]*?):(?:\s|$)''',
  );
  static final _jsonKey = RegExp(r'^\s*"([^"]+)"\s*:');

  static EditorSymbol? _match(String line, CodeLanguage lang) {
    switch (lang.id) {
      case 'dart':
        return _matchDart(line, lang);
      case 'kotlin':
        return _first(line, _kotlinClass, EditorSymbolKind.classLike) ??
            _first(line, _kotlinFun, EditorSymbolKind.method);
      case 'swift':
        return _first(line, _swiftClass, EditorSymbolKind.classLike) ??
            _first(line, _swiftFunc, EditorSymbolKind.method) ??
            _first(line, _swiftInit, EditorSymbolKind.method);
      case 'groovy':
        final block = _groovyBlock.firstMatch(line);
        if (block != null && !lang.controlKeywords.contains(block.group(1))) {
          return EditorSymbol(block.group(1)!, EditorSymbolKind.block);
        }
        return _first(line, _groovyClass, EditorSymbolKind.classLike) ??
            _first(line, _groovyDef, EditorSymbolKind.method);
      case 'shell':
        final fn = _shellFunction.firstMatch(line);
        if (fn != null && !lang.controlKeywords.contains(fn.group(1))) {
          return EditorSymbol(fn.group(1)!, EditorSymbolKind.method);
        }
        return null;
      case 'yaml':
        final key = _yamlKey.firstMatch(line);
        if (key == null) return null;
        return EditorSymbol(_unquote(key.group(1)!.trim()), EditorSymbolKind.block);
      case 'json':
        return _first(line, _jsonKey, EditorSymbolKind.block);
      default:
        return null;
    }
  }

  static EditorSymbol? _matchField(String line, CodeLanguage lang) {
    switch (lang.id) {
      case 'dart':
        final m = _dartField.firstMatch(line);
        if (m == null) return null;
        final firstWord = line.trimLeft().split(RegExp(r'[\s(]')).first;
        if (lang.controlKeywords.contains(firstWord)) return null;
        return EditorSymbol(m.group(1)!, EditorSymbolKind.field);
      case 'kotlin':
        return _first(line, _kotlinField, EditorSymbolKind.field);
      case 'swift':
        return _first(line, _swiftField, EditorSymbolKind.field);
      default:
        return null;
    }
  }

  static EditorSymbol? _matchDart(String line, CodeLanguage lang) {
    final cls = _dartClass.firstMatch(line);
    if (cls != null) return EditorSymbol(cls.group(1)!, EditorSymbolKind.classLike);

    final getter = _dartGetter.firstMatch(line);
    if (getter != null) {
      return EditorSymbol(getter.group(1)!, EditorSymbolKind.method);
    }

    final m = _dartMethod.firstMatch(line);
    if (m == null) return null;
    final trimmed = line.trim();
    if (trimmed.endsWith(';') && !trimmed.contains('=>')) return null;
    if (trimmed.endsWith(',')) return null;

    final prefixWords = m
        .group(1)!
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final name = m.group(2)!;
    if (lang.controlKeywords.contains(name)) return null;
    if (prefixWords.any(lang.controlKeywords.contains)) return null;

    final onlyConstOrNew = prefixWords.isEmpty ||
        prefixWords.every((w) => w == 'const' || w == 'new');
    if (onlyConstOrNew) {
      // Sin tipo de retorno: solo constructores declarados (`Foo({`, `Foo() {`).
      final bare = name.split('.').first.replaceFirst('_', '');
      final capitalized = bare.isNotEmpty &&
          bare[0].toUpperCase() == bare[0] &&
          bare[0].toLowerCase() != bare[0];
      final declares = trimmed.endsWith('({') ||
          (trimmed.endsWith('{') && trimmed.contains(')')) ||
          trimmed.contains(') :');
      if (!capitalized || !declares) return null;
    }
    return EditorSymbol(name, EditorSymbolKind.method);
  }

  static EditorSymbol? _first(String line, RegExp re, EditorSymbolKind kind) {
    final m = re.firstMatch(line);
    return m == null ? null : EditorSymbol(m.group(1)!, kind);
  }

  static String _unquote(String s) {
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  static final _mdHeading = RegExp(r'^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$');

  static List<EditorSymbol> _markdownChain(List<String> lines, int lineIndex) {
    final chain = <EditorSymbol>[];
    var level = 7;
    var inFence = false;
    final fenceState = List<bool>.filled(lineIndex + 1, false);
    for (var i = 0; i <= lineIndex; i++) {
      final t = lines[i].trimLeft();
      if (t.startsWith('```') || t.startsWith('~~~')) inFence = !inFence;
      fenceState[i] = inFence;
    }
    for (var i = lineIndex; i >= 0 && level > 1; i--) {
      if (fenceState[i]) continue;
      final m = _mdHeading.firstMatch(lines[i]);
      if (m == null) continue;
      final l = m.group(1)!.length;
      if (l >= level) continue;
      level = l;
      chain.insert(0, EditorSymbol(m.group(2)!, EditorSymbolKind.heading));
    }
    return chain.length > _maxDepth
        ? chain.sublist(chain.length - _maxDepth)
        : chain;
  }
}
