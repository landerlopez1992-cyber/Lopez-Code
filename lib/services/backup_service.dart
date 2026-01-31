import 'dart:io';
import 'dart:convert';

/// Servicio de backup y rollback automático
/// Guarda copias de seguridad de archivos antes de modificarlos
/// para permitir revertir cambios si algo sale mal.

class BackupService {
  static const String _backupDirName = '.lopez_code_backups';
  static const int _maxBackupsPerFile = 10; // Máximo de backups por archivo

  /// Obtiene el directorio de backups para un proyecto
  static Future<Directory> _getBackupDirectory(String projectPath) async {
    final backupPath = '$projectPath/$_backupDirName';
    final backupDir = Directory(backupPath);
    
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    
    return backupDir;
  }

  /// Crea un backup de un archivo antes de modificarlo
  static Future<BackupInfo?> createBackup(String filePath, String projectPath) async {
    try {
      final file = File(filePath);
      
      // Verificar que el archivo existe
      if (!await file.exists()) {
        print('⚠️ No se puede hacer backup: el archivo no existe: $filePath');
        return null;
      }

      // Leer contenido actual
      final content = await file.readAsString();
      
      // Obtener directorio de backups
      final backupDir = await _getBackupDirectory(projectPath);
      
      // Generar nombre único para el backup
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final relativePath = filePath.replaceFirst(projectPath, '').replaceAll('/', '_');
      final backupFileName = '${relativePath}_$timestamp.backup';
      final backupFilePath = '${backupDir.path}/$backupFileName';
      
      // Crear archivo de backup
      final backupFile = File(backupFilePath);
      await backupFile.writeAsString(content);
      
      // Crear metadata del backup
      final metadata = BackupMetadata(
        originalPath: filePath,
        backupPath: backupFilePath,
        timestamp: DateTime.now(),
        fileSize: content.length,
        checksum: _calculateChecksum(content),
      );
      
      // Guardar metadata
      final metadataPath = '$backupFilePath.meta';
      await File(metadataPath).writeAsString(jsonEncode(metadata.toJson()));
      
      print('✅ Backup creado: $backupFileName');
      
      // Limpiar backups antiguos
      await _cleanOldBackups(filePath, projectPath);
      
      return BackupInfo(
        backupPath: backupFilePath,
        metadata: metadata,
      );
    } catch (e) {
      print('❌ Error al crear backup: $e');
      return null;
    }
  }

  /// Restaura un archivo desde un backup
  static Future<bool> restoreBackup(String backupPath) async {
    try {
      // Leer metadata
      final metadataPath = '$backupPath.meta';
      final metadataFile = File(metadataPath);
      
      if (!await metadataFile.exists()) {
        print('❌ No se encontró metadata del backup');
        return false;
      }
      
      final metadataJson = jsonDecode(await metadataFile.readAsString());
      final metadata = BackupMetadata.fromJson(metadataJson);
      
      // Leer contenido del backup
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        print('❌ No se encontró el archivo de backup');
        return false;
      }
      
      final backupContent = await backupFile.readAsString();
      
      // Verificar checksum
      final currentChecksum = _calculateChecksum(backupContent);
      if (currentChecksum != metadata.checksum) {
        print('⚠️ Advertencia: el checksum del backup no coincide (posible corrupción)');
      }
      
      // Restaurar archivo original
      final originalFile = File(metadata.originalPath);
      
      // Crear backup del estado actual antes de restaurar (por si acaso)
      if (await originalFile.exists()) {
        final currentContent = await originalFile.readAsString();
        final tempBackupPath = '${backupPath}_temp_before_restore';
        await File(tempBackupPath).writeAsString(currentContent);
        print('💾 Backup temporal creado antes de restaurar: $tempBackupPath');
      }
      
      // Restaurar contenido
      await originalFile.writeAsString(backupContent);
      
      print('✅ Archivo restaurado desde backup: ${metadata.originalPath}');
      return true;
    } catch (e) {
      print('❌ Error al restaurar backup: $e');
      return false;
    }
  }

  /// Obtiene la lista de backups disponibles para un archivo
  static Future<List<BackupInfo>> getBackupsForFile(String filePath, String projectPath) async {
    try {
      final backupDir = await _getBackupDirectory(projectPath);
      final relativePath = filePath.replaceFirst(projectPath, '').replaceAll('/', '_');
      
      final backups = <BackupInfo>[];
      
      // Listar todos los archivos de backup
      await for (var entity in backupDir.list()) {
        if (entity is File && 
            entity.path.endsWith('.backup') && 
            entity.path.contains(relativePath)) {
          
          // Leer metadata
          final metadataPath = '${entity.path}.meta';
          final metadataFile = File(metadataPath);
          
          if (await metadataFile.exists()) {
            final metadataJson = jsonDecode(await metadataFile.readAsString());
            final metadata = BackupMetadata.fromJson(metadataJson);
            
            backups.add(BackupInfo(
              backupPath: entity.path,
              metadata: metadata,
            ));
          }
        }
      }
      
      // Ordenar por timestamp (más reciente primero)
      backups.sort((a, b) => b.metadata.timestamp.compareTo(a.metadata.timestamp));
      
      return backups;
    } catch (e) {
      print('❌ Error al obtener backups: $e');
      return [];
    }
  }

  /// Limpia backups antiguos manteniendo solo los más recientes
  static Future<void> _cleanOldBackups(String filePath, String projectPath) async {
    try {
      final backups = await getBackupsForFile(filePath, projectPath);
      
      if (backups.length > _maxBackupsPerFile) {
        // Eliminar los backups más antiguos
        final backupsToDelete = backups.skip(_maxBackupsPerFile);
        
        for (var backup in backupsToDelete) {
          final backupFile = File(backup.backupPath);
          final metadataFile = File('${backup.backupPath}.meta');
          
          if (await backupFile.exists()) {
            await backupFile.delete();
          }
          
          if (await metadataFile.exists()) {
            await metadataFile.delete();
          }
          
          print('🗑️ Backup antiguo eliminado: ${backup.backupPath}');
        }
      }
    } catch (e) {
      print('⚠️ Error al limpiar backups antiguos: $e');
    }
  }

  /// Elimina todos los backups de un proyecto
  static Future<void> clearAllBackups(String projectPath) async {
    try {
      final backupDir = await _getBackupDirectory(projectPath);
      
      if (await backupDir.exists()) {
        await backupDir.delete(recursive: true);
        print('✅ Todos los backups eliminados');
      }
    } catch (e) {
      print('❌ Error al eliminar backups: $e');
    }
  }

  /// Obtiene el tamaño total de los backups
  static Future<int> getBackupSize(String projectPath) async {
    try {
      final backupDir = await _getBackupDirectory(projectPath);
      int totalSize = 0;
      
      await for (var entity in backupDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      
      return totalSize;
    } catch (e) {
      print('❌ Error al calcular tamaño de backups: $e');
      return 0;
    }
  }

  /// Calcula un checksum simple del contenido
  static String _calculateChecksum(String content) {
    // Checksum simple basado en hash del contenido
    return content.hashCode.toString();
  }

  /// Obtiene información resumida de backups
  static Future<BackupSummary> getBackupSummary(String projectPath) async {
    try {
      final backupDir = await _getBackupDirectory(projectPath);
      int fileCount = 0;
      int totalSize = 0;
      DateTime? oldestBackup;
      DateTime? newestBackup;
      
      await for (var entity in backupDir.list()) {
        if (entity is File && entity.path.endsWith('.backup')) {
          fileCount++;
          totalSize += await entity.length();
          
          // Leer metadata para obtener timestamp
          final metadataPath = '${entity.path}.meta';
          final metadataFile = File(metadataPath);
          
          if (await metadataFile.exists()) {
            final metadataJson = jsonDecode(await metadataFile.readAsString());
            final metadata = BackupMetadata.fromJson(metadataJson);
            
            if (oldestBackup == null || metadata.timestamp.isBefore(oldestBackup)) {
              oldestBackup = metadata.timestamp;
            }
            
            if (newestBackup == null || metadata.timestamp.isAfter(newestBackup)) {
              newestBackup = metadata.timestamp;
            }
          }
        }
      }
      
      return BackupSummary(
        totalBackups: fileCount,
        totalSize: totalSize,
        oldestBackup: oldestBackup,
        newestBackup: newestBackup,
      );
    } catch (e) {
      print('❌ Error al obtener resumen de backups: $e');
      return BackupSummary(
        totalBackups: 0,
        totalSize: 0,
      );
    }
  }
}

/// Información de un backup
class BackupInfo {
  final String backupPath;
  final BackupMetadata metadata;

  BackupInfo({
    required this.backupPath,
    required this.metadata,
  });
}

/// Metadata de un backup
class BackupMetadata {
  final String originalPath;
  final String backupPath;
  final DateTime timestamp;
  final int fileSize;
  final String checksum;

  BackupMetadata({
    required this.originalPath,
    required this.backupPath,
    required this.timestamp,
    required this.fileSize,
    required this.checksum,
  });

  Map<String, dynamic> toJson() {
    return {
      'originalPath': originalPath,
      'backupPath': backupPath,
      'timestamp': timestamp.toIso8601String(),
      'fileSize': fileSize,
      'checksum': checksum,
    };
  }

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    return BackupMetadata(
      originalPath: json['originalPath'],
      backupPath: json['backupPath'],
      timestamp: DateTime.parse(json['timestamp']),
      fileSize: json['fileSize'],
      checksum: json['checksum'],
    );
  }
}

/// Resumen de backups
class BackupSummary {
  final int totalBackups;
  final int totalSize;
  final DateTime? oldestBackup;
  final DateTime? newestBackup;

  BackupSummary({
    required this.totalBackups,
    required this.totalSize,
    this.oldestBackup,
    this.newestBackup,
  });

  String get formattedSize {
    if (totalSize < 1024) {
      return '$totalSize B';
    } else if (totalSize < 1024 * 1024) {
      return '${(totalSize / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }
}
