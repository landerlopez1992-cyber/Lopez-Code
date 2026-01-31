import 'dart:convert';

/// Servicio de gestión de contexto de conversación
/// Maneja el historial, resúmenes y memoria de la conversación

class ConversationContextService {
  // Historial completo de mensajes
  final List<ConversationMessage> _fullHistory = [];
  
  // Resúmenes de bloques antiguos
  final List<ConversationSummary> _summaries = [];
  
  // Entidades clave identificadas (archivos, clases, funciones mencionadas)
  final Map<String, EntityInfo> _entities = {};
  
  // Decisiones importantes tomadas
  final List<Decision> _decisions = [];
  
  // Configuración
  static const int _maxMessagesInContext = 20; // Mensajes recientes sin resumir
  static const int _summaryThreshold = 10; // Cada cuántos mensajes hacer resumen

  /// Agrega un mensaje al historial
  void addMessage({
    required String role,
    required String content,
    Map<String, dynamic>? metadata,
  }) {
    final message = ConversationMessage(
      role: role,
      content: content,
      timestamp: DateTime.now(),
      metadata: metadata,
    );

    _fullHistory.add(message);

    // Extraer entidades del mensaje
    _extractEntities(message);

    // Verificar si necesitamos hacer resumen
    if (_fullHistory.length % _summaryThreshold == 0) {
      _createSummary();
    }

    print('💬 Mensaje agregado al contexto (total: ${_fullHistory.length})');
  }

  /// Registra una decisión importante
  void recordDecision({
    required String decision,
    required String reasoning,
    String? impact,
    List<String>? affectedFiles,
  }) {
    final decisionRecord = Decision(
      decision: decision,
      reasoning: reasoning,
      impact: impact,
      affectedFiles: affectedFiles,
      timestamp: DateTime.now(),
    );

    _decisions.add(decisionRecord);
    print('📝 Decisión registrada: $decision');
  }

  /// Obtiene el contexto optimizado para enviar a la IA
  ConversationContext getOptimizedContext({int? maxTokens}) {
    final context = ConversationContext();

    // 1. Siempre incluir los mensajes más recientes
    final recentMessages = _fullHistory.length > _maxMessagesInContext
        ? _fullHistory.skip(_fullHistory.length - _maxMessagesInContext).toList()
        : _fullHistory;

    context.recentMessages = recentMessages;

    // 2. Incluir resúmenes de conversaciones anteriores
    context.summaries = _summaries;

    // 3. Incluir entidades clave mencionadas frecuentemente
    final sortedEntities = _entities.entries.toList()
      ..sort((a, b) => b.value.mentionCount.compareTo(a.value.mentionCount));
    
    context.keyEntities = sortedEntities
        .take(10)
        .map((e) => e.value)
        .toList();

    // 4. Incluir decisiones recientes
    context.recentDecisions = _decisions.reversed.take(5).toList();

    return context;
  }

  /// Obtiene un resumen del contexto actual para mostrar al usuario
  String getContextSummary() {
    final buffer = StringBuffer();

    buffer.writeln('📊 CONTEXTO DE CONVERSACIÓN');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('');

    // Mensajes
    buffer.writeln('💬 Mensajes: ${_fullHistory.length}');
    if (_summaries.isNotEmpty) {
      buffer.writeln('📑 Resúmenes: ${_summaries.length} bloques');
    }

    // Entidades
    if (_entities.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('🔑 Entidades Clave:');
      final topEntities = _entities.entries.toList()
        ..sort((a, b) => b.value.mentionCount.compareTo(a.value.mentionCount));
      
      for (var entry in topEntities.take(5)) {
        buffer.writeln('  - ${entry.key} (${entry.value.type}, mencionado ${entry.value.mentionCount} veces)');
      }
    }

    // Decisiones
    if (_decisions.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('✅ Decisiones Recientes:');
      for (var decision in _decisions.reversed.take(3)) {
        buffer.writeln('  - ${decision.decision}');
      }
    }

    return buffer.toString();
  }

  /// Busca mensajes relacionados con un tema
  List<ConversationMessage> searchMessages(String query) {
    final queryLower = query.toLowerCase();
    return _fullHistory.where((msg) =>
        msg.content.toLowerCase().contains(queryLower)
    ).toList();
  }

  /// Obtiene información sobre una entidad específica
  EntityInfo? getEntityInfo(String entityName) {
    return _entities[entityName];
  }

  /// Limpia el contexto (mantiene solo decisiones importantes)
  void clearContext({bool keepDecisions = true}) {
    _fullHistory.clear();
    _summaries.clear();
    _entities.clear();
    
    if (!keepDecisions) {
      _decisions.clear();
    }

    print('🗑️ Contexto limpiado');
  }

  // Métodos privados

  /// Extrae entidades mencionadas en un mensaje
  void _extractEntities(ConversationMessage message) {
    final content = message.content;

    // Extraer archivos .dart
    final fileMatches = RegExp(r'(\w+\.dart)').allMatches(content);
    for (var match in fileMatches) {
      final fileName = match.group(1)!;
      _updateEntity(fileName, EntityType.file);
    }

    // Extraer clases (palabras que empiezan con mayúscula)
    final classMatches = RegExp(r'\b([A-Z]\w+(?:Widget|Screen|Service|Model|Controller)?)\b').allMatches(content);
    for (var match in classMatches) {
      final className = match.group(1)!;
      if (className.length > 2) { // Evitar iniciales
        _updateEntity(className, EntityType.className);
      }
    }

    // Extraer funciones (palabras seguidas de paréntesis)
    final functionMatches = RegExp(r'(\w+)\s*\(').allMatches(content);
    for (var match in functionMatches) {
      final functionName = match.group(1)!;
      _updateEntity(functionName, EntityType.function);
    }
  }

  /// Actualiza o crea una entidad
  void _updateEntity(String name, EntityType type) {
    if (_entities.containsKey(name)) {
      _entities[name]!.mentionCount++;
      _entities[name]!.lastMentioned = DateTime.now();
    } else {
      _entities[name] = EntityInfo(
        name: name,
        type: type,
        mentionCount: 1,
        firstMentioned: DateTime.now(),
        lastMentioned: DateTime.now(),
      );
    }
  }

  /// Crea un resumen de un bloque de mensajes
  void _createSummary() {
    if (_fullHistory.length < _summaryThreshold) return;

    // Tomar mensajes antiguos para resumir (excepto los últimos _maxMessagesInContext)
    final messagesToSummarize = _fullHistory.length > _maxMessagesInContext
        ? _fullHistory.take(_fullHistory.length - _maxMessagesInContext).toList()
        : <ConversationMessage>[];

    if (messagesToSummarize.isEmpty) return;

    // Generar resumen simple (en producción, esto podría usar la IA)
    final summary = _generateSimpleSummary(messagesToSummarize);

    _summaries.add(ConversationSummary(
      summary: summary,
      messageCount: messagesToSummarize.length,
      startTime: messagesToSummarize.first.timestamp,
      endTime: messagesToSummarize.last.timestamp,
    ));

    print('📝 Resumen creado: ${messagesToSummarize.length} mensajes');
  }

  /// Genera un resumen simple de mensajes
  String _generateSimpleSummary(List<ConversationMessage> messages) {
    final topics = <String>[];
    final filesDiscussed = <String>{};
    final actions = <String>[];

    for (var msg in messages) {
      // Extraer archivos mencionados
      final fileMatches = RegExp(r'(\w+\.dart)').allMatches(msg.content);
      for (var match in fileMatches) {
        filesDiscussed.add(match.group(1)!);
      }

      // Detectar acciones (verbos clave)
      if (msg.content.contains('crear') || msg.content.contains('crear')) {
        actions.add('creación');
      }
      if (msg.content.contains('editar') || msg.content.contains('modificar')) {
        actions.add('edición');
      }
      if (msg.content.contains('analizar') || msg.content.contains('revisar')) {
        actions.add('análisis');
      }
    }

    final buffer = StringBuffer();
    buffer.write('Conversación sobre ');

    if (filesDiscussed.isNotEmpty) {
      buffer.write('${filesDiscussed.join(", ")}');
    } else {
      buffer.write('el proyecto');
    }

    if (actions.isNotEmpty) {
      buffer.write(' con ${actions.toSet().join(" y ")}');
    }

    buffer.write('. ${messages.length} mensajes.');

    return buffer.toString();
  }
}

/// Mensaje de conversación
class ConversationMessage {
  final String role; // 'user', 'assistant', 'system'
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  ConversationMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      role: json['role'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      metadata: json['metadata'],
    );
  }
}

/// Resumen de un bloque de conversación
class ConversationSummary {
  final String summary;
  final int messageCount;
  final DateTime startTime;
  final DateTime endTime;

  ConversationSummary({
    required this.summary,
    required this.messageCount,
    required this.startTime,
    required this.endTime,
  });
}

/// Información de una entidad (archivo, clase, función)
class EntityInfo {
  final String name;
  final EntityType type;
  int mentionCount;
  final DateTime firstMentioned;
  DateTime lastMentioned;

  EntityInfo({
    required this.name,
    required this.type,
    required this.mentionCount,
    required this.firstMentioned,
    required this.lastMentioned,
  });
}

/// Tipos de entidades
enum EntityType {
  file,
  className,
  function,
  variable,
  constant,
}

/// Decisión registrada
class Decision {
  final String decision;
  final String reasoning;
  final String? impact;
  final List<String>? affectedFiles;
  final DateTime timestamp;

  Decision({
    required this.decision,
    required this.reasoning,
    this.impact,
    this.affectedFiles,
    required this.timestamp,
  });
}

/// Contexto optimizado de conversación
class ConversationContext {
  List<ConversationMessage> recentMessages = [];
  List<ConversationSummary> summaries = [];
  List<EntityInfo> keyEntities = [];
  List<Decision> recentDecisions = [];

  /// Convierte el contexto a texto para enviar a la IA
  String toPromptText() {
    final buffer = StringBuffer();

    // Resúmenes de conversaciones anteriores
    if (summaries.isNotEmpty) {
      buffer.writeln('=== CONVERSACIONES ANTERIORES (RESUMIDAS) ===');
      for (var summary in summaries) {
        buffer.writeln('- ${summary.summary}');
      }
      buffer.writeln('');
    }

    // Entidades clave
    if (keyEntities.isNotEmpty) {
      buffer.writeln('=== ENTIDADES CLAVE MENCIONADAS ===');
      for (var entity in keyEntities) {
        buffer.writeln('- ${entity.name} (${entity.type.name}, ${entity.mentionCount} menciones)');
      }
      buffer.writeln('');
    }

    // Decisiones recientes
    if (recentDecisions.isNotEmpty) {
      buffer.writeln('=== DECISIONES IMPORTANTES ===');
      for (var decision in recentDecisions) {
        buffer.writeln('- ${decision.decision}');
        buffer.writeln('  Razón: ${decision.reasoning}');
      }
      buffer.writeln('');
    }

    // Mensajes recientes
    buffer.writeln('=== CONVERSACIÓN RECIENTE ===');
    for (var msg in recentMessages) {
      buffer.writeln('${msg.role.toUpperCase()}: ${msg.content}');
    }

    return buffer.toString();
  }

  /// Estima el número de tokens aproximado
  int estimateTokens() {
    // Aproximación: 1 token ≈ 4 caracteres
    final text = toPromptText();
    return (text.length / 4).ceil();
  }
}
