import 'dart:io';

import '../services/debug_console_service.dart';

/// Tipos de mención de contexto estilo Cursor (`@file`, `@folder`, `@problems`, …).
enum ContextMentionType {
  file,
  folder,
  problems,
  codebase,
}

/// Representa una mención `@…` seleccionada en el input del chat.
class ContextMention {
  final String id;
  final String label;
  final ContextMentionType type;

  /// Ruta relativa al proyecto (file/folder). Null para problems/codebase.
  final String? path;

  const ContextMention({
    required this.id,
    required this.label,
    required this.type,
    this.path,
  });

  factory ContextMention.file({
    required String relativePath,
  }) {
    final name = relativePath.split('/').last;
    return ContextMention(
      id: 'file:$relativePath',
      label: '@$name',
      type: ContextMentionType.file,
      path: relativePath,
    );
  }

  factory ContextMention.folder({
    required String relativePath,
  }) {
    final name = relativePath.isEmpty
        ? 'project'
        : relativePath.split('/').where((s) => s.isNotEmpty).last;
    return ContextMention(
      id: 'folder:$relativePath',
      label: '@$name/',
      type: ContextMentionType.folder,
      path: relativePath,
    );
  }

  factory ContextMention.problems() {
    return const ContextMention(
      id: 'special:problems',
      label: '@problems',
      type: ContextMentionType.problems,
    );
  }

  factory ContextMention.codebase({String label = '@structure'}) {
    return ContextMention(
      id: 'special:codebase',
      label: label.startsWith('@') ? label : '@$label',
      type: ContextMentionType.codebase,
    );
  }

  /// Extrae el contenido real asociado a la mención.
  Future<String> resolveContent(String projectPath) async {
    switch (type) {
      case ContextMentionType.file:
        return _resolveFile(projectPath);
      case ContextMentionType.folder:
        return _resolveFolder(projectPath);
      case ContextMentionType.problems:
        return _resolveProblems();
      case ContextMentionType.codebase:
        return _resolveCodebase(projectPath);
    }
  }

  Future<String> _resolveFile(String projectPath) async {
    final relative = path;
    if (relative == null || relative.isEmpty) {
      return '(archivo sin ruta)';
    }
    final absolute = relative.startsWith('/')
        ? relative
        : '$projectPath/$relative';
    final file = File(absolute);
    if (!await file.exists()) {
      return '(archivo no encontrado: $relative)';
    }
    try {
      final content = await file.readAsString();
      const maxChars = 40000;
      if (content.length > maxChars) {
        return '${content.substring(0, maxChars)}\n\n… [truncado, ${content.length} chars totales]';
      }
      return content;
    } catch (e) {
      return '(no se pudo leer $relative: $e)';
    }
  }

  Future<String> _resolveFolder(String projectPath) async {
    final relative = path ?? '';
    final absolute = relative.isEmpty
        ? projectPath
        : (relative.startsWith('/') ? relative : '$projectPath/$relative');
    final dir = Directory(absolute);
    if (!await dir.exists()) {
      return '(carpeta no encontrada: $relative)';
    }

    final entries = <String>[];
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        final rel = _toRelative(entity.path, projectPath);
        if (_shouldIgnore(rel)) continue;
        final suffix = entity is Directory ? '/' : '';
        entries.add('$rel$suffix');
        if (entries.length >= 400) {
          entries.add('… [listado truncado]');
          break;
        }
      }
    } catch (e) {
      return '(error al listar carpeta: $e)';
    }

    entries.sort();
    final header = relative.isEmpty ? 'project/' : '$relative/';
    return 'Folder listing for $header (${entries.length} entries):\n${entries.join('\n')}';
  }

  String _resolveProblems() {
    final items = DebugConsoleService().problemItems;
    if (items.isEmpty) {
      return 'No current problems in DebugConsoleService.problemItems.\n'
          'Tip: run flutter analyze (or /analyze) to refresh.';
    }
    final buffer = StringBuffer();
    buffer.writeln('Current Problems (${items.length}):');
    for (final item in items) {
      buffer.writeln('- $item');
    }
    return buffer.toString().trimRight();
  }

  Future<String> _resolveCodebase(String projectPath) async {
    final root = Directory(projectPath);
    if (!await root.exists()) {
      return '(proyecto no encontrado: $projectPath)';
    }

    final lines = <String>[];
    await _walkTree(root, projectPath, '', lines, 0, maxDepth: 4, maxLines: 500);
    return 'Project structure:\n${lines.join('\n')}';
  }

  Future<void> _walkTree(
    Directory dir,
    String projectPath,
    String prefix,
    List<String> lines,
    int depth, {
    required int maxDepth,
    required int maxLines,
  }) async {
    if (lines.length >= maxLines || depth > maxDepth) return;

    final children = <FileSystemEntity>[];
    try {
      children.addAll(await dir.list(followLinks: false).toList());
    } catch (_) {
      return;
    }

    children.sort((a, b) {
      final aDir = a is Directory;
      final bDir = b is Directory;
      if (aDir != bDir) return aDir ? -1 : 1;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });

    for (final child in children) {
      if (lines.length >= maxLines) {
        lines.add('$prefix…');
        return;
      }
      final name = child.path.split('/').last;
      if (_ignoredName(name)) continue;

      if (child is Directory) {
        lines.add('$prefix$name/');
        await _walkTree(
          child,
          projectPath,
          '$prefix  ',
          lines,
          depth + 1,
          maxDepth: maxDepth,
          maxLines: maxLines,
        );
      } else {
        lines.add('$prefix$name');
      }
    }
  }

  static String _toRelative(String absolute, String projectPath) {
    final norm = absolute.replaceAll('\\', '/');
    final root = projectPath.replaceAll('\\', '/');
    if (norm.startsWith('$root/')) {
      return norm.substring(root.length + 1);
    }
    return norm;
  }

  static bool _ignoredName(String name) {
    const ignored = {
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
    };
    return ignored.contains(name);
  }

  static bool _shouldIgnore(String relativePath) {
    final parts = relativePath.replaceAll('\\', '/').split('/');
    return parts.any(_ignoredName);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type.name,
        'path': path,
      };

  factory ContextMention.fromJson(Map<String, dynamic> json) {
    return ContextMention(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      type: ContextMentionType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => ContextMentionType.file,
      ),
      path: json['path'] as String?,
    );
  }

  @override
  String toString() => label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContextMention && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Slash command estilo Cursor (`/fix`, `/explain`, …).
class SlashCommand {
  final String id;
  final String trigger; // e.g. /fix
  final String title;
  final String description;

  /// Plantilla del prompt expandido. Placeholders opcionales:
  /// `{activeFile}`, `{problems}`
  final String promptTemplate;

  const SlashCommand({
    required this.id,
    required this.trigger,
    required this.title,
    required this.description,
    required this.promptTemplate,
  });

  /// Expande la plantilla con archivo activo y problems actuales.
  String expand({
    String? activeFilePath,
    String? activeFileContent,
    List<String>? problemLines,
  }) {
    var result = promptTemplate;
    result = result.replaceAll(
      '{activeFile}',
      activeFilePath?.isNotEmpty == true ? activeFilePath! : '(ninguno)',
    );
    result = result.replaceAll(
      '{activeFileContent}',
      activeFileContent?.isNotEmpty == true
          ? activeFileContent!
          : '(sin contenido)',
    );
    final problems = (problemLines == null || problemLines.isEmpty)
        ? '(sin problemas actuales)'
        : problemLines.join('\n');
    result = result.replaceAll('{problems}', problems);
    return result.trim();
  }

  static const List<SlashCommand> builtins = [
    SlashCommand(
      id: 'fix',
      trigger: '/fix',
      title: 'Fix problems',
      description: 'Corregir errores actuales de Problems',
      promptTemplate:
          'Corrige los errores actuales del proyecto listados abajo. '
          'Aplica cambios mínimos y concretos.\n\n'
          'Problemas:\n{problems}\n\n'
          'Archivo activo: {activeFile}',
    ),
    SlashCommand(
      id: 'explain',
      trigger: '/explain',
      title: 'Explain file',
      description: 'Explicar el archivo abierto',
      promptTemplate:
          'Explica el archivo abierto de forma clara y concisa: qué hace, '
          'estructura principal y puntos delicados.\n\n'
          'Archivo: {activeFile}\n\n'
          '```\n{activeFileContent}\n```',
    ),
    SlashCommand(
      id: 'refactor',
      trigger: '/refactor',
      title: 'Refactor',
      description: 'Mejorar / refactorizar código',
      promptTemplate:
          'Propón un refactor del archivo activo para mejorar claridad, '
          'mantenibilidad y rendimiento sin cambiar el comportamiento.\n\n'
          'Archivo: {activeFile}\n\n'
          '```\n{activeFileContent}\n```',
    ),
    SlashCommand(
      id: 'analyze',
      trigger: '/analyze',
      title: 'Run analyze',
      description: 'Correr flutter analyze y revisar problemas',
      promptTemplate:
          'Ejecuta (o asume el resultado de) flutter analyze en el proyecto, '
          'resume los problemas encontrados y sugiere fixes priorizados.\n\n'
          'Problemas conocidos:\n{problems}\n\n'
          'Archivo activo: {activeFile}',
    ),
  ];
}
