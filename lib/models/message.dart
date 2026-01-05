class Message {
  final String role; // 'user' o 'assistant'
  final String content;
  final DateTime timestamp;
  final List<String>? imageUrls;
  final String? codeBlock;
  final String? filePath;

  Message({
    required this.role,
    required this.content,
    required this.timestamp,
    this.imageUrls,
    this.codeBlock,
    this.filePath,
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'imageUrls': imageUrls,
      'codeBlock': codeBlock,
      'filePath': filePath,
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
    );
  }
}


