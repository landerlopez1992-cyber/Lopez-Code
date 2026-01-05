import 'dart:io';

/// Servicio alternativo para seleccionar directorios usando diálogo nativo de macOS
class NativeFilePicker {
  /// Abre un diálogo nativo de macOS para seleccionar un directorio
  /// Retorna null si el usuario cancela o si hay un error
  static Future<String?> selectDirectory() async {
    try {
      print('Ejecutando osascript para abrir diálogo...');
      
      // Método más simple: usar solo choose folder sin activar ninguna aplicación
      // Este es el método más confiable en macOS
      final result = await Process.run(
        'osascript',
        [
          '-e',
          'POSIX path of (choose folder with prompt "Selecciona el directorio del proyecto")',
        ],
        runInShell: false,
      );

      print('osascript exit code: ${result.exitCode}');
      print('osascript stdout: ${result.stdout}');
      print('osascript stderr: ${result.stderr}');

      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim();
        if (path.isNotEmpty && path != 'null' && path != '') {
          print('Directorio seleccionado: $path');
          return path;
        }
      }
      
      // Exit code 1 generalmente significa que el usuario canceló
      if (result.exitCode == 1) {
        print('Usuario canceló la selección');
        return null;
      }
      
      // Si hay otro error, intentar método alternativo
      print('Error inesperado, intentando método alternativo...');
      return await _selectDirectoryAlternative();
    } catch (e, stackTrace) {
      print('Error al usar diálogo nativo: $e');
      print('Stack trace: $stackTrace');
      // Intentar método alternativo
      return await _selectDirectoryAlternative();
    }
  }

  /// Método alternativo usando un script de archivo temporal
  static Future<String?> _selectDirectoryAlternative() async {
    try {
      print('Intentando método alternativo con script temporal...');
      
      // Crear un script temporal más robusto
      final script = '''
        try
          set folderPath to choose folder with prompt "Selecciona el directorio del proyecto"
          return POSIX path of folderPath
        on error number -128
          -- Usuario canceló
          return ""
        end try
      ''';
      
      final result = await Process.run(
        'osascript',
        ['-e', script],
        runInShell: false,
      );

      print('Método alternativo exit code: ${result.exitCode}');
      print('Método alternativo stdout: ${result.stdout}');
      print('Método alternativo stderr: ${result.stderr}');

      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim();
        if (path.isNotEmpty && path != 'null' && path != '') {
          print('Directorio seleccionado (método alternativo): $path');
          return path;
        }
      }
      
      return null;
    } catch (e) {
      print('Método alternativo también falló: $e');
      return null;
    }
  }
}

