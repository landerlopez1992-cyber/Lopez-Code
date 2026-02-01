import '../models/pending_action.dart';

class Message {
  final String role; // 'user' o 'assistant'
  final String content;
  final DateTime timestamp;
  final List<String>? imageUrls;
  final String? codeBlock;
  final String? filePath;
  final List<PendingAction>? pendingActions; // ✅ NUEVO: Acciones pendientes para mostrar en el chat

  Message({
    required this.role,
    required this.content,
    required this.timestamp,
    this.imageUrls,
    this.codeBlock,
    this.filePath,
    this.pendingActions, // ✅ NUEVO
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'imageUrls': imageUrls,
      'codeBlock': codeBlock,
      'filePath': filePath,
      'pendingActions': pendingActions?.map((a) => a.toJson()).toList(),
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      role: json['role'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      imageUrls: json['imageUrls'] != null ? List<String>.from(json['imageUrls']) : null,
      codeBlock: json['codeBlock'],
      filePath: json['filePath'],
      pendingActions: json['pendingActions'] != null
          ? (json['pendingActions'] as List)
              .map((a) => PendingAction.fromJson(a))
              .toList()
          : null,
    );
  }
}


