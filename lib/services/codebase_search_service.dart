import 'dart:io';

/// Motor de búsqueda tipo Cursor: grep sobre el codebase y listado de estructura.
///
/// Independiente del chat / OpenAI. Usa solo Dart puro (`Directory.list`).
class CodebaseSearchService {
  CodebaseSearchService._();

  /// Carpetas a omitir por nombre (coincidencia de segmento de ruta).
  static const Set<String> _ignoredDirNames = {
    '.git',
    '.dart_tool',
    'build',
    'node_modules',
    'Pods',
    '.idea',
    '.vscode',
    '.symlinks',
    'DerivedData',
    '.gradle',
    'coverage',
    'dist',
    '.next',
    '__pycache__',
    '.pub-cache',
    '.lopez_code',
    '.lopez_code_backups',
    'ephemeral',
  };

  /// Rutas relativas (normalizadas) a omitir por completo.
  static const Set<String> _ignoredRelativePrefixes = {
    'ios/Pods',
    'macos/Pods',
    'android/.gradle',
    'android/build',
    'android/app/build',
  };

  /// Extensiones de texto/código que se indexan en grep.
  static const Set<String> _textExtensions = {
    '.dart',
    '.yaml',
    '.yml',
    '.json',
    '.md',
    '.txt',
    '.xml',
    '.html',
    '.css',
    '.scss',
    '.js',
    '.ts',
    '.tsx',
    '.jsx',
    '.kt',
    '.java',
    '.swift',
    '.gradle',
    '.properties',
    '.plist',
    '.sh',
    '.bash',
    '.zsh',
    '.py',
    '.rb',
    '.go',
    '.rs',
    '.c',
    '.h',
    '.cpp',
    '.hpp',
    '.m',
    '.mm',
    '.sql',
    '.toml',
    '.ini',
    '.cfg',
    '.env',
    '.gitignore',
    '.gitattributes',
    '.cursorrules',
  };

  /// Archivos sin extensión (o nombre exacto) que sí se tratan como texto.
  static const Set<String> _textBasenames = {
    'Dockerfile',
    'Makefile',
    'Gemfile',
    'Rakefile',
    'Podfile',
    'AGENTS.md',
    '.cursorrules',
    '.gitignore',
    '.env',
    '.env.example',
  };

  static const int _maxFileBytes = 2 * 1024 * 1024; // 2 MB

  /// Busca [query] (literal o RegExp) en archivos de texto del proyecto.
  ///
  /// Cada resultado incluye:
  /// - `filePath`: ruta relativa al proyecto
  /// - `lineNumber`: 1-indexed
  /// - `lineContent`: línea recortada
  /// - `context`: `{ before, after }` (1 línea antes / 1 después)
  static Future<List<Map<String, dynamic>>> grepSearch({
    required String projectPath,
    required String query,
    bool caseSensitive = false,
    String? fileExtension,
    int maxResults = 50,
  }) async {
    final results = <Map<String, dynamic>>[];
    if (query.isEmpty || maxResults <= 0) return results;

    final root = Directory(projectPath);
    if (!await root.exists()) return results;

    final pattern = _buildPattern(query, caseSensitive: caseSensitive);
    final normalizedExt = _normalizeExtension(fileExtension);
    final rootPath = _normalizePath(projectPath);

    Future<void> visitDir(Directory dir) async {
      if (results.length >= maxResults) return;
      List<FileSystemEntity> children;
      try {
        children = await dir.list(followLinks: false).toList();
      } on FileSystemException {
        return;
      }
      for (final entity in children) {
        if (results.length >= maxResults) return;
        final absolute = _normalizePath(entity.path);
        final relative = _toRelative(absolute, rootPath);
        if (_shouldIgnoreRelative(relative)) continue;

        if (entity is Directory) {
          await visitDir(entity);
          continue;
        }
        if (entity is! File) continue;
        if (!_isSearchableTextFile(relative)) continue;
        if (normalizedExt != null &&
            !relative.toLowerCase().endsWith(normalizedExt)) {
          continue;
        }

        try {
          final length = await entity.length();
          if (length == 0 || length > _maxFileBytes) continue;

          final content = await entity.readAsString();
          final lines = content.split('\n');

          for (var i = 0; i < lines.length; i++) {
            if (results.length >= maxResults) break;
            final line = lines[i];
            if (!pattern.hasMatch(line)) continue;

            results.add({
              'filePath': relative,
              'lineNumber': i + 1,
              'lineContent': _trimLine(line),
              'context': {
                'before2': i > 1 ? _trimLine(lines[i - 2]) : '',
                'before': i > 0 ? _trimLine(lines[i - 1]) : '',
                'after': i + 1 < lines.length ? _trimLine(lines[i + 1]) : '',
              },
            });
          }
        } on FileSystemException {
          // Permisos / archivo desaparecido: omitir.
        } on FormatException {
          // No UTF-8 / binario: omitir.
        }
      }
    }

    await visitDir(root);
    return results;
  }

  /// Busca archivos y carpetas cuyo **nombre** (o ruta relativa) coincida
  /// con [query]. Ideal para "go to file" / filtrar el árbol.
  ///
  /// Cada resultado:
  /// - `filePath`: ruta relativa
  /// - `name`: basename
  /// - `type`: `file` | `directory`
  static Future<List<Map<String, dynamic>>> findByName({
    required String projectPath,
    required String query,
    bool caseSensitive = false,
    int maxResults = 80,
  }) async {
    final results = <Map<String, dynamic>>[];
    final q = query.trim();
    if (q.isEmpty || maxResults <= 0) return results;

    final root = Directory(projectPath);
    if (!await root.exists()) return results;

    final rootPath = _normalizePath(projectPath);
    final needle = caseSensitive ? q : q.toLowerCase();

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (results.length >= maxResults) break;

      final absolute = _normalizePath(entity.path);
      final relative = _toRelative(absolute, rootPath);
      if (relative.isEmpty || _shouldIgnoreRelative(relative)) continue;

      final isDir = entity is Directory;
      if (!isDir && entity is! File) continue;

      final name = _basename(relative);
      final hayName = caseSensitive ? name : name.toLowerCase();
      final hayPath = caseSensitive ? relative : relative.toLowerCase();
      if (!hayName.contains(needle) && !hayPath.contains(needle)) continue;

      results.add({
        'filePath': isDir ? '$relative/' : relative,
        'name': name,
        'type': isDir ? 'directory' : 'file',
      });
    }

    // Preferir coincidencias que empiezan por la query, luego por basename.
    results.sort((a, b) {
      final aName = (a['name'] as String);
      final bName = (b['name'] as String);
      final aCmp = caseSensitive ? aName : aName.toLowerCase();
      final bCmp = caseSensitive ? bName : bName.toLowerCase();
      final aStarts = aCmp.startsWith(needle);
      final bStarts = bCmp.startsWith(needle);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      final aDir = a['type'] == 'directory';
      final bDir = b['type'] == 'directory';
      if (aDir != bDir) return aDir ? -1 : 1;
      return aCmp.compareTo(bCmp);
    });

    return results;
  }

  /// Devuelve un árbol limpio (rutas relativas) de archivos relevantes.
  ///
  /// Ideal para inyectar estructura en el system prompt sin leer a ciegas.
  /// Respeta [maxDepth] desde la raíz del proyecto (profundidad 0 = raíz).
  static Future<List<String>> listProjectFiles(
    String projectPath, {
    int maxDepth = 4,
  }) async {
    final entries = <String>[];
    final root = Directory(projectPath);
    if (!await root.exists() || maxDepth < 0) return entries;

    final rootPath = _normalizePath(projectPath);
    await _walkTree(
      directory: root,
      rootPath: rootPath,
      depth: 0,
      maxDepth: maxDepth,
      out: entries,
    );

    entries.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return entries;
  }

  /// Variante formateada del árbol, lista para pegar en un prompt.
  static Future<String> listProjectFilesAsTree(
    String projectPath, {
    int maxDepth = 4,
  }) async {
    final files = await listProjectFiles(projectPath, maxDepth: maxDepth);
    if (files.isEmpty) return '(proyecto vacío o inaccesible)';

    final buffer = StringBuffer();
    buffer.writeln('${_basename(_normalizePath(projectPath))}/');
    for (final relative in files) {
      final isDir = relative.endsWith('/');
      final clean = isDir ? relative.substring(0, relative.length - 1) : relative;
      final parts = clean.split('/');
      final indent = '  ' * parts.length;
      final name = parts.isEmpty ? clean : parts.last;
      buffer.writeln('$indent$name${isDir ? '/' : ''}');
    }
    return buffer.toString().trimRight();
  }

  // ---------------------------------------------------------------------------
  // Internos
  // ---------------------------------------------------------------------------

  static Future<void> _walkTree({
    required Directory directory,
    required String rootPath,
    required int depth,
    required int maxDepth,
    required List<String> out,
  }) async {
    if (depth > maxDepth) return;

    List<FileSystemEntity> children;
    try {
      children = await directory.list(followLinks: false).toList();
    } on FileSystemException {
      return;
    }

    children.sort(
      (a, b) => _basename(a.path)
          .toLowerCase()
          .compareTo(_basename(b.path).toLowerCase()),
    );

    for (final entity in children) {
      final absolute = _normalizePath(entity.path);
      final relative = _toRelative(absolute, rootPath);

      if (entity is Directory) {
        if (_shouldIgnoreRelative(relative)) continue;
        if (depth + 1 > maxDepth) continue;

        out.add('$relative/');
        await _walkTree(
          directory: entity,
          rootPath: rootPath,
          depth: depth + 1,
          maxDepth: maxDepth,
          out: out,
        );
      } else if (entity is File) {
        if (_shouldIgnoreRelative(relative)) continue;
        if (!_isRelevantListingFile(relative)) continue;
        out.add(relative);
      }
    }
  }

  static RegExp _buildPattern(String query, {required bool caseSensitive}) {
    try {
      return RegExp(query, caseSensitive: caseSensitive);
    } on FormatException {
      return RegExp(RegExp.escape(query), caseSensitive: caseSensitive);
    }
  }

  static String? _normalizeExtension(String? fileExtension) {
    if (fileExtension == null || fileExtension.isEmpty) return null;
    final trimmed = fileExtension.trim().toLowerCase();
    if (trimmed.startsWith('.')) return trimmed;
    return '.$trimmed';
  }

  static bool _shouldIgnoreRelative(String relative) {
    final normalized = relative.replaceAll('\\', '/');
    if (normalized.isEmpty || normalized == '.') return false;

    for (final prefix in _ignoredRelativePrefixes) {
      if (normalized == prefix || normalized.startsWith('$prefix/')) {
        return true;
      }
    }

    for (final segment in normalized.split('/')) {
      if (_ignoredDirNames.contains(segment)) return true;
    }
    return false;
  }

  static bool _isSearchableTextFile(String relative) {
    final basename = _basename(relative);
    if (_textBasenames.contains(basename)) return true;

    final ext = _extension(basename);
    if (ext.isEmpty) return false;
    return _textExtensions.contains(ext);
  }

  static bool _isRelevantListingFile(String relative) {
    final basename = _basename(relative);
    if (basename == '.DS_Store') return false;
    if (_textBasenames.contains(basename)) return true;

    final ext = _extension(basename);
    if (ext.isEmpty) {
      return basename == 'Dockerfile' ||
          basename == 'Makefile' ||
          basename == 'Podfile';
    }

    // Imágenes visibles para el agente (read_image / list_files).
    const listableImages = {
      '.png',
      '.jpg',
      '.jpeg',
      '.webp',
      '.gif',
    };
    if (listableImages.contains(ext)) return true;

    const binary = {
      '.ico',
      '.pdf',
      '.zip',
      '.jar',
      '.aar',
      '.so',
      '.dylib',
      '.dll',
      '.exe',
      '.ttf',
      '.otf',
      '.woff',
      '.woff2',
      '.mp3',
      '.mp4',
      '.mov',
    };
    return !binary.contains(ext);
  }

  static String _trimLine(String line, {int maxLen = 240}) {
    final trimmed = line.trimRight();
    if (trimmed.length <= maxLen) return trimmed;
    return '${trimmed.substring(0, maxLen)}…';
  }

  static String _normalizePath(String p) {
    var result = p.replaceAll('\\', '/');
    while (result.endsWith('/') && result.length > 1) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static String _toRelative(String absolute, String root) {
    final abs = _normalizePath(absolute);
    final base = _normalizePath(root);
    if (abs == base) return '';
    if (abs.startsWith('$base/')) {
      return abs.substring(base.length + 1);
    }
    return abs;
  }

  static String _basename(String p) {
    final normalized = p.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? normalized : parts.last;
  }

  static String _extension(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot <= 0) return '';
    return filename.substring(dot).toLowerCase();
  }
}
