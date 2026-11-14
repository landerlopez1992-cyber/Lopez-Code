import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/chat_checkpoint.dart';

/// Time-travel de archivos: checkpoints agrupados por turno de chat.
///
/// Persistencia por proyecto en `.lopez_code/checkpoints/`.
/// Independiente de chat / OpenAI / BackupService (usa su propia carpeta).
class CheckpointService {
  CheckpointService._();

  static const String _rootDirName = '.lopez_code';
  static const String _checkpointsDirName = 'checkpoints';
  static const String _indexFileName = 'index.json';
  static const String _metaFileName = 'meta.json';
  static const String _filesDirName = 'files';

  /// Crea un checkpoint (snapshot) de [filePaths] antes de modificarlos.
  ///
  /// - Si el archivo existe: guarda su contenido y lo asocia al checkpoint.
  /// - Si no existe: marca [CheckpointFileEntry.wasNewFile] para eliminarlo
  ///   al restaurar (archivo creado en ese turno).
  static Future<ChatCheckpoint> createCheckpoint({
    required String projectPath,
    required String label,
    required List<String> filePaths,
    String? messageId,
  }) async {
    final root = _normalizePath(projectPath);
    final projectDir = Directory(root);
    if (!await projectDir.exists()) {
      throw FileSystemException(
        'El directorio del proyecto no existe',
        root,
      );
    }

    final uniquePaths = _dedupePaths(filePaths);
    if (uniquePaths.isEmpty) {
      throw ArgumentError('filePaths no puede estar vacío');
    }

    final checkpointId = _generateCheckpointId();
    final checkpointDir = await _ensureCheckpointDir(root, checkpointId);
    final snapshotsDir = Directory(_join(checkpointDir.path, _filesDirName));
    await snapshotsDir.create(recursive: true);

    final entries = <CheckpointFileEntry>[];

    for (final rawPath in uniquePaths) {
      final absolute = _resolveAbsolute(rawPath, root);
      final relative = _toRelative(absolute, root);
      final file = File(absolute);

      if (await file.exists()) {
        final content = await file.readAsString();
        final snapshotName = _encodeRelativePath(relative);
        final backupPath = _join(snapshotsDir.path, snapshotName);
        await File(backupPath).writeAsString(content);

        entries.add(
          CheckpointFileEntry(
            originalPath: absolute,
            relativePath: relative,
            backupPath: backupPath,
            wasNewFile: false,
            fileSize: content.length,
            checksum: _checksum(content),
          ),
        );
      } else {
        entries.add(
          CheckpointFileEntry(
            originalPath: absolute,
            relativePath: relative,
            backupPath: null,
            wasNewFile: true,
          ),
        );
      }
    }

    final checkpoint = ChatCheckpoint(
      checkpointId: checkpointId,
      projectPath: root,
      label: label.trim().isEmpty ? 'Checkpoint' : label.trim(),
      timestamp: DateTime.now(),
      messageId: messageId,
      files: entries,
    );

    await _writeMeta(checkpointDir, checkpoint);
    await _upsertIndex(root, checkpoint);

    return checkpoint;
  }

  /// Restaura todos los archivos del checkpoint a su estado previo.
  ///
  /// - Archivos existentes en el snapshot → se reescriben.
  /// - Archivos marcados como nuevos → se eliminan.
  static Future<void> restoreCheckpoint(ChatCheckpoint checkpoint) async {
    final errors = <String>[];

    for (final entry in checkpoint.files) {
      try {
        if (entry.wasNewFile) {
          final created = File(entry.originalPath);
          if (await created.exists()) {
            await created.delete();
            await _removeEmptyParents(
              entry.originalPath,
              checkpoint.projectPath,
            );
          }
          continue;
        }

        final backupPath = entry.backupPath;
        if (backupPath == null || backupPath.isEmpty) {
          errors.add('${entry.relativePath}: sin snapshot');
          continue;
        }

        final backupFile = File(backupPath);
        if (!await backupFile.exists()) {
          errors.add('${entry.relativePath}: snapshot no encontrado');
          continue;
        }

        final content = await backupFile.readAsString();
        if (entry.checksum.isNotEmpty &&
            _checksum(content) != entry.checksum) {
          // Advertencia no bloqueante: se restaura igual.
        }

        final target = File(entry.originalPath);
        final parent = target.parent;
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }
        await target.writeAsString(content);
      } catch (e) {
        errors.add('${entry.relativePath}: $e');
      }
    }

    final updated = checkpoint.copyWith(restored: true);
    final checkpointDir = Directory(
      _join(
        _checkpointsRoot(checkpoint.projectPath),
        checkpoint.checkpointId,
      ),
    );
    if (await checkpointDir.exists()) {
      await _writeMeta(checkpointDir, updated);
      await _upsertIndex(checkpoint.projectPath, updated);
    }

    if (errors.isNotEmpty) {
      throw StateError(
        'Restauración parcial (${errors.length} error(es)): '
        '${errors.join('; ')}',
      );
    }
  }

  /// Lista checkpoints del proyecto (más recientes primero).
  static Future<List<ChatCheckpoint>> listCheckpoints(String projectPath) async {
    final root = _normalizePath(projectPath);
    final index = await _readIndex(root);
    final checkpoints = <ChatCheckpoint>[];

    for (final summary in index) {
      final id = summary['checkpointId'] as String?;
      if (id == null || id.isEmpty) continue;
      final full = await getCheckpoint(root, id);
      if (full != null) {
        checkpoints.add(full);
      }
    }

    checkpoints.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return checkpoints;
  }

  /// Carga un checkpoint por id, o `null` si no existe.
  static Future<ChatCheckpoint?> getCheckpoint(
    String projectPath,
    String checkpointId,
  ) async {
    final root = _normalizePath(projectPath);
    final metaFile = File(
      _join(_checkpointsRoot(root), checkpointId, _metaFileName),
    );
    if (!await metaFile.exists()) return null;

    try {
      final json = jsonDecode(await metaFile.readAsString());
      if (json is! Map) return null;
      return ChatCheckpoint.fromJson(Map<String, dynamic>.from(json));
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Elimina un checkpoint y sus snapshots del disco.
  static Future<bool> deleteCheckpoint(
    String projectPath,
    String checkpointId,
  ) async {
    final root = _normalizePath(projectPath);
    final dir = Directory(_join(_checkpointsRoot(root), checkpointId));
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await _removeFromIndex(root, checkpointId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Busca el checkpoint asociado a un [messageId] (si existe).
  static Future<ChatCheckpoint?> findByMessageId({
    required String projectPath,
    required String messageId,
  }) async {
    if (messageId.isEmpty) return null;
    final all = await listCheckpoints(projectPath);
    for (final cp in all) {
      if (cp.messageId == messageId) return cp;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Persistencia
  // ---------------------------------------------------------------------------

  static String _checkpointsRoot(String projectPath) {
    return _join(
      _normalizePath(projectPath),
      _rootDirName,
      _checkpointsDirName,
    );
  }

  static Future<Directory> _ensureCheckpointDir(
    String projectPath,
    String checkpointId,
  ) async {
    final dir = Directory(_join(_checkpointsRoot(projectPath), checkpointId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<void> _writeMeta(
    Directory checkpointDir,
    ChatCheckpoint checkpoint,
  ) async {
    final meta = File(_join(checkpointDir.path, _metaFileName));
    const encoder = JsonEncoder.withIndent('  ');
    await meta.writeAsString(encoder.convert(checkpoint.toJson()));
  }

  static Future<List<Map<String, dynamic>>> _readIndex(
    String projectPath,
  ) async {
    final indexFile = File(_join(_checkpointsRoot(projectPath), _indexFileName));
    if (!await indexFile.exists()) return [];

    try {
      final decoded = jsonDecode(await indexFile.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on FormatException {
      return [];
    } on FileSystemException {
      return [];
    }
  }

  static Future<void> _writeIndex(
    String projectPath,
    List<Map<String, dynamic>> index,
  ) async {
    final root = Directory(_checkpointsRoot(projectPath));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final indexFile = File(_join(root.path, _indexFileName));
    const encoder = JsonEncoder.withIndent('  ');
    await indexFile.writeAsString(encoder.convert(index));
  }

  static Future<void> _upsertIndex(
    String projectPath,
    ChatCheckpoint checkpoint,
  ) async {
    final index = await _readIndex(projectPath);
    index.removeWhere((e) => e['checkpointId'] == checkpoint.checkpointId);
    index.insert(0, {
      'checkpointId': checkpoint.checkpointId,
      'label': checkpoint.label,
      'timestamp': checkpoint.timestamp.toIso8601String(),
      'messageId': checkpoint.messageId,
      'fileCount': checkpoint.files.length,
      'restored': checkpoint.restored,
    });
    await _writeIndex(projectPath, index);
  }

  static Future<void> _removeFromIndex(
    String projectPath,
    String checkpointId,
  ) async {
    final index = await _readIndex(projectPath);
    index.removeWhere((e) => e['checkpointId'] == checkpointId);
    await _writeIndex(projectPath, index);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _generateCheckpointId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'cp_${ms}_$rand';
  }

  static List<String> _dedupePaths(List<String> paths) {
    final seen = <String>{};
    final result = <String>[];
    for (final p in paths) {
      final trimmed = p.trim();
      if (trimmed.isEmpty) continue;
      final key = _normalizePath(trimmed);
      if (seen.add(key)) result.add(trimmed);
    }
    return result;
  }

  static String _resolveAbsolute(String filePath, String projectPath) {
    final normalized = filePath.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        (normalized.length > 2 && normalized[1] == ':')) {
      return _normalizePath(normalized);
    }
    return _join(projectPath, normalized);
  }

  static String _encodeRelativePath(String relative) {
    final safe = relative
        .replaceAll('\\', '/')
        .replaceAll('..', '__')
        .replaceAll('/', '__');
    return '$safe.snapshot';
  }

  static String _checksum(String content) => content.hashCode.toString();

  static Future<void> _removeEmptyParents(
    String filePath,
    String projectPath,
  ) async {
    var dir = File(filePath).parent;
    final root = _normalizePath(projectPath);
    while (true) {
      final normalized = _normalizePath(dir.path);
      if (normalized == root || !normalized.startsWith('$root/')) break;
      try {
        final children = await dir.list().toList();
        if (children.isNotEmpty) break;
        await dir.delete();
        dir = dir.parent;
      } catch (_) {
        break;
      }
    }
  }

  static String _normalizePath(String p) {
    var result = p.replaceAll('\\', '/');
    while (result.endsWith('/') && result.length > 1) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static String _join(String base, String a, [String? b, String? c]) {
    final parts = <String>[
      _normalizePath(base),
      a.replaceAll('\\', '/'),
      if (b != null) b.replaceAll('\\', '/'),
      if (c != null) c.replaceAll('\\', '/'),
    ];
    return parts
        .map((p) => p.startsWith('/') && p != parts.first
            ? p.substring(1)
            : p)
        .where((p) => p.isNotEmpty)
        .join('/');
  }

  static String _toRelative(String absolute, String root) {
    final abs = _normalizePath(absolute);
    final base = _normalizePath(root);
    if (abs == base) return '';
    if (abs.startsWith('$base/')) return abs.substring(base.length + 1);
    return abs;
  }
}
