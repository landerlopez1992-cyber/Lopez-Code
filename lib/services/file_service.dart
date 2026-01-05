import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

class FileService {
  // Leer contenido de un archivo
  static Future<String> readFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsString();
      } else {
        throw Exception('El archivo no existe: $filePath');
      }
    } catch (e) {
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
}


