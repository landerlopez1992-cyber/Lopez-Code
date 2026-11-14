import 'package:flutter/material.dart';

/// Cómo se tokeniza el archivo.
enum LexerMode { code, yaml, json, xml, markdown, plain }

/// Paleta de tokens estilo Cursor Dark Modern (VS Code Dark+).
class SyntaxColors {
  static const Color text = Color(0xFFD4D4D4);
  static const Color controlKeyword = Color(0xFFC586C0);
  static const Color declKeyword = Color(0xFF569CD6);
  static const Color type = Color(0xFF4EC9B0);
  static const Color function = Color(0xFFDCDCAA);
  static const Color variable = Color(0xFF9CDCFE);
  static const Color string = Color(0xFFCE9178);
  static const Color number = Color(0xFFB5CEA8);
  static const Color comment = Color(0xFF6A9955);
  static const Color annotation = Color(0xFFDCDCAA);
  static const Color punctuation = Color(0xFFD4D4D4);
  static const Color tagBracket = Color(0xFF808080);
  static const Color markdownList = Color(0xFF6796E6);

  /// Bracket pair colorization (VS Code).
  static const List<Color> brackets = [
    Color(0xFFFFD700),
    Color(0xFFDA70D6),
    Color(0xFF179FFF),
  ];
}

class CodeLanguage {
  final String id;
  final String name;
  final LexerMode mode;
  final Set<String> controlKeywords;
  final Set<String> declKeywords;
  final Set<String> constants;
  final Set<String> builtinTypes;
  final String? lineComment;
  final bool blockComments;
  final bool tripleQuotes;
  final bool annotations;

  /// Identificadores en MayúsculaInicial se pintan como tipos.
  final bool capitalizedTypes;

  /// `$VAR` / `${VAR}` como variable (shell).
  final bool dollarVariables;

  /// Identificadores sueltos en color variable (#9CDCFE) en vez de texto.
  final bool colorPlainIdentifiers;

  const CodeLanguage({
    required this.id,
    required this.name,
    this.mode = LexerMode.code,
    this.controlKeywords = const {},
    this.declKeywords = const {},
    this.constants = const {},
    this.builtinTypes = const {},
    this.lineComment,
    this.blockComments = false,
    this.tripleQuotes = false,
    this.annotations = false,
    this.capitalizedTypes = false,
    this.dollarVariables = false,
    this.colorPlainIdentifiers = true,
  });

  static const dart = CodeLanguage(
    id: 'dart',
    name: 'Dart',
    controlKeywords: {
      'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'default',
      'break', 'continue', 'return', 'try', 'catch', 'finally', 'throw',
      'rethrow', 'assert', 'await', 'yield', 'import', 'export', 'part',
      'library', 'show', 'hide', 'as', 'is', 'in', 'on', 'async', 'sync',
    },
    declKeywords: {
      'abstract', 'base', 'class', 'const', 'covariant', 'deferred', 'enum',
      'extends', 'extension', 'external', 'factory', 'final', 'Function',
      'get', 'implements', 'interface', 'late', 'mixin', 'new', 'operator',
      'required', 'sealed', 'set', 'static', 'super', 'this', 'typedef',
      'var', 'void', 'with', 'dynamic',
    },
    constants: {'true', 'false', 'null'},
    builtinTypes: {'int', 'double', 'num', 'bool'},
    lineComment: '//',
    blockComments: true,
    tripleQuotes: true,
    annotations: true,
    capitalizedTypes: true,
  );

  static const groovy = CodeLanguage(
    id: 'groovy',
    name: 'Groovy',
    controlKeywords: {
      'if', 'else', 'for', 'while', 'switch', 'case', 'default', 'break',
      'continue', 'return', 'try', 'catch', 'finally', 'throw', 'import',
      'in', 'as', 'assert',
    },
    declKeywords: {
      'def', 'class', 'interface', 'enum', 'extends', 'implements', 'new',
      'static', 'final', 'private', 'public', 'protected', 'void', 'this',
      'super', 'apply', 'plugin', 'id', 'version',
    },
    constants: {'true', 'false', 'null'},
    builtinTypes: {'int', 'long', 'boolean', 'double', 'float'},
    lineComment: '//',
    blockComments: true,
    tripleQuotes: true,
    annotations: true,
    capitalizedTypes: true,
  );

  static const kotlin = CodeLanguage(
    id: 'kotlin',
    name: 'Kotlin',
    controlKeywords: {
      'if', 'else', 'when', 'for', 'while', 'do', 'break', 'continue',
      'return', 'try', 'catch', 'finally', 'throw', 'import', 'package',
      'in', 'is', 'as',
    },
    declKeywords: {
      'fun', 'val', 'var', 'class', 'object', 'interface', 'enum', 'data',
      'sealed', 'open', 'override', 'abstract', 'private', 'public',
      'protected', 'internal', 'companion', 'lateinit', 'suspend', 'this',
      'super', 'init', 'constructor', 'typealias', 'inline', 'const',
    },
    constants: {'true', 'false', 'null'},
    lineComment: '//',
    blockComments: true,
    tripleQuotes: true,
    annotations: true,
    capitalizedTypes: true,
  );

  static const swift = CodeLanguage(
    id: 'swift',
    name: 'Swift',
    controlKeywords: {
      'if', 'else', 'guard', 'switch', 'case', 'default', 'for', 'while',
      'repeat', 'break', 'continue', 'return', 'throw', 'try', 'catch', 'do',
      'import', 'in', 'is', 'as', 'await', 'defer', 'where',
    },
    declKeywords: {
      'func', 'let', 'var', 'class', 'struct', 'enum', 'protocol',
      'extension', 'init', 'deinit', 'self', 'Self', 'super', 'static',
      'private', 'public', 'internal', 'fileprivate', 'open', 'override',
      'final', 'mutating', 'async', 'throws', 'some', 'any', 'typealias',
      'weak', 'lazy',
    },
    constants: {'true', 'false', 'nil'},
    lineComment: '//',
    blockComments: true,
    tripleQuotes: true,
    annotations: true,
    capitalizedTypes: true,
  );

  static const shell = CodeLanguage(
    id: 'shell',
    name: 'Shell',
    controlKeywords: {
      'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do',
      'done', 'case', 'esac', 'in', 'function', 'return', 'exit', 'break',
      'continue',
    },
    declKeywords: {'export', 'local', 'readonly', 'declare', 'set', 'unset'},
    constants: {'true', 'false'},
    lineComment: '#',
    dollarVariables: true,
    colorPlainIdentifiers: false,
  );

  static const yaml = CodeLanguage(
    id: 'yaml',
    name: 'YAML',
    mode: LexerMode.yaml,
    constants: {'true', 'false', 'null', 'yes', 'no', '~'},
    lineComment: '#',
  );

  static const json = CodeLanguage(
    id: 'json',
    name: 'JSON',
    mode: LexerMode.json,
    constants: {'true', 'false', 'null'},
    lineComment: '//',
    blockComments: true,
  );

  static const xml = CodeLanguage(id: 'xml', name: 'XML', mode: LexerMode.xml);

  static const markdown = CodeLanguage(
    id: 'markdown',
    name: 'Markdown',
    mode: LexerMode.markdown,
  );

  static const plain = CodeLanguage(
    id: 'plaintext',
    name: 'Plain Text',
    mode: LexerMode.plain,
  );

  /// Detecta el lenguaje por extensión / nombre de archivo.
  static CodeLanguage forPath(String? path) {
    if (path == null || path.isEmpty) return plain;
    final name = path.split('/').last.toLowerCase();
    if (name == 'podfile' || name == 'gemfile' || name == 'fastfile') {
      return shell;
    }
    if (name == 'dockerfile' || name == 'makefile' || name == '.env') {
      return shell;
    }
    final dot = name.lastIndexOf('.');
    if (dot < 0) return plain;
    switch (name.substring(dot + 1)) {
      case 'dart':
        return dart;
      case 'gradle':
      case 'groovy':
        return groovy;
      case 'kt':
      case 'kts':
        return kotlin;
      case 'swift':
        return swift;
      case 'yaml':
      case 'yml':
        return yaml;
      case 'json':
      case 'arb':
        return json;
      case 'xml':
      case 'plist':
      case 'html':
      case 'xib':
      case 'storyboard':
      case 'svg':
        return xml;
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'properties':
        return shell;
      case 'md':
      case 'markdown':
        return markdown;
      default:
        return plain;
    }
  }
}

/// Icono + color de pestaña / breadcrumb por tipo de archivo.
class FileTypeIcon {
  final IconData icon;
  final Color color;

  const FileTypeIcon(this.icon, this.color);

  static const _image = FileTypeIcon(Icons.image_outlined, Color(0xFFA074C4));

  static FileTypeIcon forPath(String? path) {
    final name = (path ?? '').split('/').last.toLowerCase();
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1);
    if (name == 'pubspec.yaml' || name == 'pubspec.lock') {
      return const FileTypeIcon(Icons.flutter_dash, Color(0xFF40C4FF));
    }
    switch (ext) {
      case 'dart':
        return const FileTypeIcon(Icons.flutter_dash, Color(0xFF40C4FF));
      case 'gradle':
      case 'groovy':
        return const FileTypeIcon(Icons.build_outlined, Color(0xFF6DB33F));
      case 'kt':
      case 'kts':
        return const FileTypeIcon(Icons.code, Color(0xFFA97BFF));
      case 'swift':
        return const FileTypeIcon(Icons.code, Color(0xFFF05138));
      case 'yaml':
      case 'yml':
        return const FileTypeIcon(Icons.tune, Color(0xFFCB4B6E));
      case 'json':
      case 'arb':
        return const FileTypeIcon(Icons.data_object, Color(0xFFF1C40F));
      case 'xml':
      case 'plist':
      case 'html':
      case 'xib':
      case 'storyboard':
        return const FileTypeIcon(Icons.code, Color(0xFFE37933));
      case 'sh':
      case 'bash':
      case 'zsh':
        return const FileTypeIcon(Icons.terminal, Color(0xFF89E051));
      case 'md':
      case 'markdown':
        return const FileTypeIcon(Icons.info_outline, Color(0xFF519ABA));
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
      case 'svg':
      case 'ico':
        return _image;
      default:
        return const FileTypeIcon(
          Icons.insert_drive_file_outlined,
          Color(0xFF8E8E93),
        );
    }
  }
}
