import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

class FileService {
  // Extensiones de archivos binarios que no deben leerse como texto
  static const Set<String> _binaryExtensions = {
    'tgz', 'gz', 'zip', 'tar', 'rar', '7z',
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'ico', 'svg', 'webp',
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
    'mp3', 'mp4', 'avi', 'mov', 'wmv', 'flv',
    'exe', 'dmg', 'pkg', 'deb', 'rpm',
    'so', 'dylib', 'dll', 'a', 'lib',
    'class', 'jar', 'war', 'ear',
    'o', 'obj', 'bin',
  };

  // Verificar si un archivo es binario basándose en su extensión
  static bool _isBinaryFile(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    return _binaryExtensions.contains(extension);
  }

  // Leer contenido de un archivo
  static Future<String> readFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('El archivo no existe: $filePath');
      }

      // Verificar si es un archivo binario
      if (_isBinaryFile(filePath)) {
        final fileName = filePath.split('/').last;
        throw Exception(
          'Este archivo es binario y no puede mostrarse como texto.\n'
          'Archivo: $fileName\n'
          'Tipo: ${filePath.split('.').last.toUpperCase()}\n\n'
          'Los archivos binarios (imágenes, comprimidos, ejecutables, etc.) '
          'no pueden editarse como texto.'
        );
      }

      // Intentar leer como texto
      try {
        return await file.readAsString();
      } on FormatException catch (e) {
        // Si falla la decodificación UTF-8, es probablemente binario
        throw Exception(
          'No se puede leer este archivo como texto.\n'
          'El archivo parece ser binario o usar una codificación diferente a UTF-8.\n\n'
          'Error: ${e.message}'
        );
      }
    } catch (e) {
      if (e.toString().contains('binario') || e.toString().contains('UTF-8')) {
        rethrow; // Re-lanzar errores de archivos binarios sin modificar
      }
      throw Exception('Error al leer archivo: $e');
    }
  }

  // Escribir contenido a un archivo
  static Future<void> writeFile(String filePath, String content) async {
    try {
      final file = File(filePath);
      await file.writeAsString(content);
    } catch (e) {
      throw Exception('Error al escribir archivo: $e');
    }
  }

  // Seleccionar un archivo usando el diálogo del sistema
  static Future<String?> pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        return result.files.single.path;
      }
      return null;
    } catch (e) {
      throw Exception('Error al seleccionar archivo: $e');
    }
  }

  // Seleccionar múltiples archivos
  static Future<List<String>> pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );

      if (result != null) {
        return result.paths
            .where((path) => path != null)
            .cast<String>()
            .toList();
      }
      return [];
    } catch (e) {
      throw Exception('Error al seleccionar archivos: $e');
    }
  }

  // Verificar si un archivo existe
  static Future<bool> fileExists(String filePath) async {
    final file = File(filePath);
    return await file.exists();
  }

  // Obtener el directorio de documentos
  static Future<String> getDocumentsDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  // Directorios y archivos a excluir de la búsqueda
  static const Set<String> _excludedPaths = {
    '.dart_tool',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
    'build',
    '.build',
    'node_modules',
    '.git',
    '.idea',
    '.vscode',
    '.DS_Store',
    '.dSYM',
    'Pods',
    'DerivedData',
  };

  // Verificar si una ruta debe ser excluida
  static bool _shouldExcludePath(String path) {
    final pathLower = path.toLowerCase();
    for (final excluded in _excludedPaths) {
      if (pathLower.contains(excluded.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  // Buscar archivos por nombre en un directorio
  static Future<List<String>> searchFiles(String directoryPath, String query) async {
    final results = <String>[];
    final queryLower = query.toLowerCase();
    
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        return results;
      }

      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          // Excluir archivos binarios y rutas no deseadas
          if (_shouldExcludePath(entity.path) || _isBinaryFile(entity.path)) {
            continue;
          }
          
          final fileName = entity.path.split('/').last.toLowerCase();
          if (fileName.contains(queryLower)) {
            results.add(entity.path);
          }
        }
      }
    } catch (e) {
      print('❌ Error al buscar archivos: $e');
    }

    // Ordenar resultados: primero los que empiezan con la query
    results.sort((a, b) {
      final aName = a.split('/').last.toLowerCase();
      final bName = b.split('/').last.toLowerCase();
      final aStarts = aName.startsWith(queryLower);
      final bStarts = bName.startsWith(queryLower);
      
      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;
      return aName.compareTo(bName);
    });

    return results;
  }
}


