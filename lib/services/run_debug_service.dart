import 'dart:io';
import 'dart:async';
import 'project_service.dart';

class RunDebugService {
  static Process? _currentProcess;
  static bool _isRunning = false;
  static String? _currentOutput;

  // Ejecutar el proyecto Flutter
  static Future<Map<String, dynamic>> runFlutterProject({
    String? mode = 'debug',
    Function(String)? onOutput,
    Function(String)? onError,
  }) async {
    final projectPath = await ProjectService.getProjectPath();
    if (projectPath == null) {
      throw Exception('No hay proyecto seleccionado');
    }

    if (_isRunning) {
      throw Exception('Ya hay un proceso en ejecución');
    }

    try {
      _isRunning = true;
      _currentOutput = '';

      // Ejecutar flutter run
      final process = await Process.start(
        'flutter',
        ['run', '-d', 'macos', mode == 'debug' ? '--debug' : '--release'],
        workingDirectory: projectPath,
        mode: ProcessStartMode.normal,
      );

      _currentProcess = process;

      // Leer stdout
      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        _currentOutput = (_currentOutput ?? '') + data;
        onOutput?.call(data);
      });

      // Leer stderr
      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        _currentOutput = (_currentOutput ?? '') + data;
        onError?.call(data);
      });

      // Esperar a que termine
      final exitCode = await process.exitCode;

      _isRunning = false;
      _currentProcess = null;

      return {
        'success': exitCode == 0,
        'exitCode': exitCode,
        'output': _currentOutput ?? '',
      };
    } catch (e) {
      _isRunning = false;
      _currentProcess = null;
      throw Exception('Error al ejecutar: $e');
    }
  }

  // Detener el proceso en ejecución
  static Future<void> stop() async {
    if (_currentProcess != null) {
      try {
        _currentProcess!.kill();
        await _currentProcess!.exitCode;
      } catch (e) {
        // Ignorar errores al detener
      }
      _currentProcess = null;
    }
    _isRunning = false;
  }

  // Verificar si hay un proceso ejecutándose
  static bool isRunning() {
    return _isRunning;
  }

  // Obtener output actual
  static String? getCurrentOutput() {
    return _currentOutput;
  }

  // Ejecutar comando específico
  static Future<Map<String, dynamic>> runCommand({
    required String command,
    List<String>? args,
    Function(String)? onOutput,
  }) async {
    final projectPath = await ProjectService.getProjectPath();
    if (projectPath == null) {
      throw Exception('No hay proyecto seleccionado');
    }

    try {
      final parts = command.split(' ');
      final executable = parts[0];
      final args = parts.length > 1 ? parts.sublist(1) : <String>[];

      final result = await Process.run(
        executable,
        args,
        workingDirectory: projectPath,
      );

      if (result.stdout != null) {
        onOutput?.call(result.stdout);
      }

      return {
        'success': result.exitCode == 0,
        'exitCode': result.exitCode,
        'output': result.stdout.toString(),
      };
    } catch (e) {
      throw Exception('Error al ejecutar comando: $e');
    }
  }

  // Verificar si Flutter está disponible
  static Future<bool> isFlutterAvailable() async {
    try {
      final result = await Process.run('flutter', ['--version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  // Obtener dispositivos disponibles
  static Future<List<Map<String, String>>> getAvailableDevices() async {
    try {
      final result = await Process.run('flutter', ['devices', '--machine']);
      if (result.exitCode == 0) {
        // Parsear JSON de dispositivos
        final devices = <Map<String, String>>[];
        // Por ahora retornar macOS como dispositivo por defecto
        devices.add({
          'id': 'macos',
          'name': 'macOS',
          'type': 'desktop',
        });
        return devices;
      }
    } catch (e) {
      // Ignorar errores
    }
    return [];
  }
}

