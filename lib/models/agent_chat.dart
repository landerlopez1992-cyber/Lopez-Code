import 'message.dart';

class AgentChat {
  final String id;
  final String name;
  final List<Message> messages;
  final DateTime createdAt;
  final DateTime? lastUpdated;
  final String? projectPath; // Vincular chat con proyecto
  bool isActive;

  AgentChat({
    required this.id,
    required this.name,
    required this.messages,
    required this.createdAt,
    this.lastUpdated,
    this.projectPath,
    this.isActive = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'messages': messages.map((m) => m.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated?.toIso8601String(),
      'projectPath': projectPath,
      'isActive': isActive,
    };
  }

  factory AgentChat.fromJson(Map<String, dynamic> json) {
    return AgentChat(
      id: json['id'],
      name: json['name'],
      messages: (json['messages'] as List)
          .map((m) => Message.fromJson(m))
          .toList(),
      createdAt: DateTime.parse(json['createdAt']),
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'])
          : null,
      projectPath: json['projectPath'],
      isActive: json['isActive'] ?? false,
    );
  }

  AgentChat copyWith({
    String? name,
    List<Message>? messages,
    DateTime? lastUpdated,
    String? projectPath,
    bool? isActive,
  }) {
    return AgentChat(
      id: id,
      name: name ?? this.name,
      messages: messages ?? this.messages,
      createdAt: createdAt,
      lastUpdated: lastUpdated ?? DateTime.now(),
      projectPath: projectPath ?? this.projectPath,
      isActive: isActive ?? this.isActive,
    );
  }
}

