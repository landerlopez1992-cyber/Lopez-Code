import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio profesional para gestionar memoria de conversaciones
/// Sistema inteligente que mantiene contexto histórico sin desperdiciar tokens
class ConversationMemoryService {
  static const String _currentSessionKey = 'current_session';
  static const int _maxMessagesInMemory = 50; // Últimos 50 mensajes
  
  /// Guarda un mensaje en la conversación actual
  static Future<bool> addMessage({
    required String role,
    required String content,
    String? sessionId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Obtener o crear sesión actual
      final currentSessionId = sessionId ?? await _getCurrentSessionId();
      
      // Obtener historial de la sesión
      final messages = await getSessionMessages(currentSessionId);
      
      // Crear nuevo mensaje
      final message = ConversationMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        sessionId: currentSessionId,
        role: role,
        content: content,
        timestamp: DateTime.now(),
        metadata: metadata,
      );
      
      // Agregar mensaje
      messages.add(message);
      
      // Limitar tamaño del historial
      final limitedMessages = messages.length > _maxMessagesInMemory
          ? messages.sublist(messages.length - _maxMessagesInMemory)
          : messages;
      
      // Guardar
      return await _saveSessionMessages(currentSessionId, limitedMessages);
    } catch (e) {
      print('❌ Error al guardar mensaje: $e');
      return false;
    }
  }
  
  /// Obtiene el historial de mensajes de una sesión
  static Future<List<ConversationMessage>> getSessionMessages(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'session_$sessionId';
      final jsonString = prefs.getString(key);
      
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }
      
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => ConversationMessage.fromJson(json)).toList();
    } catch (e) {
      print('❌ Error al cargar mensajes: $e');
      return [];
    }
  }
  
  /// Guarda mensajes de una sesión
  static Future<bool> _saveSessionMessages(
    String sessionId,
    List<ConversationMessage> messages,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'session_$sessionId';
      final jsonList = messages.map((m) => m.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      
      final success = await prefs.setString(key, jsonString);
      
      if (success) {
        print('✅ Guardados ${messages.length} mensajes en sesión $sessionId');
      }
      
      return success;
    } catch (e) {
      print('❌ Error al guardar mensajes: $e');
      return false;
    }
  }
  
  /// Obtiene el ID de la sesión actual
  static Future<String> _getCurrentSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    var sessionId = prefs.getString(_currentSessionKey);
    
    if (sessionId == null) {
      sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(_currentSessionKey, sessionId);
    }
    
    return sessionId;
  }
  
  /// Inicia una nueva sesión de conversación
  static Future<String> startNewSession() async {
    final sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentSessionKey, sessionId);
    print('🆕 Nueva sesión iniciada: $sessionId');
    return sessionId;
  }
  
  /// Obtiene contexto optimizado para enviar a la IA
  /// Solo incluye lo necesario para ahorrar tokens
  static Future<String> getOptimizedContext({
    String? sessionId,
    int maxMessages = 10,
    bool includeSystemInfo = false,
  }) async {
    try {
      final currentSessionId = sessionId ?? await _getCurrentSessionId();
      final messages = await getSessionMessages(currentSessionId);
      
      if (messages.isEmpty) {
        return '';
      }
      
      // Obtener últimos N mensajes
      final recentMessages = messages.length > maxMessages
          ? messages.sublist(messages.length - maxMessages)
          : messages;
      
      // Formatear contexto
      final buffer = StringBuffer();
      
      if (includeSystemInfo) {
        buffer.writeln('=== CONTEXTO DE CONVERSACIÓN ===\n');
      }
      
      for (final message in recentMessages) {
        final roleLabel = message.role == 'user' ? 'Usuario' : 'Asistente';
        buffer.writeln('[$roleLabel]:');
        buffer.writeln(message.content);
        buffer.writeln();
      }
      
      return buffer.toString();
    } catch (e) {
      print('❌ Error al obtener contexto: $e');
      return '';
    }
  }
  
  /// Genera un resumen de la conversación para ahorrar tokens
  static Future<String> generateSummary(String sessionId) async {
    try {
      final messages = await getSessionMessages(sessionId);
      
      if (messages.isEmpty) {
        return 'Sin conversación previa.';
      }
      
      // Contar mensajes por rol
      final userMessages = messages.where((m) => m.role == 'user').length;
      final assistantMessages = messages.where((m) => m.role == 'assistant').length;
      
      // Identificar temas principales (palabras clave)
      final allContent = messages.map((m) => m.content).join(' ');
      final keywords = _extractKeywords(allContent);
      
      final buffer = StringBuffer();
      buffer.writeln('RESUMEN DE CONVERSACIÓN:');
      buffer.writeln('- Total de mensajes: ${messages.length}');
      buffer.writeln('- Mensajes del usuario: $userMessages');
      buffer.writeln('- Respuestas del asistente: $assistantMessages');
      buffer.writeln('- Temas discutidos: ${keywords.join(', ')}');
      
      return buffer.toString();
    } catch (e) {
      print('❌ Error al generar resumen: $e');
      return 'Error al generar resumen.';
    }
  }
  
  /// Extrae palabras clave del texto
  static List<String> _extractKeywords(String text) {
    // Palabras comunes a ignorar
    final stopWords = {
      'el', 'la', 'de', 'que', 'y', 'a', 'en', 'un', 'ser', 'se', 'no',
      'haber', 'por', 'con', 'su', 'para', 'como', 'estar', 'tener',
      'the', 'be', 'to', 'of', 'and', 'in', 'that', 'have', 'it',
    };
    
    // Extraer palabras y contar frecuencia
    final words = text.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3 && !stopWords.contains(w));
    
    final frequency = <String, int>{};
    for (final word in words) {
      frequency[word] = (frequency[word] ?? 0) + 1;
    }
    
    // Obtener top 5 palabras más frecuentes
    final sorted = frequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sorted.take(5).map((e) => e.key).toList();
  }
  
  /// Limpia conversaciones antiguas para liberar espacio
  static Future<void> cleanOldSessions({int daysToKeep = 30}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
      
      int cleaned = 0;
      
      for (final key in keys) {
        if (key.startsWith('session_')) {
          final sessionId = key.substring(8);
          final messages = await getSessionMessages(sessionId);
          
          if (messages.isNotEmpty) {
            final lastMessage = messages.last;
            if (lastMessage.timestamp.isBefore(cutoffDate)) {
              await prefs.remove(key);
              cleaned++;
            }
          }
        }
      }
      
      if (cleaned > 0) {
        print('🧹 Limpiadas $cleaned sesiones antiguas');
      }
    } catch (e) {
      print('❌ Error al limpiar sesiones: $e');
    }
  }
  
  /// Obtiene todas las sesiones disponibles
  static Future<List<SessionSummary>> getAllSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final sessions = <SessionSummary>[];
      
      for (final key in keys) {
        if (key.startsWith('session_')) {
          final sessionId = key.substring(8);
          final messages = await getSessionMessages(sessionId);
          
          if (messages.isNotEmpty) {
            sessions.add(SessionSummary(
              id: sessionId,
              messageCount: messages.length,
              lastMessageAt: messages.last.timestamp,
              firstMessage: messages.first.content,
            ));
          }
        }
      }
      
      // Ordenar por fecha (más reciente primero)
      sessions.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      
      return sessions;
    } catch (e) {
      print('❌ Error al obtener sesiones: $e');
      return [];
    }
  }
}

/// Modelo de mensaje de conversación
class ConversationMessage {
  final String id;
  final String sessionId;
  final String role; // 'user' o 'assistant'
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  
  ConversationMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.timestamp,
    this.metadata,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'metadata': metadata,
  };
  
  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      id: json['id'] ?? '',
      sessionId: json['sessionId'] ?? '',
      role: json['role'] ?? 'user',
      content: json['content'] ?? '',
      timestamp: DateTime.parse(
        json['timestamp'] ?? DateTime.now().toIso8601String(),
      ),
      metadata: json['metadata'],
    );
  }
}

/// Resumen de sesión
class SessionSummary {
  final String id;
  final int messageCount;
  final DateTime lastMessageAt;
  final String firstMessage;
  
  SessionSummary({
    required this.id,
    required this.messageCount,
    required this.lastMessageAt,
    required this.firstMessage,
  });
}
