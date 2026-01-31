import 'dart:io';
import 'conversation_memory_service.dart';
import 'documentation_service.dart';

/// Context Manager profesional para optimizar uso de tokens
/// Solo envía información relevante a la IA
class SmartContextManager {
  static const int _avgCharsPerToken = 4; // Aproximación
  
  /// Construye el contexto optimizado para enviar a la IA
  static Future<ContextBundle> buildOptimizedContext({
    required String userMessage,
    required String projectPath,
    String? sessionId,
    List<String>? selectedFiles,
    bool includeDocumentation = true,
    bool includeHistory = true,
    bool includeProjectStructure = false,
  }) async {
    final buffer = StringBuffer();
    int estimatedTokens = 0;
    final metadata = <String, dynamic>{};
    
    // 1. Sistema: Prompt profesional conciso
    final systemPrompt = _getSystemPrompt();
    buffer.writeln(systemPrompt);
    buffer.writeln();
    estimatedTokens += _estimateTokens(systemPrompt);
    
    // 2. Historial de conversación (solo últimos mensajes relevantes)
    if (includeHistory) {
      final history = await ConversationMemoryService.getOptimizedContext(
        sessionId: sessionId,
        maxMessages: 6, // Solo últimos 3 intercambios
        includeSystemInfo: false,
      );
      
      if (history.isNotEmpty) {
        buffer.writeln('=== CONVERSACIÓN RECIENTE ===');
        buffer.writeln(history);
        buffer.writeln();
        estimatedTokens += _estimateTokens(history);
        metadata['historyIncluded'] = true;
      }
    }
    
    // 3. Archivos seleccionados (contenido real, no solo nombres)
    if (selectedFiles != null && selectedFiles.isNotEmpty) {
      final filesContent = await _getSelectedFilesContent(
        selectedFiles,
        maxTokensPerFile: 1000,
      );
      
      if (filesContent.isNotEmpty) {
        buffer.writeln('=== ARCHIVOS SELECCIONADOS ===');
        buffer.writeln(filesContent);
        buffer.writeln();
        estimatedTokens += _estimateTokens(filesContent);
        metadata['filesIncluded'] = selectedFiles.length;
      }
    }
    
    // 4. Documentación relevante (si está activa)
    if (includeDocumentation) {
      final docContent = await DocumentationService.getActiveDocumentationContent();
      
      // Limitar documentación si es muy larga
      final trimmedDoc = _trimToTokenLimit(
        docContent,
        maxTokens: 3000,
      );
      
      if (trimmedDoc.isNotEmpty) {
        buffer.writeln(trimmedDoc);
        buffer.writeln();
        estimatedTokens += _estimateTokens(trimmedDoc);
        metadata['documentationIncluded'] = true;
      }
    }
    
    // 5. Estructura del proyecto (solo si se solicita explícitamente)
    if (includeProjectStructure) {
      final structure = await _getProjectStructure(projectPath);
      
      if (structure.isNotEmpty) {
        buffer.writeln('=== ESTRUCTURA DEL PROYECTO ===');
        buffer.writeln(structure);
        buffer.writeln();
        estimatedTokens += _estimateTokens(structure);
        metadata['structureIncluded'] = true;
      }
    }
    
    // 6. Mensaje del usuario (siempre al final)
    buffer.writeln('=== SOLICITUD DEL USUARIO ===');
    buffer.writeln(userMessage);
    estimatedTokens += _estimateTokens(userMessage);
    
    print('📊 Contexto construido: ~$estimatedTokens tokens estimados');
    
    return ContextBundle(
      content: buffer.toString(),
      estimatedTokens: estimatedTokens,
      metadata: metadata,
    );
  }
  
  /// System prompt profesional y conciso
  static String _getSystemPrompt() {
    return '''Eres un asistente de programación Flutter/Dart experto.

REGLAS IMPORTANTES:
1. Responde SOLO lo que se pregunta, sin información extra
2. Si piden código, da código completo y funcional
3. Sé conciso pero preciso
4. No repitas información que ya está en el historial
5. Si no estás seguro, di "necesito más contexto sobre..."

FORMATO DE RESPUESTA:
- Código: usa bloques ```dart
- Explicaciones: máximo 2-3 líneas por concepto
- Pasos: lista numerada simple

Tu objetivo: resolver el problema del usuario eficientemente.''';
  }
  
  /// Obtiene contenido de archivos seleccionados
  static Future<String> _getSelectedFilesContent(
    List<String> filePaths,
    {int maxTokensPerFile = 1000}
  ) async {
    final buffer = StringBuffer();
    
    for (final path in filePaths.take(5)) { // Máximo 5 archivos
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        
        final content = await file.readAsString();
        final fileName = path.split('/').last;
        
        // Truncar si es muy largo
        final truncated = _trimToTokenLimit(content, maxTokens: maxTokensPerFile);
        
        buffer.writeln('📄 $fileName:');
        buffer.writeln('```dart');
        buffer.writeln(truncated);
        buffer.writeln('```');
        buffer.writeln();
      } catch (e) {
        print('⚠️ Error leyendo archivo $path: $e');
      }
    }
    
    return buffer.toString();
  }
  
  /// Obtiene estructura del proyecto (solo directorios principales)
  static Future<String> _getProjectStructure(String projectPath) async {
    try {
      final dir = Directory(projectPath);
      if (!await dir.exists()) return '';
      
      final buffer = StringBuffer();
      buffer.writeln('Estructura principal:');
      
      final entities = await dir.list(recursive: false).toList();
      final directories = entities.whereType<Directory>()
          .where((d) => !d.path.contains('.') && !d.path.contains('build'))
          .take(10);
      
      for (final directory in directories) {
        final name = directory.path.split('/').last;
        buffer.writeln('📁 $name/');
      }
      
      return buffer.toString();
    } catch (e) {
      print('⚠️ Error obteniendo estructura: $e');
      return '';
    }
  }
  
  /// Estima tokens de un texto
  static int _estimateTokens(String text) {
    return (text.length / _avgCharsPerToken).ceil();
  }
  
  /// Recorta texto para que no exceda un límite de tokens
  static String _trimToTokenLimit(String text, {required int maxTokens}) {
    final maxChars = maxTokens * _avgCharsPerToken;
    
    if (text.length <= maxChars) {
      return text;
    }
    
    // Truncar en el último punto o párrafo completo
    final truncated = text.substring(0, maxChars);
    final lastPeriod = truncated.lastIndexOf('.');
    final lastNewline = truncated.lastIndexOf('\n');
    
    final cutPoint = lastPeriod > lastNewline ? lastPeriod : lastNewline;
    
    if (cutPoint > maxChars - 500) {
      return '${truncated.substring(0, cutPoint + 1)}\n\n[...contenido truncado para optimizar tokens]';
    }
    
    return '$truncated\n\n[...contenido truncado para optimizar tokens]';
  }
  
  /// Analiza si una solicitud necesita contexto completo
  static bool needsFullContext(String userMessage) {
    final lowercaseMsg = userMessage.toLowerCase();
    
    // Palabras que indican necesidad de contexto completo
    final fullContextKeywords = [
      'todo el proyecto',
      'toda la app',
      'estructura completa',
      'análisis completo',
      'revisar todo',
    ];
    
    return fullContextKeywords.any((keyword) => lowercaseMsg.contains(keyword));
  }
  
  /// Analiza si una solicitud necesita documentación
  static bool needsDocumentation(String userMessage) {
    final lowercaseMsg = userMessage.toLowerCase();
    
    // Indicadores de que se necesita documentación
    final docKeywords = [
      '@',
      'según',
      'documentación',
      'api',
      'cómo',
      'implementar',
      'integrar',
    ];
    
    return docKeywords.any((keyword) => lowercaseMsg.contains(keyword));
  }
}

/// Bundle de contexto optimizado
class ContextBundle {
  final String content;
  final int estimatedTokens;
  final Map<String, dynamic> metadata;
  
  ContextBundle({
    required this.content,
    required this.estimatedTokens,
    required this.metadata,
  });
  
  bool get isWithinLimit => estimatedTokens <= 8000;
  
  String get summary {
    final parts = <String>[];
    if (metadata['historyIncluded'] == true) parts.add('historial');
    if (metadata['filesIncluded'] != null) {
      parts.add('${metadata['filesIncluded']} archivos');
    }
    if (metadata['documentationIncluded'] == true) parts.add('documentación');
    if (metadata['structureIncluded'] == true) parts.add('estructura');
    
    return parts.isEmpty ? 'contexto básico' : parts.join(', ');
  }
}
