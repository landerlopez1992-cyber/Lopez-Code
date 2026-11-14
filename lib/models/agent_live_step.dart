/// Paso en vivo del agente (tarjeta estilo Cursor en el chat).
enum AgentLiveStepKind {
  edit,
  create,
  explore,
  search,
  shell,
  browser,
  status,
  thought,
}

class AgentLiveStepLine {
  /// `+` | `-` | ` ` (contexto)
  final String mark;
  final String text;
  final int? lineNumber;

  const AgentLiveStepLine({
    required this.mark,
    required this.text,
    this.lineNumber,
  });

  Map<String, dynamic> toJson() => {
        'mark': mark,
        'text': text,
        if (lineNumber != null) 'lineNumber': lineNumber,
      };

  factory AgentLiveStepLine.fromJson(Map<String, dynamic> json) {
    return AgentLiveStepLine(
      mark: json['mark'] as String? ?? ' ',
      text: json['text'] as String? ?? '',
      lineNumber: json['lineNumber'] as int?,
    );
  }
}

class AgentLiveStep {
  final String id;
  final AgentLiveStepKind kind;
  final String title;
  final String? filePath;
  final int? added;
  final int? removed;
  final List<AgentLiveStepLine> previewLines;
  final String? command;
  final String? output;
  final bool running;
  final DateTime at;

  const AgentLiveStep({
    required this.id,
    required this.kind,
    required this.title,
    this.filePath,
    this.added,
    this.removed,
    this.previewLines = const [],
    this.command,
    this.output,
    this.running = false,
    required this.at,
  });

  String get fileName {
    final p = filePath;
    if (p == null || p.isEmpty) return title;
    return p.split('/').last;
  }

  String? get statsLabel {
    if (added == null && removed == null) return null;
    final a = added ?? 0;
    final r = removed ?? 0;
    if (a == 0 && r == 0) return null;
    return '+$a -$r';
  }

  AgentLiveStep copyWith({
    String? id,
    AgentLiveStepKind? kind,
    String? title,
    String? filePath,
    int? added,
    int? removed,
    List<AgentLiveStepLine>? previewLines,
    String? command,
    String? output,
    bool? running,
    DateTime? at,
  }) {
    return AgentLiveStep(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      added: added ?? this.added,
      removed: removed ?? this.removed,
      previewLines: previewLines ?? this.previewLines,
      command: command ?? this.command,
      output: output ?? this.output,
      running: running ?? this.running,
      at: at ?? this.at,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'filePath': filePath,
        'added': added,
        'removed': removed,
        'previewLines': previewLines.map((e) => e.toJson()).toList(),
        'command': command,
        'output': output,
        'running': running,
        'at': at.toIso8601String(),
      };

  factory AgentLiveStep.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'] as String? ?? 'status';
    final kind = AgentLiveStepKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => AgentLiveStepKind.status,
    );
    final linesRaw = json['previewLines'];
    final lines = <AgentLiveStepLine>[];
    if (linesRaw is List) {
      for (final item in linesRaw) {
        if (item is Map) {
          lines.add(
            AgentLiveStepLine.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return AgentLiveStep(
      id: json['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      kind: kind,
      title: json['title'] as String? ?? '',
      filePath: json['filePath'] as String?,
      added: json['added'] as int?,
      removed: json['removed'] as int?,
      previewLines: lines,
      command: json['command'] as String?,
      output: json['output'] as String?,
      running: json['running'] == true,
      at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
