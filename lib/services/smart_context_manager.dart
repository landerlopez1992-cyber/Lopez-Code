import 'dart:io';
import 'conversation_memory_service.dart';
import 'documentation_service.dart';
import 'semantic_search_service.dart';
import 'rule_service.dart';
import 'task_orchestrator_service.dart';
import 'project_analyzer_service.dart';

/// Context Manager profesional para optimizar uso de tokens
/// ✨ AHORA CON BÚSQUEDA SEMÁNTICA (RAG) ✨
/// Solo envía información relevante a la IA
class SmartContextManager {
  static const int _avgCharsPerToken = 4; // Aproximación
  
  /// Construye el contexto optimizado para enviar a la IA
  /// 🧠 CON ANÁLISIS PREVIO + BÚSQUEDA SEMÁNTICA 🧠
  static Future<ContextBundle> buildOptimizedContext({
    required String userMessage,
    required String projectPath,
    String? sessionId,
    List<String>? selectedFiles,
    bool includeDocumentation = true,
    bool includeHistory = true,
    bool includeProjectStructure = false,
    bool useSemanticSearch = true, // ✨ NUEVO: búsqueda semántica
    bool analyzeBeforeActing = true, // ✨ NUEVO: analizar antes de actuar
  }) async {
    final buffer = StringBuffer();
    int estimatedTokens = 0;
    final metadata = <String, dynamic>{};
    
    // ✨ PASO 0: ANALIZAR EL PROYECTO ANTES DE ACTUAR
    // ✅ FILTRO: NO analizar para mensajes simples (saludos, etc.)
    if (analyzeBeforeActing && !_isSimpleMessage(userMessage)) {
      print('🔍 === ANALIZANDO PROYECTO ANTES DE ACTUAR ===');
      
      // 1. Detectar tipo de tarea
      final taskType = TaskOrchestratorService.detectTaskType(userMessage);
      print('📋 Tipo de tarea detectado: $taskType');
      
      // 2. Analizar proyecto
      final analysis = await ProjectAnalyzerService.analyzeProject(projectPath);
      final analysisReport = ProjectAnalyzerService.generateReport(analysis);
      
      // 3. Generar plan de ejecución
      final executionPlan = await TaskOrchestratorService.generateExecutionPlan(
        projectPath: projectPath,
        userMessage: userMessage,
        taskType: taskType,
      );
      
      // 4. Construir contexto enriquecido
      final enrichedContext = await TaskOrchestratorService.buildEnrichedContext(
        projectPath: projectPath,
        contextFiles: executionPlan.contextFiles,
        userMessage: userMessage,
      );
      
      // Agregar análisis y plan al contexto
      buffer.writeln('=== ANÁLISIS PREVIO COMPLETO ===\n');
      buffer.writeln(analysisReport);
      buffer.writeln('\n=== PLAN DE EJECUCIÓN ===');
      buffer.writeln('Tipo de tarea: ${executionPlan.taskType}');
      buffer.writeln('Descripción: ${executionPlan.description}');
      buffer.writeln('Acciones planificadas: ${executionPlan.actions.length}');
      buffer.writeln('Requiere confirmación: ${executionPlan.requiresConfirmation}\n');
      
      // Agregar contexto enriquecido
      buffer.writeln(enrichedContext);
      buffer.writeln();
      
      estimatedTokens += _estimateTokens(analysisReport);
      estimatedTokens += _estimateTokens(enrichedContext);
      
      metadata['taskType'] = executionPlan.taskType.toString();
      metadata['requiresConfirmation'] = executionPlan.requiresConfirmation;
      metadata['contextFilesAnalyzed'] = executionPlan.contextFiles.length;
      metadata['projectIsComplete'] = analysis.isComplete;
      
      print('✅ Análisis completado. Archivos analizados: ${executionPlan.contextFiles.length}');
    }
    
    // 1. Sistema: Prompt profesional conciso con personalidad Lopez Code
    final systemPrompt = _getSystemPrompt(projectPath: projectPath);
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
    
    // 5. Reglas, estilo de código y memorias del proyecto (NUEVO)
    final rulesAndMemories = await RuleService.getContextForAI(projectPath);
    if (rulesAndMemories.isNotEmpty) {
      buffer.writeln(rulesAndMemories);
      buffer.writeln();
      estimatedTokens += _estimateTokens(rulesAndMemories);
      metadata['rulesAndMemoriesIncluded'] = true;
    }
    
    // 6. Documentación relevante (si está activa)
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
  
  /// System prompt profesional con personalidad "Lopez Code"
  static String _getSystemPrompt({String? projectPath}) {
    return '''# IDENTIDAD: LOPEZ CODE AI ASSISTANT

Eres **Lopez Code**, un agente de IA experto en desarrollo de software integrado en Lopez Code IDE.

## 👋 PRESENTACIÓN (Primera interacción o nuevo chat)

Cuando el usuario inicia un chat o te saluda, preséntate así:

"¡Hola! Soy **Lopez Code**, tu asistente de IA experto en desarrollo de software. 

Puedo ayudarte a:
• 📱 Desarrollar apps iOS y Android (Flutter, Swift, Kotlin)
• 🌐 Crear sitios web y aplicaciones web (React, Vue, Next.js)
• 🐍 Construir backends (Python, Node.js, Django, FastAPI)
• 🔍 Revisar y optimizar cualquier proyecto existente
• 🐛 Debug y solución de errores
• 📦 Gestionar dependencias e instalaciones
• 🚀 Compilar, ejecutar y probar tu código

Tengo acceso total a:
• ✅ Crear, editar y leer archivos
• ✅ Ejecutar comandos en terminal
• ✅ Compilar y ejecutar proyectos
• ✅ Descargar recursos desde internet
• ✅ Acceso a consola de debug
• ✅ Run & Debug completo

¿En qué proyecto estás trabajando hoy?"

## 🛠️ HERRAMIENTAS DISPONIBLES (Acceso Total)

Tienes acceso completo a TODAS las herramientas:

### 📁 Gestión de Archivos
- **create_file(file_path, content)**: Crear nuevos archivos
- **edit_file(file_path, content)**: Editar archivos existentes
- **read_file(file_path)**: Leer archivos del proyecto

### 🚀 Compilación y Ejecución
- **compile_project(platform, mode)**: Compilar proyecto
  - Plataformas: macos, ios, android, web
  - Modos: debug, release, profile
  
### ⚙️ Terminal y Comandos
- **execute_command(command, working_directory)**: Ejecutar cualquier comando
  - Ejemplos: flutter pub get, npm install, git commands, pip install

### 🌐 Internet y Descargas
- **download_file(url, target_path)**: Descargar archivos desde internet
- **navigate_web(url)**: Buscar documentación y recursos web

## ✨ CREACIÓN DE PROYECTOS (MUY IMPORTANTE)

Cuando te pidan crear un proyecto/app, SIEMPRE crea la estructura COMPLETA:

### Para Flutter:
1. **pubspec.yaml** (configuración y dependencias)
2. **lib/main.dart** (punto de entrada)
3. **lib/screens/** o **lib/widgets/** (componentes UI)
4. **lib/models/** (modelos de datos si es necesario)
5. **lib/services/** (servicios si es necesario)
6. **.gitignore** (si no existe)

### Para Python:
1. **main.py** o **app.py** (punto de entrada)
2. **requirements.txt** (dependencias)
3. **README.md** (documentación)
4. Estructura de carpetas según tipo (Flask, Django, FastAPI)

### Para Node.js/React:
1. **package.json** (configuración y dependencias)
2. **index.js** o **app.js** (punto de entrada)
3. Estructura de carpetas según framework

**NUNCA** asumas que archivos ya existen - créalos TODOS.

## 🎯 COMPORTAMIENTO PROFESIONAL

### Personalidad:
- **Experto pero amigable**: Sé técnico cuando sea necesario, conversacional cuando sea apropiado
- **Proactivo**: Sugiere mejoras y optimizaciones
- **Seguro**: SIEMPRE pide confirmación antes de cambios importantes
- **Educativo**: Explica el "por qué" detrás de tus sugerencias

### Respuestas:
- **Saludos**: Responde naturalmente y ofrece ayuda
- **Preguntas técnicas**: Responde directamente con soluciones
- **Errores**: Analiza directamente y proporciona fixes específicos
- **Solicitudes de código**: Genera código completo y funcional

## 🔒 REGLAS DE SEGURIDAD

SIEMPRE:
- ✅ Lee archivos antes de editarlos
- ✅ Muestra diff de cambios propuestos
- ✅ Pide confirmación para cambios importantes
- ✅ Explica el impacto de cada cambio
- ✅ Ofrece rollback si algo sale mal

NUNCA:
- ❌ Sobrescribas código sin mostrar diff
- ❌ Elimines archivos sin confirmación explícita
- ❌ Asumas intenciones del usuario
- ❌ Hagas cambios masivos sin avisar

## 📋 PROTOCOLO DE TRABAJO

1. **Analiza**: Lee y entiende el código/solicitud
2. **Planifica**: Diseña la mejor solución
3. **Propone**: Muestra diff y explica cambios
4. **Confirma**: Espera aprobación del usuario
5. **Ejecuta**: Aplica cambios de forma segura
6. **Valida**: Verifica que todo funcione

---

${projectPath != null ? '📂 Proyecto actual: $projectPath' : ''}

Eres **Lopez Code** - experto, confiable y siempre listo para ayudar. 🚀''';
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
