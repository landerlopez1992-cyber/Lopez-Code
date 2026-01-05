import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'project_service.dart';

class RunDebugService {
  static Process? _currentProcess;
  static bool _isRunning = false;
  static String? _currentOutput;

  // Ejecutar el proyecto Flutter
  static Future<Map<String, dynamic>> runFlutterProject({
    String? mode = 'debug',
    String? platform = 'macos', // 'macos', 'ios', 'android', 'web'
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

      // Construir comando según plataforma
      final List<String> args = ['run'];
      
      // Agregar flag de dispositivo según plataforma
      if (platform != null) {
        args.add('-d');
        args.add(platform);
      }
      
      // Agregar modo (debug es por defecto, solo agregar si es release o profile)
      if (mode == 'release') {
        args.add('--release');
      } else if (mode == 'profile') {
        args.add('--profile');
      }

      print('🚀 Ejecutando: flutter ${args.join(' ')}');
      _currentOutput = '🚀 Ejecutando: flutter ${args.join(' ')}\n';
      onOutput?.call(_currentOutput!);

      // Ejecutar flutter run
      _currentProcess = await Process.start(
        'flutter',
        args,
        workingDirectory: projectPath,
        mode: ProcessStartMode.normal,
      );

      // Leer stdout
      _currentProcess!.stdout.transform(utf8.decoder).listen((data) {
        _currentOutput = (_currentOutput ?? '') + data;
        onOutput?.call(data);
      });

      // Leer stderr
      _currentProcess!.stderr.transform(utf8.decoder).listen((data) {
        _currentOutput = (_currentOutput ?? '') + data;
        onError?.call(data);
      });

      // Esperar a que termine (pero no bloquear)
      _currentProcess!.exitCode.then((exitCode) {
        _isRunning = false;
        _currentProcess = null;
        onOutput?.call('\n\n✅ Proceso terminado con código: $exitCode\n');
      });

      return {
        'success': true,
        'exitCode': 0,
        'output': _currentOutput ?? '',
      };
    } catch (e) {
      _isRunning = false;
      _currentProcess = null;
      _currentOutput = (_currentOutput ?? '') + '❌ Error: $e\n';
      onError?.call('❌ Error: $e\n');
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