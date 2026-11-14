import '../models/pending_action.dart';
import 'chat_checkpoint.dart';

class Message {
  final String role; // 'user' o 'assistant'
  final String content;
  final DateTime timestamp;
  final List<String>? imageUrls;
  final String? codeBlock;
  final String? filePath;
  final List<PendingAction>? pendingActions; // ✅ NUEVO: Acciones pendientes para mostrar en el chat
  final bool isCancelled; // ✅ NUEVO: Indica si el mensaje fue cancelado
  final ChatCheckpoint? checkpoint; // Snapshot pre-edición (time-travel)
  /// El agente agotó sus pasos sin terminar: mostrar "Continuar tarea".
  final bool canContinueTask;

  Message({
    required this.role,
    required this.content,
    required this.timestamp,
    this.imageUrls,
    this.codeBlock,
    this.filePath,
    this.pendingActions, // ✅ NUEVO
    this.isCancelled = false, // ✅ NUEVO
    this.checkpoint,
    this.canContinueTask = false,
  });

  Message copyWith({
    String? role,
    String? content,
    DateTime? timestamp,
    List<String>? imageUrls,
    String? codeBlock,
    String? filePath,
    List<PendingAction>? pendingActions,
    bool? isCancelled,
    ChatCheckpoint? checkpoint,
    bool? canContinueTask,
  }) {
    return Message(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      imageUrls: imageUrls ?? this.imageUrls,
      codeBlock: codeBlock ?? this.codeBlock,
      filePath: filePath ?? this.filePath,
      pendingActions: pendingActions ?? this.pendingActions,
      isCancelled: isCancelled ?? this.isCancelled,
      checkpoint: checkpoint ?? this.checkpoint,
      canContinueTask: canContinueTask ?? this.canContinueTask,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'imageUrls': imageUrls,
      'codeBlock': codeBlock,
      'filePath': filePath,
      'pendingActions': pendingActions?.map((a) => a.toJson()).toList(),
      'isCancelled': isCancelled,
      'checkpoint': checkpoint?.toJson(),
      'canContinueTask': canContinueTask,
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
      isCancelled: json['isCancelled'] ?? false,
      checkpoint: json['checkpoint'] is Map
          ? ChatCheckpoint.fromJson(
              Map<String, dynamic>.from(json['checkpoint'] as Map),
            )
          : null,
      canContinueTask: json['canContinueTask'] == true,
    );
  }
}
