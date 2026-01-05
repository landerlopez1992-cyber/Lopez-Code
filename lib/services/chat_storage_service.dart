import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_session.dart';
import '../models/agent_chat.dart';
import '../models/message.dart';

class ChatStorageService {
  static const String _sessionsKey = 'chat_sessions';
  static const String _agentChatsKey = 'agent_chats';
  static const String _currentSessionKey = 'current_session_id';

  // Guardar todas las sesiones
  static Future<void> saveSessions(List<ChatSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final sessionsJson = sessions.map((s) => s.toJson()).toList();
    await prefs.setString(_sessionsKey, jsonEncode(sessionsJson));
  }

  // Cargar todas las sesiones
  static Future<List<ChatSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionsJson = prefs.getString(_sessionsKey);
    
    if (sessionsJson == null || sessionsJson.isEmpty) {
      return [];
    }
    
    try {
      final List<dynamic> decoded = jsonDecode(sessionsJson);
      return decoded.map((json) => ChatSession.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  // Guardar una sesión específica
  static Future<void> saveSession(ChatSession session) async {
    final sessions = await loadSessions();
    final index = sessions.indexWhere((s) => s.id == session.id);
    
    if (index >= 0) {
      sessions[index] = session;
    } else {
      sessions.add(session);
    }
    
    await saveSessions(sessions);
  }

  // Guardar agentes
  static Future<void> saveAgentChats(List<AgentChat> chats) async {
    final prefs = await SharedPreferences.getInstance();
    final chatsJson = chats.map((c) => c.toJson()).toList();
    await prefs.setString(_agentChatsKey, jsonEncode(chatsJson));
  }

  // Cargar agentes
  static Future<List<AgentChat>> loadAgentChats() async {
    final prefs = await SharedPreferences.getInstance();
    final chatsJson = prefs.getString(_agentChatsKey);
    
    if (chatsJson == null || chatsJson.isEmpty) {
      return [];
    }
    
    try {
      final List<dynamic> decoded = jsonDecode(chatsJson);
      return decoded.map((json) => AgentChat.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  // Guardar un agente específico
  static Future<void> saveAgentChat(AgentChat chat) async {
    final chats = await loadAgentChats();
    final index = chats.indexWhere((c) => c.id == chat.id);
    
    if (index >= 0) {
      chats[index] = chat;
    } else {
      chats.add(chat);
    }
    
    await saveAgentChats(chats);
  }

  // Cargar mensajes de un agente
  static Future<List<dynamic>> loadAgentMessages(String chatId) async {
    final chat = (await loadAgentChats()).firstWhere(
      (c) => c.id == chatId,
      orElse: () => AgentChat(
        id: chatId,
        name: 'Agente',
        messages: [],
        createdAt: DateTime.now(),
      ),
    );
    return chat.messages.map((m) => m.toJson()).toList();
  }

  // Guardar mensajes de un agente
  static Future<void> saveAgentMessages(String chatId, List<dynamic> messages, {String? projectPath}) async {
    final allChats = await loadAgentChats();
    final chat = allChats.firstWhere(
      (c) => c.id == chatId,
      orElse: () => AgentChat(
        id: chatId,
        name: 'Agente',
        messages: [],
        createdAt: DateTime.now(),
        projectPath: projectPath,
      ),
    );
    
    // Convertir mensajes a Message objects
    final messageObjects = messages.map((m) => Message.fromJson(m)).toList();
    final updatedChat = chat.copyWith(
      messages: messageObjects,
      lastUpdated: DateTime.now(),
      projectPath: projectPath ?? chat.projectPath,
    );
    
    await saveAgentChat(updatedChat);
  }

  // Eliminar una sesión
  static Future<void> deleteSession(String sessionId) async {
    final sessions = await loadSessions();
    sessions.removeWhere((s) => s.id == sessionId);
    await saveSessions(sessions);
  }

  // Obtener sesión actual
  static Future<String?> getCurrentSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentSessionKey);
  }

  // Establecer sesión actual
  static Future<void> setCurrentSessionId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentSessionKey, sessionId);
  }

  // Cargar sesión actual
  static Future<ChatSession?> loadCurrentSession() async {
    final sessionId = await getCurrentSessionId();
    if (sessionId == null) return null;
    
    final sessions = await loadSessions();
    try {
      return sessions.firstWhere((s) => s.id == sessionId);
    } catch (e) {
      return null;
    }
  }
}
