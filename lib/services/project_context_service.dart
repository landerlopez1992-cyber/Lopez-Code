import 'dart:io';
import 'package:path/path.dart' as path;
import 'project_service.dart';

class ProjectContextService {
  // Obtener contexto del proyecto para enviar a la IA
  static Future<String> getProjectContext({
    int maxFiles = 5, // Reducido de 20 a 5 archivos para evitar tokens excesivos
    int maxFileSize = 10000, // Reducido de 50KB a 10KB por archivo
  }) async {
    final projectPath = await ProjectService.getProjectPath();
    if (projectPath == null) {
      return 'No hay proyecto seleccionado.';
    }

    final projectDir = Directory(projectPath);
    if (!await projectDir.exists()) {
      return 'El proyecto seleccionado no existe.';
    }

    final context = StringBuffer();
    context.writeln('=== ESTRUCTURA DEL PROYECTO ===');
    context.writeln('Ruta del proyecto: $projectPath');
    context.writeln('Nombre del proyecto: ${path.basename(projectPath)}');
    context.writeln('');

    // Obtener estructura de directorios
    final structure = await ProjectService.getProjectStructure();
    context.writeln('=== ESTRUCTURA DE DIRECTORIOS ===');
    context.writeln(_formatStructure(structure, 0));
    context.writeln('');

    // Obtener contenido de archivos importantes
    context.writeln('=== CONTENIDO DE ARCHIVOS PRINCIPALES ===');
    final importantFiles = await _getImportantFiles(projectDir, maxFiles, maxFileSize);
    
    for (var fileInfo in importantFiles) {
      context.writeln('\n--- ${fileInfo['path']} ---');
      context.writeln(fileInfo['content']);
    }

    return context.toString();
  }

  static String _formatStructure(Map<String, dynamic> node, int indent) {
    final buffer = StringBuffer();
    final indentStr = '  ' * indent;
    final name = node['name'] as String;
    final type = node['type'] as String;
    
    if (type == 'directory') {
      buffer.writeln('$indentStr📁 $name/');
      final children = node['children'] as List<dynamic>?;
      if (children != null) {
        for (var child in children) {
          buffer.write(_formatStructure(child as Map<String, dynamic>, indent + 1));
        }
      }
    } else {
      buffer.writeln('$indentStr📄 $name');
    }
    
    return buffer.toString();
  }

  static Future<List<Map<String, String>>> _getImportantFiles(
    Directory projectDir,
    int maxFiles,
    int maxFileSize,
  ) async {
    final importantExtensions = [
      '.dart', '.js', '.ts', '.jsx', '.tsx', '.py', '.java', '.kt',
      '.html', '.css', '.json', '.yaml', '.yml', '.md', '.xml',
      '.pubspec.yaml', '.package.json', '.README.md',
    ];

    final importantFiles = <Map<String, String>>[];
    final projectPath = projectDir.path;

    try {
      await for (var entity in projectDir.list(recursive: true)) {
        if (importantFiles.length >= maxFiles) break;
        
        if (entity is File) {
          final fileName = path.basename(entity.path);
          final extension = path.extension(entity.path).toLowerCase();
          final relativePath = path.relative(entity.path, from: projectPath);
          
          // Ignorar archivos ocultos y carpetas comunes
          if (fileName.startsWith('.') || 
              relativePath.contains('node_modules') ||
              relativePath.contains('.dart_tool') ||
              relativePath.contains('build')) {
            continue;
          }

          // Solo archivos importantes o pequeños
          if (importantExtensions.contains(extension) || 
              await entity.length() < maxFileSize) {
            try {
              final content = await entity.readAsString();
              if (content.length > maxFileSize) {
                importantFiles.add({
                  'path': relativePath,
                  'content': '${content.substring(0, maxFileSize)}...\n[Archivo truncado - muy grande]',
                });
              } else {
                importantFiles.add({
                  'path': relativePath,
                  'content': content,
                });
              }
            } catch (e) {
              // Ignorar archivos que no se pueden leer
            }
          }
        }
      }
    } catch (e) {
      // Ignorar errores
    }

    return importantFiles;
  }

  // Obtener resumen del proyecto
  static Future<String> getProjectSummary() async {
    final projectPath = await ProjectService.getProjectPath();
    if (projectPath == null) return '';

    final projectDir = Directory(projectPath);
    if (!await projectDir.exists()) return '';

    final summary = StringBuffer();
    summary.writeln('Proyecto: ${path.basename(projectPath)}');
    summary.writeln('Ruta: $projectPath');
    
    // Contar archivos
    int fileCount = 0;
    int dirCount = 0;
    try {
      await for (var entity in projectDir.list(recursive: true)) {
        if (entity is File) {
          fileCount++;
        } else if (entity is Directory) {
          dirCount++;
        }
      }
    } catch (e) {
      // Ignorar errores
    }
    
    summary.writeln('Archivos: $fileCount, Directorios: $dirCount');
    
    return summary.toString();
  }
}


