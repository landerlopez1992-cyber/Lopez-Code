import 'dart:io';

/// Soporte nativo de reglas de proyecto (.cursorrules, AGENTS.md, Copilot).
///
/// Independiente del chat / OpenAI. Lee y combina instrucciones listas para
/// inyectarse en el system prompt del agente.
class ProjectRulesService {
  ProjectRulesService._();

  /// Fuentes conocidas, en orden de prioridad / combinación.
  static const List<String> _instructionRelativePaths = [
    '.cursorrules',
    'AGENTS.md',
    '.github/copilot-instructions.md',
  ];

  /// Plantilla por defecto para [createDefaultRulesFile].
  static const String defaultRulesTemplate = '''
# Project Rules

## Project overview
Describe the product, stack, and main goals of this repository.

## Coding standards
- Prefer clear, focused changes over large refactors.
- Match existing naming, formatting, and architecture.
- Keep comments sparse and only where intent is non-obvious.

## Architecture
- Document key folders and entry points.
- Note patterns the agent must follow (e.g. services vs widgets).

## Do / Don't
- Do: …
- Don't: …

## Agent behavior
- Ask before destructive operations.
- Prefer reading existing code before inventing new APIs.
''';

  /// Busca en la raíz (y `.github/`) los archivos de instrucciones del proyecto.
  ///
  /// Devuelve mapas con:
  /// - `relativePath`
  /// - `absolutePath`
  /// - `exists` (bool)
  static Future<List<Map<String, dynamic>>> findInstructionFiles(
    String projectPath,
  ) async {
    final found = <Map<String, dynamic>>[];
    final root = _normalizePath(projectPath);

    for (final relative in _instructionRelativePaths) {
      final absolute = _join(root, relative);
      final exists = await File(absolute).exists();
      found.add({
        'relativePath': relative,
        'absolutePath': absolute,
        'exists': exists,
      });
    }
    return found;
  }

  /// Indica si el proyecto tiene al menos un archivo de reglas.
  static Future<bool> hasProjectInstructions(String projectPath) async {
    final files = await findInstructionFiles(projectPath);
    return files.any((f) => f['exists'] == true);
  }

  /// Lee y combina las reglas del proyecto en un bloque listo para systemPrompt.
  ///
  /// Si no hay archivos, devuelve cadena vacía.
  static Future<String> loadProjectInstructions(String projectPath) async {
    final root = Directory(projectPath);
    if (!await root.exists()) return '';

    final sections = <String>[];

    for (final relative in _instructionRelativePaths) {
      final file = File(_join(projectPath, relative));
      if (!await file.exists()) continue;

      try {
        final raw = await file.readAsString();
        final content = raw.trim();
        if (content.isEmpty) continue;

        sections.add(_formatSection(source: relative, content: content));
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }

    if (sections.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('=== PROJECT INSTRUCTIONS ===');
    buffer.writeln(
      'The following rules were loaded from the project and MUST be followed '
      'when working in this codebase.',
    );
    buffer.writeln();
    buffer.write(sections.join('\n\n'));
    buffer.writeln();
    buffer.writeln('=== END PROJECT INSTRUCTIONS ===');
    return buffer.toString().trimRight();
  }

  /// Crea `.cursorrules` con una plantilla si aún no existe.
  ///
  /// No sobrescribe un archivo existente.
  static Future<void> createDefaultRulesFile(String projectPath) async {
    final root = Directory(projectPath);
    if (!await root.exists()) {
      throw FileSystemException(
        'El directorio del proyecto no existe',
        projectPath,
      );
    }

    final file = File(_join(projectPath, '.cursorrules'));
    if (await file.exists()) {
      return;
    }

    await file.writeAsString(defaultRulesTemplate.trimLeft());
  }

  /// Lista de rutas relativas de instrucciones soportadas (solo lectura).
  static List<String> get supportedInstructionPaths =>
      List<String>.unmodifiable(_instructionRelativePaths);

  static String _formatSection({
    required String source,
    required String content,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('--- Source: $source ---');
    buffer.write(content);
    return buffer.toString().trimRight();
  }

  static String _normalizePath(String p) {
    var result = p.replaceAll('\\', '/');
    while (result.endsWith('/') && result.length > 1) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static String _join(String base, String relative) {
    final root = _normalizePath(base);
    final rel = relative.replaceAll('\\', '/');
    if (rel.isEmpty) return root;
    return '$root/$rel';
  }
}
