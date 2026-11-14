/// Snapshot de un archivo dentro de un checkpoint (time-travel).
class CheckpointFileEntry {
  /// Ruta absoluta original en el proyecto.
  final String originalPath;

  /// Ruta relativa al [ChatCheckpoint.projectPath].
  final String relativePath;

  /// Ruta del snapshot en `.voryxel/checkpoints/...`.
  /// `null` cuando [wasNewFile] es `true` (no había contenido previo).
  final String? backupPath;

  /// `true` si el archivo no existía al crear el checkpoint;
  /// al restaurar se elimina.
  final bool wasNewFile;

  /// Tamaño del contenido snapshot (0 si era nuevo).
  final int fileSize;

  /// Checksum simple del contenido snapshot (vacío si era nuevo).
  final String checksum;

  const CheckpointFileEntry({
    required this.originalPath,
    required this.relativePath,
    required this.backupPath,
    required this.wasNewFile,
    this.fileSize = 0,
    this.checksum = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'originalPath': originalPath,
      'relativePath': relativePath,
      'backupPath': backupPath,
      'wasNewFile': wasNewFile,
      'fileSize': fileSize,
      'checksum': checksum,
    };
  }

  factory CheckpointFileEntry.fromJson(Map<String, dynamic> json) {
    return CheckpointFileEntry(
      originalPath: json['originalPath'] as String? ?? '',
      relativePath: json['relativePath'] as String? ?? '',
      backupPath: json['backupPath'] as String?,
      wasNewFile: json['wasNewFile'] as bool? ?? false,
      fileSize: json['fileSize'] as int? ?? 0,
      checksum: json['checksum'] as String? ?? '',
    );
  }

  CheckpointFileEntry copyWith({
    String? originalPath,
    String? relativePath,
    String? backupPath,
    bool? wasNewFile,
    int? fileSize,
    String? checksum,
  }) {
    return CheckpointFileEntry(
      originalPath: originalPath ?? this.originalPath,
      relativePath: relativePath ?? this.relativePath,
      backupPath: backupPath ?? this.backupPath,
      wasNewFile: wasNewFile ?? this.wasNewFile,
      fileSize: fileSize ?? this.fileSize,
      checksum: checksum ?? this.checksum,
    );
  }
}

/// Checkpoint de chat: agrupa varios snapshots bajo un mismo [checkpointId].
///
/// Asociado a un turno/mensaje del asistente para restauración con 1 clic.
class ChatCheckpoint {
  final String checkpointId;
  final String projectPath;
  final String label;
  final DateTime timestamp;

  /// ID del mensaje / turno del chat (opcional, para enlazar en UI).
  final String? messageId;

  final List<CheckpointFileEntry> files;

  /// `true` si ya se restauró al menos una vez (informativo).
  final bool restored;

  const ChatCheckpoint({
    required this.checkpointId,
    required this.projectPath,
    required this.label,
    required this.timestamp,
    required this.files,
    this.messageId,
    this.restored = false,
  });

  int get modifiedFileCount => files.length;

  List<String> get relativeFilePaths =>
      files.map((f) => f.relativePath).toList(growable: false);

  Map<String, dynamic> toJson() {
    return {
      'checkpointId': checkpointId,
      'projectPath': projectPath,
      'label': label,
      'timestamp': timestamp.toIso8601String(),
      'messageId': messageId,
      'files': files.map((f) => f.toJson()).toList(),
      'restored': restored,
    };
  }

  factory ChatCheckpoint.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    final files = rawFiles is List
        ? rawFiles
            .whereType<Map>()
            .map((e) => CheckpointFileEntry.fromJson(
                  Map<String, dynamic>.from(e),
                ))
            .toList()
        : <CheckpointFileEntry>[];

    return ChatCheckpoint(
      checkpointId: json['checkpointId'] as String? ?? '',
      projectPath: json['projectPath'] as String? ?? '',
      label: json['label'] as String? ?? 'Checkpoint',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      messageId: json['messageId'] as String?,
      files: files,
      restored: json['restored'] as bool? ?? false,
    );
  }

  ChatCheckpoint copyWith({
    String? checkpointId,
    String? projectPath,
    String? label,
    DateTime? timestamp,
    String? messageId,
    List<CheckpointFileEntry>? files,
    bool? restored,
  }) {
    return ChatCheckpoint(
      checkpointId: checkpointId ?? this.checkpointId,
      projectPath: projectPath ?? this.projectPath,
      label: label ?? this.label,
      timestamp: timestamp ?? this.timestamp,
      messageId: messageId ?? this.messageId,
      files: files ?? this.files,
      restored: restored ?? this.restored,
    );
  }
}
