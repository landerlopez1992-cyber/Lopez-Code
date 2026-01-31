import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class ProjectService {
  static const String _projectPathKey = 'current_project_path';

  // Guardar ruta del proyecto actual
  static Future<void> saveProjectPath(String path) async {
    print('💾 ProjectService.saveProjectPath: Guardando path: $path');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_projectPathKey, path);
    print('✅ ProjectService.saveProjectPath: Path guardado exitosamente');
    
    // Verificar inmediatamente que se guardó
    final verification = prefs.getString(_projectPathKey);
    print('🔍 ProjectService.saveProjectPath: Verificación - path guardado: $verification');
  }

  // Obtener ruta del proyecto actual
  static Future<String?> getProjectPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_projectPathKey);
    print('📖 ProjectService.getProjectPath: Path leído: $path');
    return path;
  }

  // Verificar si hay un proyecto seleccionado
  static Future<bool> hasProject() async {
    final path = await getProjectPath();
    if (path == null || path.isEmpty) return false;
    
    final dir = Directory(path);
    return await dir.exists();
  }

  // Verificar si una ruta es un proyecto Flutter válido
  static Future<bool> isFlutterProject(String path) async {
    if (path.isEmpty) return false;
    
    final dir = Directory(path);
    if (!await dir.exists()) return false;
    
    final pubspecFile = File('$path/pubspec.yaml');
    return await pubspecFile.exists();
  }

  // Obtener el nombre del proyecto desde pubspec.yaml
  static Future<String?> getProjectName(String path) async {
    if (path.isEmpty) return null;
    
    final pubspecFile = File('$path/pubspec.yaml');
    if (!await pubspecFile.exists()) return null;
    
    try {
      final content = await pubspecFile.readAsString();
      final nameMatch = RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(content);
      return nameMatch?.group(1)?.trim();
    } catch (e) {
      print('⚠️ Error al leer nombre del proyecto: $e');
      return null;
    }
  }

  // Verificar si una ruta está dentro del proyecto
  static Future<bool> isPathInProject(String filePath) async {
    final projectPath = await getProjectPath();
    if (projectPath == null) return false;
    
    final projectDir = Directory(projectPath);
    final file = File(filePath);
    
    // Normalizar rutas
    final normalizedProject = projectDir.absolute.path;
    final normalizedFile = file.absolute.path;
    
    return normalizedFile.startsWith(normalizedProject);
  }

  // Obtener ruta relativa desde el proyecto
  static Future<String?> getRelativePath(String absolutePath) async {
    final projectPath = await getProjectPath();
    if (projectPath == null) return null;
    
    final projectDir = Directory(projectPath);
    final file = File(absolutePath);
    
    final projectAbsolute = projectDir.absolute.path;
    final fileAbsolute = file.absolute.path;
    
    if (fileAbsolute.startsWith(projectAbsolute)) {
      return fileAbsolute.substring(projectAbsolute.length + 1);
    }
    
    return null;
  }

  // Listar todos los archivos del proyecto
  static Future<List<FileSystemEntity>> listProjectFiles() async {
    final projectPath = await getProjectPath();
    if (projectPath == null) return [];
    
    final dir = Directory(projectPath);
    if (!await dir.exists()) return [];
    
    try {
      return await dir.list(recursive: true).toList();
    } catch (e) {
      return [];
    }
  }

  // Obtener estructura de directorios del proyecto
  static Future<Map<String, dynamic>> getProjectStructure() async {
    final projectPath = await getProjectPath();
    if (projectPath == null) return {};
    
    // Normalizar el path - eliminar barra final si existe
    final normalizedPath = projectPath.endsWith('/') 
        ? projectPath.substring(0, projectPath.length - 1)
        : projectPath;
    
    final dir = Directory(normalizedPath);
    if (!await dir.exists()) {
      print('❌ El directorio del proyecto no existe: $normalizedPath');
      return {};
    }
    
    print('📂 Construyendo estructura para: $normalizedPath');
    return await _buildDirectoryTree(dir, normalizedPath);
  }

  static Future<Map<String, dynamic>> _buildDirectoryTree(
    Directory dir,
    String rootPath,
  ) async {
    final Map<String, dynamic> tree = {
      'name': dir.path == rootPath ? 'root' : dir.path.split('/').last,
      'path': dir.path,
      'type': 'directory',
      'children': <Map<String, dynamic>>[],
    };

    try {
      print('📂 Construyendo árbol para: ${dir.path}');
      
      // Verificar permisos antes de listar
      if (!await dir.exists()) {
        print('❌ El directorio no existe: ${dir.path}');
        return tree;
      }
      
      // Intentar listar con manejo de errores de permisos
      List<FileSystemEntity> entities;
      try {
        entities = await dir.list().toList();
      } on PathAccessException catch (e) {
        print('❌ Error de permisos al listar ${dir.path}: $e');
        print('💡 Solución: Ve a Preferencias del Sistema > Seguridad y Privacidad > Archivos y Carpetas');
        print('💡 Asegúrate de que "Lopez Code" tenga acceso a la carpeta del proyecto');
        return tree; // Retornar árbol vacío si no hay permisos
      } catch (e) {
        print('❌ Error al listar directorio ${dir.path}: $e');
        return tree;
      }
      
      print('📂 Encontrados ${entities.length} elementos en ${dir.path}');
      
      for (var entity in entities) {
        try {
          if (entity is Directory) {
            // Ignorar carpetas ocultas y comunes que no queremos mostrar
            final name = entity.path.split('/').last;
            if (!name.startsWith('.') && 
                name != 'node_modules' && 
                name != 'build' &&
                name != '.dart_tool') {
              final childTree = await _buildDirectoryTree(entity, rootPath);
              tree['children'].add(childTree);
              print('📁 Agregado directorio: $name');
            }
          } else if (entity is File) {
            final name = entity.path.split('/').last;
            if (!name.startsWith('.')) {
              tree['children'].add({
                'name': name,
                'path': entity.path,
                'type': 'file',
                'size': await entity.length(),
              });
              print('📄 Agregado archivo: $name');
            }
          }
        } catch (e) {
          print('⚠️ Error al procesar ${entity.path}: $e');
          // Continuar con el siguiente elemento
        }
      }
    } catch (e) {
      print('❌ Error al listar directorio ${dir.path}: $e');
      // Ignorar errores de acceso pero loguearlos
    }

    // Ordenar: directorios primero, luego archivos
    (tree['children'] as List).sort((a, b) {
      if (a['type'] == 'directory' && b['type'] != 'directory') return -1;
      if (a['type'] != 'directory' && b['type'] == 'directory') return 1;
      return a['name'].toString().toLowerCase().compareTo(
        b['name'].toString().toLowerCase(),
      );
    });

    return tree;
  }
}


