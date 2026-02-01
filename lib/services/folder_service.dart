import 'dart:io';

/// Servicio para gestionar carpetas/directorios
class FolderService {
  /// Crea un directorio de forma recursiva
  static Future<bool> createDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        print('✅ Directorio creado: $path');
        return true;
      } else {
        print('ℹ️ Directorio ya existe: $path');
        return true;
      }
    } catch (e) {
      print('❌ Error creando directorio: $e');
      return false;
    }
  }
  
  /// Verifica si un directorio existe
  static Future<bool> directoryExists(String path) async {
    try {
      final dir = Directory(path);
      return await dir.exists();
    } catch (e) {
      return false;
    }
  }
  
  /// Elimina un directorio (requiere confirmación)
  static Future<bool> deleteDirectory(String path, {bool recursive = false}) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: recursive);
        print('✅ Directorio eliminado: $path');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error eliminando directorio: $e');
      return false;
    }
  }
}
