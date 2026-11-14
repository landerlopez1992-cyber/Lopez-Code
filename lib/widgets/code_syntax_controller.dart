import 'package:flutter/material.dart';

import 'code_language.dart';

/// Tipografía y métrica de línea compartidas por texto, números de línea y
/// el painter de fondo. La altura de línea es fija (strut forzado) para que
/// guías, línea actual y ocurrencias caigan exactamente sobre el texto.
class EditorMetrics {
  static const double fontSize = 13;
  static const double lineHeightFactor = 1.45;
  static const double lineHeight = fontSize * lineHeightFactor;
  static const String fontFamily = 'Menlo';
  static const List<String> fontFamilyFallback = [
    'SF Mono',
    'Monaco',
    'JetBrains Mono',
    'Courier New',
    'monospace',
  ];

  static const TextStyle textStyle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: fontSize,
    height: lineHeightFactor,
    color: SyntaxColors.text,
  );

  static const StrutStyle strut = StrutStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: fontSize,
    height: lineHeightFactor,
    forceStrutHeight: true,
  );
}

/// [TextEditingController] con resaltado multi-lenguaje en vivo vía
/// [buildTextSpan]. El tokenizado se cachea por texto+lenguaje, así mover el
/// cursor no re-tokeniza el archivo.
class CodeSyntaxController extends TextEditingController {
  CodeSyntaxController({super.text, CodeLanguage language = CodeLanguage.plain})
      : _language = language;

  static const int _maxHighlightChars = 200000;

  CodeLanguage _language;
  String? _cachedText;
  String? _cachedLanguageId;
  List<InlineSpan>? _cachedSpans;

  CodeLanguage get language => _language;

  set language(CodeLanguage value) {
    if (value.id == _language.id) return;
    _language = value;
    _cachedText = null;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    const base = EditorMetrics.textStyle;
    if (text.isEmpty) return const TextSpan(style: base, text: '');
    if (_language.mode == LexerMode.plain || text.length > _maxHighlightChars) {
      return TextSpan(style: base, text: text);
    }
    if (_cachedText != text || _cachedLanguageId != _language.id) {
      _cachedSpans = _SyntaxTokenizer(_language).tokenize(text);
      _cachedText = text;
      _cachedLanguageId = _language.id;
    }
    return TextSpan(style: base, children: _cachedSpans);
  }
}

class _SyntaxTokenizer {
  _SyntaxTokenizer(this.lang);

  final CodeLanguage lang;
  final List<InlineSpan> _spans = [];
  final StringBuffer _pending = StringBuffer();
  Color? _pendingColor;
  FontWeight? _pendingWeight;

  List<InlineSpan> tokenize(String source) {
    switch (lang.mode) {
      case LexerMode.yaml:
        _tokenizeYaml(source);
        break;
      case LexerMode.xml:
        _tokenizeXml(source);
        break;
      case LexerMode.markdown:
        _tokenizeMarkdown(source);
        break;
      case LexerMode.code:
      case LexerMode.json:
        _tokenizeCode(source);
        break;
      case LexerMode.plain:
        _emit(source, SyntaxColors.text);
        break;
    }
    _flush();
    return _spans;
  }

  // ── Emisión con fusión de tokens contiguos del mismo estilo ──────────

  void _emit(String text, Color color, {FontWeight? weight}) {
    if (text.isEmpty) return;
    if (_pending.isNotEmpty &&
        (_pendingColor != color || _pendingWeight != weight)) {
      _flush();
    }
    _pendingColor = color;
    _pendingWeight = weight;
    _pending.write(text);
  }

  void _flush() {
    if (_pending.isEmpty) return;
    _spans.add(TextSpan(
      text: _pending.toString(),
      style: TextStyle(color: _pendingColor, fontWeight: _pendingWeight),
    ));
    _pending.clear();
  }

  // ── Lenguajes tipo C (Dart, Groovy, Kotlin, Swift, Shell, JSON) ──────

  void _tokenizeCode(String s) {
    final n = s.length;
    final isJson = lang.mode == LexerMode.json;
    var i = 0;
    var depth = 0;
    var lastSig = -1;

    while (i < n) {
      final c = s.codeUnitAt(i);

      if (_isSpace(c)) {
        final start = i;
        while (i < n && _isSpace(s.codeUnitAt(i))) {
          i++;
        }
        _emit(s.substring(start, i), SyntaxColors.text);
        continue;
      }

      final lc = lang.lineComment;
      if (lc != null &&
          s.startsWith(lc, i) &&
          (lc != '#' || i == 0 || _isSpace(s.codeUnitAt(i - 1)))) {
        var end = s.indexOf('\n', i);
        if (end < 0) end = n;
        _emit(s.substring(i, end), SyntaxColors.comment);
        i = end;
        continue;
      }

      if (lang.blockComments && s.startsWith('/*', i)) {
        var end = s.indexOf('*/', i + 2);
        end = end < 0 ? n : end + 2;
        _emit(s.substring(i, end), SyntaxColors.comment);
        i = end;
        continue;
      }

      if (lang.tripleQuotes) {
        final rawPrefix = (c == 0x72 || c == 0x52) && _isTripleQuoteAt(s, i + 1);
        if (rawPrefix || _isTripleQuoteAt(s, i)) {
          final qStart = rawPrefix ? i + 1 : i;
          final quote = s.substring(qStart, qStart + 3);
          var end = s.indexOf(quote, qStart + 3);
          end = end < 0 ? n : end + 3;
          _emit(s.substring(i, end), SyntaxColors.string);
          lastSig = 0x22;
          i = end;
          continue;
        }
      }

      if (c == 0x27 || c == 0x22) {
        final start = i;
        i = _skipString(s, i);
        final isKey = isJson && _nextNonSpace(s, i) == 0x3A;
        _emit(
          s.substring(start, i),
          isKey ? SyntaxColors.variable : SyntaxColors.string,
        );
        lastSig = c;
        continue;
      }

      if (lang.dollarVariables && c == 0x24 && i + 1 < n) {
        final start = i;
        i++;
        if (s.codeUnitAt(i) == 0x7B) {
          final close = s.indexOf('}', i);
          i = close < 0 ? n : close + 1;
        } else {
          while (i < n && _isIdentChar(s.codeUnitAt(i))) {
            i++;
          }
          if (i == start + 1) i++;
        }
        _emit(s.substring(start, i), SyntaxColors.variable);
        lastSig = 0x41;
        continue;
      }

      if (lang.annotations && c == 0x40 && i + 1 < n &&
          _isIdentStart(s.codeUnitAt(i + 1))) {
        final start = i;
        i++;
        while (i < n && _isIdentChar(s.codeUnitAt(i))) {
          i++;
        }
        _emit(s.substring(start, i), SyntaxColors.annotation);
        lastSig = 0x41;
        continue;
      }

      if (_isDigit(c) ||
          (c == 0x2D && isJson && i + 1 < n && _isDigit(s.codeUnitAt(i + 1)))) {
        final start = i;
        i++;
        while (i < n) {
          final ch = s.codeUnitAt(i);
          if (_isIdentChar(ch) || ch == 0x2E) {
            if (ch == 0x2E && (i + 1 >= n || !_isDigit(s.codeUnitAt(i + 1)))) {
              break;
            }
            i++;
          } else {
            break;
          }
        }
        _emit(s.substring(start, i), SyntaxColors.number);
        lastSig = 0x30;
        continue;
      }

      if (_isIdentStart(c)) {
        final start = i;
        i++;
        while (i < n && _isIdentChar(s.codeUnitAt(i))) {
          i++;
        }
        final word = s.substring(start, i);
        _emit(word, _colorForIdentifier(word, lastSig, _nextNonSpace(s, i)));
        lastSig = 0x41;
        continue;
      }

      if (c == 0x28 || c == 0x5B || c == 0x7B) {
        _emit(s[i], SyntaxColors.brackets[depth % 3]);
        depth++;
        lastSig = c;
        i++;
        continue;
      }
      if (c == 0x29 || c == 0x5D || c == 0x7D) {
        depth = depth > 0 ? depth - 1 : 0;
        _emit(s[i], SyntaxColors.brackets[depth % 3]);
        lastSig = c;
        i++;
        continue;
      }

      _emit(s[i], SyntaxColors.punctuation);
      lastSig = c;
      i++;
    }
  }

  Color _colorForIdentifier(String word, int lastSig, int next) {
    final afterDot = lastSig == 0x2E;
    if (!afterDot && lang.controlKeywords.contains(word)) {
      return SyntaxColors.controlKeyword;
    }
    if (!afterDot && lang.declKeywords.contains(word)) {
      return SyntaxColors.declKeyword;
    }
    if (lang.constants.contains(word)) return SyntaxColors.declKeyword;
    if (lang.builtinTypes.contains(word)) return SyntaxColors.type;
    final capitalized = lang.capitalizedTypes && _isUpper(word.codeUnitAt(0));
    if (capitalized) return SyntaxColors.type;
    if (next == 0x28) return SyntaxColors.function;
    return lang.colorPlainIdentifiers ? SyntaxColors.variable : SyntaxColors.text;
  }

  // ── YAML (línea a línea) ─────────────────────────────────────────────

  static final RegExp _yamlKey = RegExp(
    r'''^(\s*)(-\s+)?("[^"]*"|'[^']*'|[^\s#:'"\-][^#:]*?|-[^\s#:][^#:]*?)(:)(?=\s|$)''',
  );
  static final RegExp _yamlListItem = RegExp(r'^(\s*)(-)(\s+|$)');
  static final RegExp _yamlNumber = RegExp(r'^[-+]?(\d[\d_]*)(\.\d+)?([eE][-+]?\d+)?$');

  void _tokenizeYaml(String s) {
    final lines = s.split('\n');
    for (var li = 0; li < lines.length; li++) {
      final line = lines[li];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('#')) {
        _emit(line, SyntaxColors.comment);
      } else if (trimmed == '---' || trimmed == '...') {
        _emit(line, SyntaxColors.punctuation);
      } else {
        final key = _yamlKey.firstMatch(line);
        if (key != null) {
          _emit(key.group(1)!, SyntaxColors.text);
          if (key.group(2) != null) {
            _emit(key.group(2)!, SyntaxColors.punctuation);
          }
          _emit(key.group(3)!, SyntaxColors.declKeyword);
          _emit(':', SyntaxColors.punctuation);
          _yamlValue(line.substring(key.end));
        } else {
          final item = _yamlListItem.firstMatch(line);
          if (item != null) {
            _emit(item.group(1)!, SyntaxColors.text);
            _emit(item.group(2)!, SyntaxColors.punctuation);
            _emit(item.group(3)!, SyntaxColors.text);
            _yamlValue(line.substring(item.end));
          } else {
            _yamlValue(line);
          }
        }
      }
      if (li < lines.length - 1) _emit('\n', SyntaxColors.text);
    }
  }

  void _yamlValue(String rest) {
    if (rest.isEmpty) return;
    var commentAt = -1;
    int? quote;
    for (var i = 0; i < rest.length; i++) {
      final ch = rest.codeUnitAt(i);
      if (quote != null) {
        if (ch == quote) quote = null;
      } else if (ch == 0x22 || ch == 0x27) {
        quote = ch;
      } else if (ch == 0x23 && (i == 0 || _isSpace(rest.codeUnitAt(i - 1)))) {
        commentAt = i;
        break;
      }
    }
    final value = commentAt < 0 ? rest : rest.substring(0, commentAt);
    final leading = value.length - value.trimLeft().length;
    final core = value.trim();
    final trailing = value.length - leading - core.length;
    _emit(value.substring(0, leading), SyntaxColors.text);
    if (core.isNotEmpty) {
      final Color color;
      if (core.startsWith('"') || core.startsWith("'")) {
        color = SyntaxColors.string;
      } else if (_yamlNumber.hasMatch(core)) {
        color = SyntaxColors.number;
      } else if (lang.constants.contains(core.toLowerCase())) {
        color = SyntaxColors.declKeyword;
      } else if (core.startsWith('&') || core.startsWith('*')) {
        color = SyntaxColors.type;
      } else if (core == '|' || core == '>' || core == '|-' || core == '>-') {
        color = SyntaxColors.punctuation;
      } else {
        color = SyntaxColors.string;
      }
      _emit(core, color);
    }
    if (trailing > 0) {
      _emit(value.substring(value.length - trailing), SyntaxColors.text);
    }
    if (commentAt >= 0) {
      _emit(rest.substring(commentAt), SyntaxColors.comment);
    }
  }

  // ── XML / HTML / plist ───────────────────────────────────────────────

  void _tokenizeXml(String s) {
    final n = s.length;
    var i = 0;
    while (i < n) {
      if (s.startsWith('<!--', i)) {
        var end = s.indexOf('-->', i + 4);
        end = end < 0 ? n : end + 3;
        _emit(s.substring(i, end), SyntaxColors.comment);
        i = end;
        continue;
      }
      if (s.startsWith('<![CDATA[', i)) {
        var end = s.indexOf(']]>', i);
        end = end < 0 ? n : end + 3;
        _emit(s.substring(i, end), SyntaxColors.string);
        i = end;
        continue;
      }
      if (s.codeUnitAt(i) == 0x3C) {
        final start = i;
        i++;
        if (i < n && (s[i] == '/' || s[i] == '?' || s[i] == '!')) i++;
        _emit(s.substring(start, i), SyntaxColors.tagBracket);
        final nameStart = i;
        while (i < n && !_isSpace(s.codeUnitAt(i)) && s[i] != '>' && s[i] != '/') {
          i++;
        }
        _emit(s.substring(nameStart, i), SyntaxColors.declKeyword);
        while (i < n) {
          final ch = s.codeUnitAt(i);
          if (ch == 0x3E) {
            _emit('>', SyntaxColors.tagBracket);
            i++;
            break;
          }
          if (_isSpace(ch)) {
            final ws = i;
            while (i < n && _isSpace(s.codeUnitAt(i))) {
              i++;
            }
            _emit(s.substring(ws, i), SyntaxColors.text);
          } else if (ch == 0x2F || ch == 0x3F) {
            _emit(s[i], SyntaxColors.tagBracket);
            i++;
          } else if (ch == 0x22 || ch == 0x27) {
            final qs = i;
            i = _skipString(s, i);
            _emit(s.substring(qs, i), SyntaxColors.string);
          } else if (ch == 0x3D) {
            _emit('=', SyntaxColors.punctuation);
            i++;
          } else {
            final as = i;
            while (i < n) {
              final a = s.codeUnitAt(i);
              if (_isSpace(a) || a == 0x3D || a == 0x3E || a == 0x2F ||
                  a == 0x22 || a == 0x27) {
                break;
              }
              i++;
            }
            if (i == as) i++;
            _emit(s.substring(as, i), SyntaxColors.variable);
          }
        }
        continue;
      }
      var end = s.indexOf('<', i);
      if (end < 0) end = n;
      _emit(s.substring(i, end), SyntaxColors.text);
      i = end;
    }
  }

  // ── Markdown ─────────────────────────────────────────────────────────

  static final RegExp _mdHeading = RegExp(r'^\s{0,3}#{1,6}\s');
  static final RegExp _mdList = RegExp(r'^(\s*)([-*+]|\d+[.)])(\s+)');

  void _tokenizeMarkdown(String s) {
    final lines = s.split('\n');
    var inFence = false;
    for (var li = 0; li < lines.length; li++) {
      final line = lines[li];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        inFence = !inFence;
        _emit(line, SyntaxColors.comment);
      } else if (inFence) {
        _emit(line, SyntaxColors.string);
      } else if (_mdHeading.hasMatch(line)) {
        _emit(line, SyntaxColors.declKeyword, weight: FontWeight.bold);
      } else if (trimmed.startsWith('>')) {
        _emit(line, SyntaxColors.comment);
      } else {
        final list = _mdList.firstMatch(line);
        if (list != null) {
          _emit(list.group(1)!, SyntaxColors.text);
          _emit(list.group(2)!, SyntaxColors.markdownList);
          _emit(list.group(3)!, SyntaxColors.text);
          _markdownInline(line.substring(list.end));
        } else {
          _markdownInline(line);
        }
      }
      if (li < lines.length - 1) _emit('\n', SyntaxColors.text);
    }
  }

  void _markdownInline(String line) {
    var i = 0;
    final n = line.length;
    while (i < n) {
      if (line.codeUnitAt(i) == 0x60) {
        final end = line.indexOf('`', i + 1);
        if (end > i) {
          _emit(line.substring(i, end + 1), SyntaxColors.string);
          i = end + 1;
          continue;
        }
      }
      if (line.startsWith('**', i)) {
        final end = line.indexOf('**', i + 2);
        if (end > i) {
          _emit(line.substring(i, end + 2), SyntaxColors.text,
              weight: FontWeight.bold);
          i = end + 2;
          continue;
        }
      }
      if (line.codeUnitAt(i) == 0x5B) {
        final close = line.indexOf('](', i);
        final paren = close < 0 ? -1 : line.indexOf(')', close);
        if (close > i && paren > close) {
          _emit(line.substring(i, close + 1), SyntaxColors.variable);
          _emit(line.substring(close + 1, paren + 1), SyntaxColors.string);
          i = paren + 1;
          continue;
        }
      }
      _emit(line[i], SyntaxColors.text);
      i++;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  static int _skipString(String s, int i) {
    final quote = s.codeUnitAt(i);
    i++;
    while (i < s.length) {
      final ch = s.codeUnitAt(i);
      if (ch == 0x5C && i + 1 < s.length) {
        i += 2;
        continue;
      }
      i++;
      if (ch == quote || ch == 0x0A) break;
    }
    return i;
  }

  static int _nextNonSpace(String s, int i) {
    while (i < s.length) {
      final ch = s.codeUnitAt(i);
      if (ch != 0x20 && ch != 0x09) return ch;
      i++;
    }
    return -1;
  }

  static bool _isTripleQuoteAt(String s, int i) {
    if (i + 2 >= s.length) return false;
    final a = s.codeUnitAt(i);
    return (a == 0x27 || a == 0x22) &&
        s.codeUnitAt(i + 1) == a &&
        s.codeUnitAt(i + 2) == a;
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
  static bool _isUpper(int c) => c >= 0x41 && c <= 0x5A;
  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
  static bool _isIdentStart(int c) =>
      (c >= 0x61 && c <= 0x7A) || _isUpper(c) || c == 0x5F;
  static bool _isIdentChar(int c) =>
      _isIdentStart(c) || _isDigit(c) || c == 0x24;
}
