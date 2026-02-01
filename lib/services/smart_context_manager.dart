import 'dart:io';
import 'conversation_memory_service.dart';
import 'documentation_service.dart';
import 'semantic_search_service.dart';

/// Context Manager profesional para optimizar uso de tokens
/// ✨ AHORA CON BÚSQUEDA SEMÁNTICA (RAG) ✨
/// Solo envía información relevante a la IA
class SmartContextManager {
  static const int _avgCharsPerToken = 4; // Aproximación
  
  /// Construye el contexto optimizado para enviar a la IA
  /// 🧠 CON BÚSQUEDA SEMÁNTICA AUTOMÁTICA 🧠
  static Future<ContextBundle> buildOptimizedContext({
    required String userMessage,
    required String projectPath,
    String? sessionId,
    List<String>? selectedFiles,
    bool includeDocumentation = true,
    bool includeHistory = true,
    bool includeProjectStructure = false,
    bool useSemanticSearch = true, // ✨ NUEVO: búsqueda semántica
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
    
    // 🧠 3. BÚSQUEDA SEMÁNTICA (RAG) - NUEVO
    if (useSemanticSearch && !_isSimpleQuery(userMessage)) {
      final semanticContext = await SemanticSearchService.buildContextForQuery(
        query: userMessage,
        maxFiles: 3,
        includeRelated: true,
      );
      
      if (semanticContext.hasResults) {
        final formattedContext = SemanticSearchService.formatContextForAI(semanticContext);
        buffer.writeln(formattedContext);
        estimatedTokens += _estimateTokens(formattedContext);
        metadata['semanticSearchUsed'] = true;
        metadata['semanticFilesFound'] = semanticContext.totalFiles;
        
        print('🧠 Búsqueda semántica: ${semanticContext.totalFiles} archivos relevantes');
      }
    }
    
    // 4. Archivos seleccionados manualmente (contenido real, no solo nombres)
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
    
    // 5. Documentación relevante (si está activa)
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
    
    // 6. Estructura del proyecto (solo si se solicita explícitamente)
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
    
    // 7. Mensaje del usuario (siempre al final)
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
  
  /// Verifica si es una consulta simple (no requiere búsqueda semántica)
  static bool _isSimpleQuery(String message) {
    final lowerMsg = message.toLowerCase().trim();
    
    // Saludos comunes
    final greetings = [
      'hola',
      'hi',
      'hello',
      'hey',
      'buenos días',
      'buenas tardes',
      'buenas noches',
      'saludos',
    ];
    
    // Respuestas simples
    final simpleResponses = [
      'gracias',
      'thanks',
      'ok',
      'okay',
      'entendido',
      'perfecto',
      'sí',
      'si',
      'yes',
      'no',
      'vale',
    ];
    
    // Verificar si es solo un saludo o respuesta simple
    if (greetings.any((g) => lowerMsg == g || lowerMsg.startsWith('$g '))) {
      return true;
    }
    
    if (simpleResponses.contains(lowerMsg)) {
      return true;
    }
    
    // Mensajes muy cortos (probablemente no son preguntas técnicas)
    if (lowerMsg.length < 10 && !lowerMsg.contains('?')) {
      return true;
    }
    
    return false;
  }
  
  /// System prompt profesional y conversacional
  static String _getSystemPrompt() {
    return '''Eres un asistente de programación Flutter/Dart experto y amigable.

PERSONALIDAD:
- Sé conversacional y natural en saludos y conversaciones casuales
- Para "hola", "buenos días", etc: saluda de vuelta y pregunta en qué puedes ayudar
- Sé técnico y preciso cuando se trata de código
- Mantén un tono profesional pero amigable

REGLAS DE RESPUESTA:
1. SALUDOS: Responde naturalmente ("¡Hola! ¿En qué puedo ayudarte hoy?")
2. CÓDIGO: Si piden código, da código completo y funcional
3. PRECISIÓN: Sé conciso pero preciso en explicaciones técnicas
4. CONTEXTO: Solo pide más contexto si realmente no entiendes la pregunta técnica
5. NO REPITAS: No repitas información que ya está en el historial

✨ IMPORTANTE - CREACIÓN DE PROYECTOS:
Cuando te pidan crear un proyecto (calculadora, app, etc):
- SIEMPRE crea TODOS los archivos necesarios para que funcione
- Para Flutter: crea pubspec.yaml + main.dart + archivos necesarios
- Para Python: crea main.py/app.py + requirements.txt si es web
- Para Node.js: crea package.json + index.js/app.js + archivos necesarios
- NO asumas que archivos ya existen - créalos TODOS
- Usa create_file para cada archivo necesario

FORMATO:
- Código: usa bloques ```dart, ```python, etc
- Explicaciones técnicas: máximo 2-3 líneas por concepto
- Pasos: lista numerada simple
- Conversación casual: sé natural y amigable

Tu objetivo: ayudar al usuario de manera eficiente y amigable.''';
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
  
  /// Estima tokens de un texto (método público)
  static int estimateTokens(String text) {
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
    if (metadata['semanticSearchUsed'] == true) {
      parts.add('${metadata['semanticFilesFound']} archivos relevantes (RAG)');
    }
    if (metadata['filesIncluded'] != null) {
      parts.add('${metadata['filesIncluded']} archivos seleccionados');
    }
    if (metadata['documentationIncluded'] == true) parts.add('documentación');
    if (metadata['structureIncluded'] == true) parts.add('estructura');
    
    return parts.isEmpty ? 'contexto básico' : parts.join(', ');
  }
}
