import '../models/context_mention.dart';
import 'debug_console_service.dart';

/// Arma bloques de contexto estructurados a partir de menciones `@…`
/// antes de enviar el mensaje a OpenAI.
class ContextBuilderService {
  ContextBuilderService._();

  /// Enriquece [rawMessage] con un bloque `<context>…</context>` limpio.
  ///
  /// - Resuelve cada [ContextMention] vía [ContextMention.resolveContent].
  /// - Incluye opcionalmente el archivo activo.
  /// - Deja el mensaje del usuario al final para que el modelo lo priorice.
  static Future<String> enrichPromptWithMentions({
    required String rawMessage,
    required List<ContextMention> mentions,
    required String projectPath,
    String? activeFilePath,
    String? activeFileContent,
  }) async {
    final buffer = StringBuffer();
    final hasMentions = mentions.isNotEmpty;
    final hasActive = activeFilePath != null &&
        activeFilePath.isNotEmpty &&
        activeFileContent != null;

    if (hasMentions || hasActive) {
      buffer.writeln('<context>');
      buffer.writeln('project_path: $projectPath');

      if (hasActive) {
        buffer.writeln();
        buffer.writeln('<active_file path="$activeFilePath">');
        buffer.writeln(_truncate(activeFileContent, maxChars: 30000));
        buffer.writeln('</active_file>');
      }

      for (final mention in mentions) {
        buffer.writeln();
        final tag = mention.type.name;
        final pathAttr =
            mention.path != null && mention.path!.isNotEmpty
                ? ' path="${mention.path}"'
                : '';
        buffer.writeln('<$tag label="${mention.label}"$pathAttr>');
        try {
          final content = await mention.resolveContent(projectPath);
          buffer.writeln(_truncate(content, maxChars: 40000));
        } catch (e) {
          buffer.writeln('(error resolving ${mention.label}: $e)');
        }
        buffer.writeln('</$tag>');
      }

      buffer.writeln('</context>');
      buffer.writeln();
    }

    buffer.writeln('<user_message>');
    buffer.writeln(rawMessage.trim());
    buffer.writeln('</user_message>');

    return buffer.toString().trimRight();
  }

  /// Expande un [SlashCommand] con archivo activo + problems actuales.
  static String expandSlashCommand({
    required SlashCommand command,
    String? activeFilePath,
    String? activeFileContent,
  }) {
    final problems = DebugConsoleService()
        .problemItems
        .map((p) => p.toString())
        .toList();
    return command.expand(
      activeFilePath: activeFilePath,
      activeFileContent: activeFileContent,
      problemLines: problems,
    );
  }

  /// Extrae labels `@…` ya presentes en el texto (para chips / depuración).
  static List<String> extractMentionLabels(String text) {
    final matches = RegExp(r'@([\w./\-]+)').allMatches(text);
    return matches
        .map((m) => '@${m.group(1)}')
        .toSet()
        .toList(growable: false);
  }

  static String _truncate(String value, {required int maxChars}) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}\n… [truncated]';
  }
}
