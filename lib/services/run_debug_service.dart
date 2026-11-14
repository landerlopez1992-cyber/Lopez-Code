import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'debug_console_service.dart';
import 'platform_service.dart';
import 'project_platform_support.dart';
import 'project_service.dart';

class RunDebugService {
  static Future<int> _findFreeWebPort({int preferred = 8085}) async {
    Future<bool> isFree(int port) async {
      try {
        final socket =
            await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await socket.close();
        return true;
      } catch (_) {
        return false;
      }
    }

    if (await isFree(preferred)) return preferred;
    for (var port = preferred + 1; port < preferred + 40; port++) {
      if (await isFree(port)) return port;
    }
    final ephemeral =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = ephemeral.port;
    await ephemeral.close();
    return port;
  }

  static void _notifyWebPreviewUrl(
    String url, {
    bool ready = true,
    String? platform,
  }) {
    try {
      final debug = DebugConsoleService();
      final p = (platform ?? PlatformService().selectedPlatform).toLowerCase();
      final isWeb = p == 'web';
      final label = ProjectPlatformSupport.humanLabel(p);
      debug.setRunning(true);
      debug.setAppUrl(url);
      if (ready) {
        debug.setCompilationProgress(
          1.0,
          isWeb ? 'Aplicación web ejecutándose' : '$label ejecutándose',
        );
        debug.addDebugConsole('🌐 Preview interno listo: $url');
      } else {
        debug.setCompilationProgress(
          0.35,
          isWeb ? 'Compilando Web Preview…' : 'Compilando $label…',
        );
        debug.addDebugConsole('🌐 Preview apuntando a $url (compilando…)');
      }
    } catch (e) {
      print('⚠️ No se pudo notificar URL de Preview: $e');
    }
  }

  static void _markRunStarted(String platform) {
    try {
      final debug = DebugConsoleService();
      debug.setRunning(true);
      // Limpia estado de error previo (pantalla roja del Preview).
      debug.setCompilationProgress(
        0.12,
        platform == 'web'
            ? 'Compilando Web Preview…'
            : 'Compilando para $platform…',
      );
      debug.addDebugConsole('🚀 Run iniciado · plataforma=$platform');
    } catch (_) {}
  }
  /// Referencia real del proceso `dart:io` Process de `flutter run`.
  static Process? _currentProcess;
  static bool _isRunning = false;
  static String? _currentOutput;
  static void Function()? _onProcessEnded;

  /// Callback para notificar a la UI que el proceso realmente terminó.
  static void setOnProcessEnded(void Function()? callback) {
    _onProcessEnded = callback;
  }

  static void _notifyProcessEnded() {
    _isRunning = false;
    _currentProcess = null;
    _onProcessEnded?.call();
  }

  // Ejecutar el proyecto Flutter
  static Future<Map<String, dynamic>> runFlutterProject({
    String? mode = 'debug',
    String? platform = 'macos', // 'macos', 'ios', 'android', 'web'
    Function(String)? onOutput,
    Function(String)? onError,
    void Function()? onProcessEnded,
  }) async {
    final projectPath = await ProjectService.getProjectPath();
    if (projectPath == null) {
      throw Exception('No hay proyecto seleccionado');
    }

    if (onProcessEnded != null) {
      _onProcessEnded = onProcessEnded;
    }

    // Detener proceso anterior si existe (evita zombies / cuelgues)
    if (_isRunning && _currentProcess != null) {
      print('⚠️ Deteniendo proceso anterior antes de iniciar uno nuevo...');
      await stop();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    try {
      _isRunning = true;
      _currentOutput = '';

      final List<String> args = ['run'];
      final plat = (platform ?? '').toLowerCase();
      final embeddedPreview = plat == 'web' ||
          plat == 'android' ||
          plat == 'ios'; // Preview embebido (marco teléfono)
      String? previewUrl;

      _markRunStarted(
        embeddedPreview
            ? (plat == 'web' ? 'web' : plat)
            : (platform ?? 'flutter'),
      );

      if (embeddedPreview) {
        // Preview interno: web-server → WebView (carcasa Android/iOS o monitor).
        final port = await _findFreeWebPort(preferred: 8085);
        previewUrl = 'http://127.0.0.1:$port';
        args.addAll([
          '-d',
          'web-server',
          '--web-hostname',
          '127.0.0.1',
          '--web-port',
          '$port',
        ]);
        _notifyWebPreviewUrl(previewUrl, ready: false, platform: plat);
      } else if (platform != null) {
        // Nativo: android_native → android device id, etc.
        final deviceTarget = plat.endsWith('_native')
            ? plat.replaceAll('_native', '')
            : plat;
        args.add('-d');
        args.add(deviceTarget);
      }

      if (mode == 'release') {
        args.add('--release');
      } else if (mode == 'profile') {
        args.add('--profile');
      }

      print('🚀 Ejecutando: flutter ${args.join(' ')}');
      _currentOutput = '🚀 Ejecutando: flutter ${args.join(' ')}\n';
      onOutput?.call(_currentOutput!);
      if (previewUrl != null) {
        onOutput?.call('🌐 Preview URL: $previewUrl\n');
      }

      final process = await Process.start(
        'flutter',
        args,
        workingDirectory: projectPath,
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
      _currentProcess = process;

      final stderrBuffer = StringBuffer();
      final startupCompleter = Completer<Map<String, dynamic>>();

      void completeOnce(Map<String, dynamic> payload) {
        if (!startupCompleter.isCompleted) {
          startupCompleter.complete(payload);
        }
      }

      void checkReadyAndCaptureUrl(String chunk) {
        final lower = chunk.toLowerCase();

        // Ignorar DevTools / Observatory al buscar URL de la app.
        final isDevToolsLine = lower.contains('devtools') ||
            lower.contains('vm service') ||
            lower.contains('observatory') ||
            lower.contains('debugger and profiler');

        if (embeddedPreview && !isDevToolsLine) {
          final served = RegExp(
            r'(?:is being served at|serving at|Serving at)\s*(https?://[^\s]+)',
            caseSensitive: false,
          ).firstMatch(chunk);
          if (served != null) {
            final url = served.group(1)!.trim();
            if (DebugConsoleService.isPreviewAppUrl(url)) {
              previewUrl = url;
              _notifyWebPreviewUrl(url, ready: true, platform: plat);
              completeOnce({
                'success': true,
                'exitCode': 0,
                'output': _currentOutput ?? '',
                'error': stderrBuffer.toString(),
                'pid': process.pid,
                'previewUrl': url,
              });
              return;
            }
          }

          final match = RegExp(
            r'https?://(?:localhost|127\.0\.0\.1):\d+',
            caseSensitive: false,
          ).firstMatch(chunk);
          if (match != null) {
            final url = match.group(0)!;
            if (DebugConsoleService.isPreviewAppUrl(url)) {
              previewUrl = url;
              _notifyWebPreviewUrl(url, ready: true, platform: plat);
            }
          }
        }

        // Señales post-compilación válidas en todas las plataformas
        // (Web, Android/iOS Preview y nativo macOS/Android/iOS).
        final isAppReady = lower.contains('flutter run key commands') ||
            lower.contains('to hot reload') ||
            lower.contains('an observatory debugger') ||
            lower.contains('dart vm service is listening') ||
            lower.contains('observatory listening') ||
            lower.contains('application finished launching') ||
            lower.contains('is being served at') ||
            lower.contains('serving at http');

        if (isAppReady) {
          if (embeddedPreview && previewUrl != null) {
            _notifyWebPreviewUrl(previewUrl!, ready: true, platform: plat);
          } else {
            try {
              DebugConsoleService().setCompilationProgress(
                1.0,
                'Aplicación ejecutándose',
              );
            } catch (_) {}
          }
          completeOnce({
            'success': true,
            'exitCode': 0,
            'output': _currentOutput ?? '',
            'error': stderrBuffer.toString(),
            'pid': process.pid,
            if (previewUrl != null) 'previewUrl': previewUrl,
          });
        }
      }

      void forwardProgress(String chunk) {
        try {
          DebugConsoleService().updateProgressFromFlutterLine(chunk);
        } catch (_) {}
        try {
          // Output = log crudo; Debug Console solo eventos/errores clave
          DebugConsoleService().ingestProcessChunk(chunk);
        } catch (_) {}
      }

      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();

      process.stdout.transform(utf8.decoder).listen(
        (data) {
          _currentOutput = (_currentOutput ?? '') + data;
          onOutput?.call(data);
          forwardProgress(data);
          checkReadyAndCaptureUrl(data);
        },
        onDone: () {
          if (!stdoutDone.isCompleted) stdoutDone.complete();
        },
        onError: (_) {
          if (!stdoutDone.isCompleted) stdoutDone.complete();
        },
      );

      process.stderr.transform(utf8.decoder).listen(
        (data) {
          _currentOutput = (_currentOutput ?? '') + data;
          stderrBuffer.write(data);
          onError?.call(data);
          forwardProgress(data);
          checkReadyAndCaptureUrl(data);
        },
        onDone: () {
          if (!stderrDone.isCompleted) stderrDone.complete();
        },
        onError: (_) {
          if (!stderrDone.isCompleted) stderrDone.complete();
        },
      );

      process.exitCode.then((exitCode) async {
        // Esperar a que stdout/stderr terminen de vaciar las últimas líneas de error.
        await Future.wait([stdoutDone.future, stderrDone.future])
            .timeout(const Duration(milliseconds: 500), onTimeout: () => []);
        onOutput?.call('\n\n✅ Proceso terminado con código: $exitCode\n');
        try {
          final debug = DebugConsoleService();
          if (exitCode != 0) {
            debug.setCompilationProgress(
              0.0,
              '❌ Compilación/ejecución falló (exit $exitCode)',
            );
            if (embeddedPreview) debug.setAppUrl(null);
          }
          debug.setRunning(false);
        } catch (_) {}
        _notifyProcessEnded();
        completeOnce({
          'success': exitCode == 0,
          'exitCode': exitCode,
          'output': _currentOutput ?? '',
          'error': stderrBuffer.toString(),
          'pid': process.pid,
          if (exitCode == 0 && previewUrl != null) 'previewUrl': previewUrl,
        });
      });

      // Esperar resultado real de la compilación (listo o fallo), máx. 2 min.
      return await startupCompleter.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => {
          'success': false,
          'exitCode': -1,
          'timedOut': true,
          'output': _currentOutput ?? '',
          'error':
              'Timeout esperando compilación tras 120s.\n${stderrBuffer.toString()}',
          'pid': process.pid,
        },
      );
    } catch (e) {
      _notifyProcessEnded();
      _currentOutput = (_currentOutput ?? '') + '❌ Error: $e\n';
      onError?.call('❌ Error: $e\n');
      throw Exception('Error al ejecutar: $e');
    }
  }

  /// Hot Reload vía stdin (`r`).
  static Future<bool> hotReload() async {
    return _sendFlutterCommand('r', label: 'Hot Reload');
  }

  /// Hot Restart vía stdin (`R`).
  static Future<bool> hotRestart() async {
    return _sendFlutterCommand('R', label: 'Hot Restart');
  }

  static Future<bool> _sendFlutterCommand(
    String key, {
    required String label,
  }) async {
    final process = _currentProcess;
    if (process == null || !_isRunning) {
      print('⚠️ $label: no hay proceso activo en RunDebugService');
      return false;
    }
    try {
      process.stdin.writeln(key);
      await process.stdin.flush();
      print('✅ $label enviado (RunDebugService pid=${process.pid})');
      return true;
    } catch (e) {
      print('❌ Error enviando $label: $e');
      return false;
    }
  }

  /// Detiene `flutter run`: SIGTERM inmediato; SIGKILL a los 2s si sigue vivo.
  static Future<void> stop() async {
    final process = _currentProcess;
    if (process == null) {
      _isRunning = false;
      _currentOutput = null;
      return;
    }

    try {
      print('🛑 Enviando SIGTERM al proceso pid=${process.pid}...');
      process.kill(ProcessSignal.sigterm);

      var exited = false;
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
        exited = true;
      } on TimeoutException {
        exited = false;
      }

      if (!exited) {
        print('⚠️ Proceso aún vivo tras 2s — enviando SIGKILL...');
        try {
          process.kill(ProcessSignal.sigkill);
        } catch (_) {}
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          print('⚠️ SIGKILL: el proceso no respondió a tiempo');
        }
      }
    } catch (e) {
      print('⚠️ Error al detener proceso: $e');
    } finally {
      _currentOutput = null;
      _notifyProcessEnded();
    }
  }
  
  // ✅ NUEVO: Limpiar todo cuando se cambia de proyecto
  static Future<void> cleanup() async {
    print('🧹 Limpiando RunDebugService...');
    await stop();
    _currentOutput = null;
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