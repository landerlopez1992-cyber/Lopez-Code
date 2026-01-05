import 'dart:io';
import 'project_service.dart';

class CodeEditorService {
  // Extraer código de bloques de código en la respuesta de la IA
  static Map<String, String> extractCodeBlocks(String response) {
    final Map<String, String> codeBlocks = {};
    
    // Buscar bloques de código con formato ```language\ncode\n```
    final codeBlockRegex = RegExp(
      r'```(\w+)?\n([\s\S]*?)```',
      multiLine: true,
    );
    
    int blockIndex = 0;
    codeBlockRegex.allMatches(response).forEach((match) {
      final language = match.group(1) ?? 'text';
      final code = match.group(2) ?? '';
      codeBlocks['block_$blockIndex'] = code;
      codeBlocks['${blockIndex}_language'] = language;
      blockIndex++;
    });
    
    return codeBlocks;
  }

  // Detectar si el usuario quiere crear un archivo
  static bool wantsToCreateFile(String message) {
    final createKeywords = [
      'crea',
      'create',
      'crear',
      'haz',
      'make',
      'genera',
      'generate',
      'nuevo archivo',
      'new file',
      'archivo nuevo',
    ];
    
    final lowerMessage = message.toLowerCase();
    return createKeywords.any((keyword) => lowerMessage.contains(keyword));
  }

  // Detectar si el usuario quiere editar un archivo
  static bool wantsToEditFile(String message) {
    final editKeywords = [
      'edita',
      'edit',
      'modifica',
      'modify',
      'cambia',
      'change',
      'actualiza',
      'update',
      'corrige',
      'fix',
    ];
    
    final lowerMessage = message.toLowerCase();
    return editKeywords.any((keyword) => lowerMessage.contains(keyword));
  }

  // Extraer ruta de archivo del mensaje
  static String? extractFilePath(String message) {
    // Buscar rutas que empiecen con / o ~ o contengan .dart, .js, .html, etc.
    final pathRegex = RegExp(
      r'(?:^|\s)([/~]?[\w/.-]+\.(dart|js|ts|html|css|py|java|cpp|c|h|json|yaml|yml|md|txt|xml|swift|kt|go|rs|php|rb|sh|bash|zsh|fish))',
    );
    
    final match = pathRegex.firstMatch(message);
    if (match != null) {
      String filePath = match.group(1)!.trim();
      // Expandir ~ a home directory
      if (filePath.startsWith('~')) {
        filePath = filePath.replaceFirst('~', Platform.environment['HOME'] ?? '');
      }
      return filePath;
    }
    return null;
  }

  // Crear archivo con código
  static Future<String> createFile({
    required String filePath,
    required String content,
  }) async {
    try {
      // Verificar que el archivo está dentro del proyecto
      final isInProject = await ProjectService.isPathInProject(filePath);
      if (!isInProject) {
        throw Exception('El archivo debe estar dentro del proyecto seleccionado');
      }
      
      final file = File(filePath);
      
      // Crear directorios si no existen
      final directory = file.parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      // Escribir contenido
      await file.writeAsString(content);
      return 'Archivo creado exitosamente: $filePath';
    } catch (e) {
      throw Exception('Error al crear archivo: $e');
    }
  }

  // Editar archivo existente
  static Future<String> editFile({
    required String filePath,
    required String newContent,
  }) async {
    try {
      final file = File(filePath);
      
      if (!await file.exists()) {
        // Si no existe, crearlo
        return await createFile(filePath: filePath, content: newContent);
      }
      
      // Escribir nuevo contenido
      await file.writeAsString(newContent);
      return 'Archivo editado exitosamente: $filePath';
    } catch (e) {
      throw Exception('Error al editar archivo: $e');
    }
  }

  // Obtener directorio de trabajo actual
  static String getCurrentWorkingDirectory() {
    return Directory.current.path;
  }

  // Listar archivos en un directorio
  static Future<List<String>> listFiles(String directoryPath) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        return [];
      }
      
      final files = <String>[];
      await for (var entity in directory.list()) {
        if (entity is File) {
          files.add(entity.path);
        }
      }
      return files;
    } catch (e) {
      return [];
    }
  }

  // Crear directorio/carpeta
  static Future<String> createDirectory(String directoryPath) async {
    try {
      final isInProject = await ProjectService.isPathInProject(directoryPath);
      if (!isInProject) {
        throw Exception('El directorio debe estar dentro del proyecto seleccionado');
      }
      
      final directory = Directory(directoryPath);
      if (await directory.exists()) {
        throw Exception('El directorio ya existe: $directoryPath');
      }
      
      await directory.create(recursive: true);
      return 'Directorio creado exitosamente: $directoryPath';
    } catch (e) {
      throw Exception('Error al crear directorio: $e');
    }
  }

  // Crear nuevo proyecto Flutter
  static Future<String> createFlutterProject(String projectPath, String projectName) async {
    try {
      final fullPath = '$projectPath/$projectName';
      final directory = Directory(fullPath);
      
      if (await directory.exists()) {
        throw Exception('El proyecto ya existe: $fullPath');
      }
      
      // Crear directorio del proyecto
      await directory.create(recursive: true);
      
      // Ejecutar flutter create
      final process = await Process.run(
        'flutter',
        ['create', projectName],
        workingDirectory: projectPath,
      );
      
      if (process.exitCode != 0) {
        throw Exception('Error al crear proyecto Flutter: ${process.stderr}');
      }
      
      return 'Proyecto Flutter creado exitosamente: $fullPath';
    } catch (e) {
      throw Exception('Error al crear proyecto: $e');
    }
  }

  // Eliminar archivo o directorio
  static Future<String> deleteFileOrDirectory(String path) async {
    try {
      final isInProject = await ProjectService.isPathInProject(path);
      if (!isInProject) {
        throw Exception('El archivo/directorio debe estar dentro del proyecto seleccionado');
      }
      
      final entity = FileSystemEntity.typeSync(path);
      
      if (entity == FileSystemEntityType.file) {
        final file = File(path);
        await file.delete();
        return 'Archivo eliminado: $path';
      } else if (entity == FileSystemEntityType.directory) {
        final directory = Directory(path);
        await directory.delete(recursive: true);
        return 'Directorio eliminado: $path';
      } else {
        throw Exception('No se encontró el archivo o directorio: $path');
      }
    } catch (e) {
      throw Exception('Error al eliminar: $e');
    }
  }
}

