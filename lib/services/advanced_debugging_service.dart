import 'dart:io';
import 'dart:async';
import 'dart:convert';

import '../models/problem_item.dart';
import 'debug_console_service.dart';
import 'project_platform_support.dart';

/// Servicio avanzado de debugging y análisis de compilación
/// Proporciona herramientas para ejecutar, analizar y depurar código Flutter

class AdvancedDebuggingService {
  /// Referencia real del `Process` de `dart:io` para el `flutter run` activo.
  static Process? _activeProcess;
  static void Function()? _onProcessEnded;
  /// `debug` | `profile` | `release` del flutter run activo.
  static String _activeMode = 'debug';
  static bool _appInteractive = false; // true cuando stdin acepta r/R

  /// Proceso Flutter actualmente en ejecución (si hay alguno).
  static Process? get activeProcess => _activeProcess;

  static bool get isRunning => _activeProcess != null;

  /// Hot Reload/Restart solo funcionan en debug (JIT).
  static bool get supportsHotReload =>
      isRunning && _activeMode == 'debug' && _appInteractive;

  /// Notifica a la UI cuando el proceso realmente termina (exit o stop).
  static void setOnProcessEnded(void Function()? callback) {
    _onProcessEnded = callback;
  }

  static void _clearActiveProcess({bool notify = true}) {
    _activeProcess = null;
    _appInteractive = false;
    _activeMode = 'debug';
    if (notify) {
      try {
        // Actualiza toolbar / console sin reentrar en stop().
        final debug = DebugConsoleService();
        debug.setRunning(false);
        debug.setCompilationProgress(0.0, '');
        debug.addDebugConsole('🛑 Proceso Flutter terminado');
      } catch (_) {}
      _onProcessEnded?.call();
    }
  }

  static void _markProcessActive(Process process, {String mode = 'debug'}) {
    _activeProcess = process;
    _activeMode = mode;
    _appInteractive = false;
    try {
      final debug = DebugConsoleService();
      debug.setRunning(true);
      debug.setCompilationProgress(0.15, 'Compilando ($mode)...');
      debug.addDebugConsole(
        '🚀 flutter run activo (pid=${process.pid}, mode=$mode)',
      );
    } catch (_) {}
  }

  /// Detecta cuando la app ya está lista para Hot Reload / Hot Restart.
  static void _maybeMarkAppReady(String line) {
    final lower = line.toLowerCase();
    final strongReady = lower.contains('flutter run key commands') ||
        lower.contains('to hot reload') ||
        lower.contains('an observatory debugger') ||
        lower.contains('dart vm service is listening') ||
        lower.contains('observatory listening');
    final warming = lower.contains('syncing files to device') ||
        lower.contains('launching lib/main.dart') ||
        lower.contains('waiting for connection') ||
        lower.contains('running with sound null safety');

    if (!strongReady && !warming) {
      // Solo URL de la app ("is being served at"), nunca DevTools.
      _capturePreviewUrlFromLine(line, softProgress: true);
      return;
    }

    try {
      final debug = DebugConsoleService();
      debug.setRunning(true);
      if (strongReady) {
        _appInteractive = _activeMode == 'debug';
        debug.setCompilationProgress(
          1.0,
          _appInteractive
              ? 'Aplicación en ejecución (Hot Reload listo)'
              : 'Aplicación en ejecución ($_activeMode — sin Hot Reload)',
        );
        debug.addDebugConsole(
          _appInteractive
              ? '⚡ Hot Reload/Restart disponibles (stdin r/R)'
              : '⚠️ Modo $_activeMode: Hot Reload no disponible',
        );
      } else if (debug.compilationProgress < 0.85) {
        debug.setCompilationProgress(0.85, 'Iniciando aplicación...');
      }
      _capturePreviewUrlFromLine(line, softProgress: false);
    } catch (_) {}
  }

  /// Extrae la URL del Preview (web-server), ignorando DevTools / VM Service.
  static void _capturePreviewUrlFromLine(
    String line, {
    required bool softProgress,
  }) {
    try {
      final debug = DebugConsoleService();
      // Preferir el patrón explícito de flutter web-server.
      final served = RegExp(
        r'(?:is being served at|serving at|Serving at)\s*(https?://[^\s]+)',
        caseSensitive: false,
      ).firstMatch(line);
      if (served != null) {
        final url = served.group(1)!.trim();
        if (DebugConsoleService.isPreviewAppUrl(url)) {
          debug.setAppUrl(url);
          if (softProgress && debug.compilationProgress < 0.7) {
            debug.setCompilationProgress(0.7, 'Servidor web listo, compilando…');
          }
        }
        return;
      }

      // No capturar líneas de DevTools / Observatory.
      final lower = line.toLowerCase();
      if (lower.contains('devtools') ||
          lower.contains('vm service') ||
          lower.contains('observatory') ||
          lower.contains('debugger and profiler')) {
        final vm = RegExp(r'https?://[^\s]+').firstMatch(line);
        if (vm != null) debug.setVmServiceUri(vm.group(0));
        return;
      }

      final urlOnly =
          RegExp(r'https?://(?:localhost|127\.0\.0\.1):\d+[^\s]*').firstMatch(line);
      if (urlOnly != null) {
        final url = urlOnly.group(0)!;
        if (DebugConsoleService.isPreviewAppUrl(url)) {
          debug.setAppUrl(url);
          if (softProgress && debug.compilationProgress < 0.7) {
            debug.setCompilationProgress(0.7, 'Servidor web listo, compilando…');
          }
        }
      }
    } catch (_) {}
  }

  /// Hot Reload: envía `r` al stdin de `flutter run` (solo debug).
  static Future<bool> hotReload() async {
    return _sendFlutterCommand('r', label: 'Hot Reload');
  }

  /// Hot Restart: envía `R` al stdin de `flutter run` (solo debug).
  static Future<bool> hotRestart() async {
    return _sendFlutterCommand('R', label: 'Hot Restart');
  }

  static Future<bool> _sendFlutterCommand(
    String key, {
    required String label,
  }) async {
    final process = _activeProcess;
    final debug = DebugConsoleService();
    if (process == null) {
      debug.addDebugConsole(
        '⚠️ $label: no hay proceso Flutter activo. Pulsa Run primero.',
      );
      print('⚠️ $label: no hay proceso Flutter activo');
      return false;
    }
    if (_activeMode != 'debug') {
      debug.addDebugConsole(
        '⚠️ $label no funciona en modo $_activeMode. '
        'Stop + Run (debug) para habilitar Hot Reload.',
      );
      return false;
    }
    if (!_appInteractive) {
      debug.addDebugConsole(
        '⚠️ $label: la app aún no está lista (espera '
        '"Flutter run key commands" / VM Service).',
      );
      return false;
    }
    try {
      process.stdin.writeln(key);
      await process.stdin.flush();
      debug.addDebugConsole('✅ $label enviado (pid=${process.pid})');
      print('✅ $label enviado al proceso pid=${process.pid}');
      return true;
    } catch (e) {
      debug.addDebugConsole('❌ Error enviando $label: $e');
      print('❌ Error enviando $label: $e');
      return false;
    }
  }

  /// Detiene `flutter run`: SIGTERM; si sigue vivo a los 2s, SIGKILL.
  /// Limpia la referencia y notifica a la UI.
  static Future<void> stop() async {
    final process = _activeProcess;
    if (process == null) {
      _clearActiveProcess();
      return;
    }

    try {
      print('🛑 AdvancedDebuggingService: SIGTERM pid=${process.pid}');
      process.kill(ProcessSignal.sigterm);

      var exited = false;
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
        exited = true;
      } on TimeoutException {
        exited = false;
      }

      if (!exited) {
        print('⚠️ Proceso vivo tras 2s — SIGKILL pid=${process.pid}');
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
      print('⚠️ Error al detener proceso Flutter: $e');
    } finally {
      _clearActiveProcess();
    }
  }

  /// Lista los dispositivos disponibles de Flutter
  static Future<List<Map<String, String>>> getAvailableDevices() async {
    final devices = <Map<String, String>>[];
    
    try {
      print('🔍 Ejecutando: flutter devices --machine');
      final process = await Process.run(
        'flutter',
        ['devices', '--machine'],
        runInShell: true,
      );

      print('📱 Exit code: ${process.exitCode}');
      final stdoutStr = process.stdout.toString().trim();
      print('📱 Stdout length: ${stdoutStr.length}');
      if (process.stderr.toString().isNotEmpty) {
        print('📱 Stderr: ${process.stderr.toString()}');
      }

      if (process.exitCode == 0 && stdoutStr.isNotEmpty) {
        try {
          // flutter devices --machine devuelve un array JSON completo
          final deviceList = jsonDecode(stdoutStr) as List<dynamic>;
          
          print('📱 Dispositivos encontrados en JSON: ${deviceList.length}');
          
          for (var deviceData in deviceList) {
            if (deviceData is! Map<String, dynamic>) continue;
            
            final id = deviceData['id']?.toString() ?? '';
            final name = deviceData['name']?.toString() ?? '';
            final category = deviceData['category']?.toString() ?? '';
            final platform = deviceData['platform']?.toString() ?? '';
            
            print('📱 Dispositivo detectado: $name ($id) - Categoría: $category - Plataforma: $platform');
            
            if (id.isNotEmpty && name.isNotEmpty) {
              devices.add({
                'id': id,
                'name': name,
                'category': category,
                'platform': platform,
              });
            }
          }
        } catch (e) {
          print('⚠️ Error al parsear JSON de dispositivos: $e');
          print('📱 Output completo: $stdoutStr');
          // Intentar parsear línea por línea como fallback
          final lines = stdoutStr.split('\n');
          for (var line in lines) {
            if (line.trim().isEmpty) continue;
            try {
              final deviceData = jsonDecode(line) as Map<String, dynamic>;
              final id = deviceData['id']?.toString() ?? '';
              final name = deviceData['name']?.toString() ?? '';
              final category = deviceData['category']?.toString() ?? '';
              final platform = deviceData['platform']?.toString() ?? '';
              
              if (id.isNotEmpty && name.isNotEmpty) {
                devices.add({
                  'id': id,
                  'name': name,
                  'category': category,
                  'platform': platform,
                });
              }
            } catch (e2) {
              // Ignorar líneas que no son JSON válido
            }
          }
        }
      } else {
        print('❌ Error al ejecutar flutter devices: exit code ${process.exitCode}');
      }
    } catch (e) {
      print('⚠️ Error al listar dispositivos: $e');
    }
    
    print('📱 Total de dispositivos encontrados: ${devices.length}');
    return devices;
  }

  /// Encuentra el ID del dispositivo más apropiado para la plataforma
  /// IMPORTANTE: Solo devuelve un dispositivo si coincide EXACTAMENTE con la plataforma solicitada
  static Future<String?> findDeviceId(String platform) async {
    print('🔍 Buscando dispositivo para plataforma: $platform');
    final devices = await getAvailableDevices();
    
    if (devices.isEmpty) {
      print('⚠️ No hay dispositivos disponibles');
      return null;
    }
    
    print('📱 Dispositivos disponibles: ${devices.length}');
    for (var device in devices) {
      print('   - ${device['name']} (${device['id']}, platform: ${device['platform']}, category: ${device['category']})');
    }
    
    // Buscar dispositivo que coincida EXACTAMENTE con la plataforma
    for (var device in devices) {
      final id = device['id'] ?? '';
      final devicePlatform = device['platform']?.toLowerCase() ?? '';
      final deviceCategory = device['category']?.toLowerCase() ?? '';
      
      // Para Android, buscar SOLO dispositivos Android
      if (platform.toLowerCase() == 'android') {
        // Buscar dispositivos Android por múltiples criterios
        if (id.contains('android') || 
            id.contains('emulator') ||
            id.startsWith('emulator-') ||
            devicePlatform == 'android' ||
            (deviceCategory == 'mobile' && devicePlatform != 'ios' && devicePlatform != 'macos')) {
          print('✅ Dispositivo Android encontrado: ${device['name']} (${device['id']}, platform: $devicePlatform, category: $deviceCategory)');
          return id;
        }
      }
      // Para iOS, buscar SOLO dispositivos iOS
      else if (platform.toLowerCase() == 'ios') {
        if (id.contains('ios') || 
            id.contains('simulator') ||
            id.contains('iPhone') ||
            id.contains('iPad') ||
            devicePlatform == 'ios' ||
            (deviceCategory == 'mobile' && devicePlatform == 'ios')) {
          print('✅ Dispositivo iOS encontrado: ${device['name']} (${device['id']}, platform: $devicePlatform, category: $deviceCategory)');
          return id;
        }
      }
      // Para macOS, buscar SOLO dispositivos macOS
      else if (platform.toLowerCase() == 'macos') {
        if (id.contains('macos') || 
            id.contains('mac') ||
            devicePlatform == 'macos' ||
            devicePlatform == 'darwin' ||
            (deviceCategory == 'desktop' && devicePlatform == 'macos')) {
          print('✅ Dispositivo macOS encontrado: ${device['name']} (${device['id']}, platform: $devicePlatform, category: $deviceCategory)');
          return id;
        }
      }
      // Para otras plataformas, buscar coincidencia exacta
      else if (id == platform || devicePlatform == platform.toLowerCase() || deviceCategory == platform.toLowerCase()) {
        print('✅ Dispositivo encontrado: ${device['name']} (${device['id']}, platform: $devicePlatform, category: $deviceCategory)');
        return id;
      }
    }
    
    // NO devolver un dispositivo por defecto - esto causaría ejecución en plataforma incorrecta
    print('❌ No se encontró dispositivo para la plataforma "$platform"');
    print('   Solo se ejecutará en la plataforma solicitada si hay un dispositivo disponible');
    return null;
  }

  /// Lanza AVD (Android) o Simulator (iOS) vía `flutter emulators --launch`.
  static Future<bool> launchNativeEmulator(
    String platform, [
    Function(String line)? onOutput,
  ]) async {
    final base = ProjectPlatformSupport.basePlatform(platform);
    try {
      final listed = await Process.run(
        'flutter',
        ['emulators'],
        runInShell: false,
      );
      final out = '${listed.stdout}\n${listed.stderr}';
      onOutput?.call(out.trim().isEmpty ? 'flutter emulators (vacío)' : out.trim());

      // Líneas tipo: "Pixel_6 • Pixel 6 • Google • android"
      final ids = <String>[];
      for (final line in out.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.toLowerCase().startsWith('id')) continue;
        final id = trimmed.split(RegExp(r'\s+•\s+|\s+')).first.trim();
        if (id.isEmpty) continue;
        final lower = trimmed.toLowerCase();
        if (base == 'android' &&
            (lower.contains('android') ||
                lower.contains('pixel') ||
                lower.contains('api'))) {
          ids.add(id);
        } else if (base == 'ios' &&
            (lower.contains('ios') ||
                lower.contains('iphone') ||
                lower.contains('ipad') ||
                lower.contains('apple'))) {
          ids.add(id);
        }
      }

      if (ids.isEmpty && base == 'ios') {
        // Fallback: abrir Simulator.app en macOS
        onOutput?.call('📲 Abriendo Simulator.app…');
        await Process.run('open', ['-a', 'Simulator'], runInShell: false);
        return true;
      }

      if (ids.isEmpty) {
        onOutput?.call('❌ No hay emuladores listados para $base');
        return false;
      }

      final id = ids.first;
      onOutput?.call('📲 flutter emulators --launch $id');
      final launch = await Process.run(
        'flutter',
        ['emulators', '--launch', id],
        runInShell: false,
      );
      onOutput?.call('${launch.stdout}${launch.stderr}'.trim());
      return launch.exitCode == 0;
    } catch (e) {
      onOutput?.call('❌ Error lanzando emulador: $e');
      return false;
    }
  }

  /// `flutter run -d web-server` → URL en DebugConsole para el WebView central.
  static Future<CompilationResult> _startEmbeddedWebPreview({
    required String projectPath,
    required String platform,
    required String mode,
    required CompilationResult result,
    Function(String line)? onOutput,
    Function(CompilationError error)? onError,
    bool useWebServer = true,
  }) async {
    final label = ProjectPlatformSupport.humanLabel(platform);
    final isMobile = ProjectPlatformSupport.isEmbeddedMobilePreview(platform) ||
        platform == 'android' ||
        platform == 'ios';

    print('🌐 Preview embebido ($label)…');
    onOutput?.call(
      isMobile
          ? '📱 $label → web-server en el marco de teléfono (sin emulador externo)'
          : '🌐 Iniciando compilación para Web…',
    );
    onOutput?.call('💡 No requiere dispositivo físico ni emulador de Android Studio');

    final port = await _findFreeWebPort(preferred: 8085);
    final args = <String>[
      'run',
      '-d',
      'web-server',
      '--web-hostname',
      '127.0.0.1',
      '--web-port',
      '$port',
    ];
    if (mode == 'release') {
      args.add('--release');
    } else if (mode == 'profile') {
      args.add('--profile');
    }

    final previewUrl = 'http://127.0.0.1:$port';
    onOutput?.call(
      '🌐 web-server ($previewUrl) — Preview dentro de Voryxel Code'
      '${isMobile ? ' · carcasa $label' : ''}',
    );

    try {
      final debug = DebugConsoleService();
      debug.setRunning(true);
      debug.setAppUrl(previewUrl);
      debug.setCompilationProgress(
        0.35,
        isMobile ? 'Compilando $label Preview…' : 'Compilando Web Preview…',
      );
      debug.addDebugConsole(
        '🌐 Preview → $previewUrl (useWebServer=$useWebServer)',
      );
    } catch (_) {}

    print('🌐 Comando: flutter ${args.join(' ')}');
    final process = await Process.start(
      'flutter',
      args,
      workingDirectory: projectPath,
      mode: ProcessStartMode.normal,
      runInShell: false,
    );
    _markProcessActive(process, mode: mode);
    return _processFlutterOutput(process, result, onOutput, onError);
  }

  /// Puerto libre para `flutter run -d web-server` (preferido [preferred]).
  static Future<int> _findFreeWebPort({int preferred = 8085}) async {
    Future<bool> isFree(int port) async {
      try {
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
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
    // Último recurso: SO elige puerto efímero
    final ephemeral =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = ephemeral.port;
    await ephemeral.close();
    return port;
  }

  /// Ejecuta flutter run y analiza la salida en tiempo real.
  /// Almacena la referencia real del [Process] para [stop].
  ///
  /// Preview embebido: `web`, `android` (Preview) e `ios` (Preview) usan
  /// `-d web-server` → WebView dentro del marco central.
  /// `android_native` / `ios_native` lanzan emulador/simulador externo.
  static Future<CompilationResult> runFlutterApp({
    required String projectPath,
    String platform = 'macos',
    String mode = 'debug',
    bool useWebServer = true,
    // Flutter 3.22+ eliminó --web-renderer; se ignora (compat con callers viejos).
    String? webRenderer,
    Function(String line)? onOutput,
    Function(CompilationError error)? onError,
    void Function()? onProcessEnded,
  }) async {
    final result = CompilationResult(
      platform: platform,
      mode: mode,
      startTime: DateTime.now(),
    );
    // Compat: callers antiguos pasaban html/canvaskit; Flutter ya no lo acepta.
    assert(() {
      // ignore: unnecessary_statements
      webRenderer;
      return true;
    }());

    if (onProcessEnded != null) {
      _onProcessEnded = onProcessEnded;
    }

    try {
      // Detener proceso previo para evitar zombies
      if (_activeProcess != null) {
        await stop();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Validar que el directorio del proyecto existe
      final projectDir = Directory(projectPath);
      if (!await projectDir.exists()) {
        final errorMsg = '❌ El directorio del proyecto no existe: $projectPath';
        print(errorMsg);
        onOutput?.call(errorMsg);
        result.errors.add(errorMsg);
        result.success = false;
        return result;
      }
      
      // Verificar que es un proyecto Flutter
      final pubspecFile = File('$projectPath/pubspec.yaml');
      if (!await pubspecFile.exists()) {
        final errorMsg = '❌ No es un proyecto Flutter válido (no se encontró pubspec.yaml): $projectPath';
        print(errorMsg);
        onOutput?.call(errorMsg);
        result.errors.add(errorMsg);
        result.success = false;
        return result;
      }
      
      // Obtener nombre del proyecto para logging
      try {
        final pubspecContent = await pubspecFile.readAsString();
        final nameMatch = RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(pubspecContent);
        final projectName = nameMatch?.group(1)?.trim() ?? projectPath.split('/').last;
        print('📦 Ejecutando proyecto: $projectName');
        print('📁 Ruta del proyecto: $projectPath');
        onOutput?.call('📦 Proyecto: $projectName');
        onOutput?.call('📁 Ruta: $projectPath');
      } catch (e) {
        print('⚠️ Error al leer nombre del proyecto: $e');
      }
      
      final plat = platform.toLowerCase().trim();

      // Web + Android/iOS (Preview) → web-server en el Preview central.
      // No falla por falta de emulador: siempre hay marco de teléfono / WebView.
      if (plat == 'web' ||
          ProjectPlatformSupport.isEmbeddedMobilePreview(plat)) {
        return _startEmbeddedWebPreview(
          projectPath: projectPath,
          platform: plat,
          mode: mode,
          result: result,
          onOutput: onOutput,
          onError: onError,
          useWebServer: useWebServer,
        );
      }

      // Target nativo: android_native / ios_native / macos / etc.
      final devicePlatform = ProjectPlatformSupport.basePlatform(plat);
      final devices = await getAvailableDevices();

      if (devices.isEmpty) {
        onOutput?.call('⚠️ No se detectaron dispositivos disponibles');
      } else {
        onOutput?.call('📱 Dispositivos disponibles: ${devices.length}');
        for (var device in devices) {
          final devicePlatformLabel =
              device['platform'] ?? device['category'] ?? 'desconocida';
          onOutput?.call(
            '  - ${device['name']} (${device['id']}) - $devicePlatformLabel',
          );
        }
      }

      var deviceId = await findDeviceId(devicePlatform);

      // Emulador Nativo: si no hay device, intentar lanzar AVD / Simulator.
      if (deviceId == null &&
          ProjectPlatformSupport.isNativeMobileTarget(plat)) {
        onOutput?.call(
          '📲 Lanzando emulador nativo ($devicePlatform)…',
        );
        final launched = await launchNativeEmulator(devicePlatform, onOutput);
        if (launched) {
          for (var i = 0; i < 20 && deviceId == null; i++) {
            await Future.delayed(const Duration(seconds: 2));
            deviceId = await findDeviceId(devicePlatform);
          }
        }
      }

      if (deviceId == null) {
        // Fallback de seguridad: Preview embebido en vez de error duro
        // (excepto si el usuario pidió explícitamente nativo y falló el launch).
        if (ProjectPlatformSupport.isNativeMobileTarget(plat)) {
          final errorMsg =
              '❌ No se pudo iniciar el emulador nativo "$devicePlatform".\n'
              '💡 Usa Android (Preview) / iOS (Preview) para ver la app '
              'dentro de Voryxel Code, o abre el AVD/Simulador manualmente.';
          result.errors.add(errorMsg);
          result.success = false;
          result.endTime = DateTime.now();
          result.phase = 'error';
          onOutput?.call(errorMsg);
          onError?.call(CompilationError(
            file: '',
            line: 0,
            column: 0,
            type: 'error',
            message: errorMsg,
          ));
          return result;
        }

        onOutput?.call(
          '📱 Sin dispositivo $devicePlatform — usando Preview embebido '
          '(web-server en el marco central).',
        );
        return _startEmbeddedWebPreview(
          projectPath: projectPath,
          platform: devicePlatform,
          mode: mode,
          result: result,
          onOutput: onOutput,
          onError: onError,
          useWebServer: useWebServer,
        );
      }

      print('🚀 Iniciando flutter run en $deviceId ($plat, $mode)...');
      onOutput?.call('🚀 Ejecutando en dispositivo: $deviceId');
      onOutput?.call('📁 Proyecto: $projectPath');

      final runArgs = <String>['run', '-d', deviceId];
      if (mode == 'release') {
        runArgs.add('--release');
      } else if (mode == 'profile') {
        runArgs.add('--profile');
      }

      final process = await Process.start(
        'flutter',
        runArgs,
        workingDirectory: projectPath,
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
      _markProcessActive(process, mode: mode);

      return _processFlutterOutput(process, result, onOutput, onError);

    } catch (e) {
      print('❌ Error al ejecutar flutter run: $e');
      result.endTime = DateTime.now();
      result.success = false;
      result.errors.add('Error: $e');
      _clearActiveProcess();
      return result;
    }
  }

  /// Procesa la salida de un proceso de Flutter (stdout/stderr)
  static Future<CompilationResult> _processFlutterOutput(
    Process process,
    CompilationResult result,
    Function(String line)? onOutput,
    Function(CompilationError error)? onError,
  ) async {
    // Capturar stdout
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      result.output.add(line);
      onOutput?.call(line);

      // Analizar línea para detectar errores o warnings
      _analyzeLine(line, result);
      _maybeMarkAppReady(line);
    });

    // Capturar stderr (errores reales de compilación)
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      result.errors.add(line);
      
      // También agregar a output para que se muestre en Debug Console
      result.output.add(line);
      onOutput?.call(line);
      _maybeMarkAppReady(line);

      // Parsear error
      final error = _parseError(line);
      if (error != null) {
        result.compilationErrors.add(error);
        onError?.call(error);
      }
    });

    // Esperar a que termine y limpiar referencia + notificar UI
    final exitCode = await process.exitCode;
    result.exitCode = exitCode;
    result.endTime = DateTime.now();
    result.success = exitCode == 0;

    if (identical(_activeProcess, process)) {
      _clearActiveProcess();
    }

    print(result.success 
        ? '✅ Compilación exitosa' 
        : '❌ Compilación fallida (exit code: $exitCode)');

    return result;
  }

  /// Ejecuta `flutter analyze --no-pub` (y, si existe, salida machine/JSON)
  /// y parsea diagnósticos a [ProblemItem] estructurados.
  static Future<List<ProblemItem>> runFlutterAnalyze(String projectPath) async {
    final problems = <ProblemItem>[];
    final projectDir = Directory(projectPath);
    if (!await projectDir.exists()) {
      return problems;
    }

    try {
      // Preferir formato humano estable (`--machine` no está en todas las versiones).
      print('🔍 Ejecutando: flutter analyze --no-pub');
      final process = await Process.run(
        'flutter',
        ['analyze', '--no-pub'],
        workingDirectory: projectPath,
        runInShell: false,
      );

      final combined = '${process.stdout}\n${process.stderr}';
      for (final line in combined.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        // Si alguna toolchain emite JSON por línea, también lo aceptamos.
        final fromMachine = _parseMachineAnalyzeLine(trimmed, projectPath);
        if (fromMachine != null) {
          problems.add(fromMachine);
          continue;
        }

        final fromHuman = _parseHumanAnalyzeLine(trimmed, projectPath);
        if (fromHuman != null) {
          problems.add(fromHuman);
        }
      }

      print('📊 flutter analyze: ${problems.length} problema(s)');
    } catch (e) {
      print('❌ Error en runFlutterAnalyze: $e');
    }

    return problems;
  }

  /// Parsea una línea JSON de `flutter analyze --machine`.
  static ProblemItem? _parseMachineAnalyzeLine(String line, String projectPath) {
    if (!line.startsWith('{')) return null;
    try {
      final json = jsonDecode(line);
      if (json is! Map<String, dynamic>) return null;

      // Formato Analysis Server / dart analyze --format=machine (JSON por línea)
      final severityRaw = (json['severity'] ?? json['type'] ?? '').toString();
      if (severityRaw.isEmpty && json['event'] != null) {
        // Eventos con params.errors[]
        final params = json['params'];
        if (params is Map<String, dynamic>) {
          final errors = params['errors'];
          // Este método solo parsea un ítem; los arrays se expanden en el caller
          // vía líneas individuales. Si viene embebido, no lo tratamos aquí.
          if (errors is List) return null;
        }
        return null;
      }

      String filePath = '';
      int lineNum = 0;
      int column = 0;

      final location = json['location'];
      if (location is Map<String, dynamic>) {
        filePath = (location['file'] ?? location['path'] ?? '').toString();
        final range = location['range'];
        if (range is Map<String, dynamic>) {
          final start = range['start'];
          if (start is Map<String, dynamic>) {
            lineNum = (start['line'] as num?)?.toInt() ?? 0;
            column = (start['column'] as num?)?.toInt() ?? 0;
          }
        }
        lineNum = lineNum != 0
            ? lineNum
            : (location['line'] as num?)?.toInt() ?? 0;
        column = column != 0
            ? column
            : (location['column'] as num?)?.toInt() ?? 0;
      } else {
        filePath = (json['file'] ?? json['path'] ?? '').toString();
        lineNum = (json['line'] as num?)?.toInt() ?? 0;
        column = (json['column'] as num?)?.toInt() ?? 0;
      }

      final message = (json['message'] ?? json['problemMessage'] ?? '').toString();
      final code = (json['code'] ?? json['errorCode'] ?? '').toString();
      if (message.isEmpty && filePath.isEmpty) return null;

      return ProblemItem.fromSeverityString(
        filePath: _toRelativePath(filePath, projectPath),
        line: lineNum,
        column: column,
        severity: severityRaw.isEmpty ? 'info' : severityRaw,
        message: message,
        code: code,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parsea formatos humanos de analyzer:
  /// - `  error • msg • lib/a.dart:10:5 • code`
  /// - `lib/a.dart:10:5: Error: message`
  /// - `  error - message at lib/a.dart:10:5 - (code)`
  static ProblemItem? _parseHumanAnalyzeLine(String line, String projectPath) {
    if (line.isEmpty) return null;

    // Formato bullet: severity • message • path:line:col • code
    final bullet = RegExp(
      r'^\s*(error|warning|info|hint)\s*[•·\-]\s*(.+?)\s*[•·\-]\s*(.+?):(\d+):(\d+)\s*[•·\-]\s*(.+)\s*$',
      caseSensitive: false,
    ).firstMatch(line);
    if (bullet != null) {
      return ProblemItem.fromSeverityString(
        filePath: _toRelativePath(bullet.group(3)!, projectPath),
        line: int.tryParse(bullet.group(4)!) ?? 0,
        column: int.tryParse(bullet.group(5)!) ?? 0,
        severity: bullet.group(1)!,
        message: bullet.group(2)!.trim(),
        code: bullet.group(6)!.trim().replaceAll(RegExp(r'[()]'), ''),
      );
    }

    // Formato "at": severity - message at path:line:col - (code)
    final atFmt = RegExp(
      r'^\s*(error|warning|info|hint)\s*[-–]\s*(.+?)\s+at\s+(.+?):(\d+):(\d+)(?:\s*[-–]\s*\(?([^)\s]+)\)?)?',
      caseSensitive: false,
    ).firstMatch(line);
    if (atFmt != null) {
      return ProblemItem.fromSeverityString(
        filePath: _toRelativePath(atFmt.group(3)!, projectPath),
        line: int.tryParse(atFmt.group(4)!) ?? 0,
        column: int.tryParse(atFmt.group(5)!) ?? 0,
        severity: atFmt.group(1)!,
        message: atFmt.group(2)!.trim(),
        code: atFmt.group(6)?.trim() ?? '',
      );
    }

    // Formato clásico: path:line:col: error: message
    final classic = RegExp(
      r'^(.+?):(\d+):(\d+):\s*(error|warning|info|hint):\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (classic != null) {
      return ProblemItem.fromSeverityString(
        filePath: _toRelativePath(classic.group(1)!, projectPath),
        line: int.tryParse(classic.group(2)!) ?? 0,
        column: int.tryParse(classic.group(3)!) ?? 0,
        severity: classic.group(4)!,
        message: classic.group(5)!.trim(),
      );
    }

    return null;
  }

  static String _toRelativePath(String filePath, String projectPath) {
    var normalized = filePath.replaceAll('\\', '/');
    final root = projectPath.replaceAll('\\', '/');
    if (normalized.startsWith('$root/')) {
      return normalized.substring(root.length + 1);
    }
    // Quitar prefijos absolutos comunes si el analyzer ya devolvió relativo
    if (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    return normalized;
  }

  /// Ejecuta flutter test y analiza resultados
  static Future<TestResult> runFlutterTests({
    required String projectPath,
    String? testPath,
    Function(String line)? onOutput,
  }) async {
    final result = TestResult(startTime: DateTime.now());

    try {
      print('🧪 Ejecutando tests...');

      final args = ['test'];
      if (testPath != null) {
        args.add(testPath);
      }

      final process = await Process.start(
        'flutter',
        args,
        workingDirectory: projectPath,
        runInShell: true,
      );

      // Capturar salida
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        result.output.add(line);
        onOutput?.call(line);
        _analyzeTestLine(line, result);
      });

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        result.errors.add(line);
      });

      final exitCode = await process.exitCode;
      result.exitCode = exitCode;
      result.endTime = DateTime.now();
      result.success = exitCode == 0;

      print(result.success
          ? '✅ Tests pasaron (${result.passed}/${result.total})'
          : '❌ Tests fallaron (${result.failed} fallos)');

      return result;
    } catch (e) {
      print('❌ Error al ejecutar tests: $e');
      result.endTime = DateTime.now();
      result.success = false;
      return result;
    }
  }

  /// Analiza errores de compilación de Dart/Flutter (delega a [runFlutterAnalyze]).
  static Future<List<CompilationError>> analyzeCompilationErrors(
    String projectPath,
  ) async {
    final items = await runFlutterAnalyze(projectPath);
    return items
        .map(
          (p) => CompilationError(
            file: p.filePath,
            line: p.line,
            column: p.column,
            type: p.severityLabel,
            message: p.code.isNotEmpty ? '${p.message} (${p.code})' : p.message,
          ),
        )
        .toList();
  }

  /// Analiza un stack trace y extrae información útil
  static StackTraceAnalysis analyzeStackTrace(String stackTrace) {
    final analysis = StackTraceAnalysis(rawTrace: stackTrace);

    try {
      final lines = stackTrace.split('\n');

      for (var line in lines) {
        // Detectar archivo y línea
        final match = RegExp(r'([^/]+\.dart):(\d+):(\d+)').firstMatch(line);
        if (match != null) {
          final frame = StackFrame(
            file: match.group(1) ?? '',
            line: int.tryParse(match.group(2) ?? '0') ?? 0,
            column: int.tryParse(match.group(3) ?? '0') ?? 0,
            content: line.trim(),
          );
          analysis.frames.add(frame);
        }

        // Detectar tipo de error
        if (line.contains('Exception:')) {
          analysis.errorType = 'Exception';
          analysis.errorMessage = line.split('Exception:').last.trim();
        } else if (line.contains('Error:')) {
          analysis.errorType = 'Error';
          analysis.errorMessage = line.split('Error:').last.trim();
        }
      }

      // Identificar archivo principal del error (primer frame)
      if (analysis.frames.isNotEmpty) {
        analysis.primaryFile = analysis.frames.first.file;
        analysis.primaryLine = analysis.frames.first.line;
      }

      // Generar sugerencias
      analysis.suggestions = _generateSuggestions(analysis);
    } catch (e) {
      print('⚠️ Error al analizar stack trace: $e');
    }

    return analysis;
  }

  /// Detecta problemas comunes en el código
  static Future<List<CodeIssue>> detectCommonIssues(
    String projectPath,
  ) async {
    final issues = <CodeIssue>[];

    try {
      // Buscar archivos Dart en lib/
      final libDir = Directory('$projectPath/lib');
      if (!await libDir.exists()) return issues;

      await for (var entity in libDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final content = await entity.readAsString();
          final fileIssues = _analyzeFileForIssues(entity.path, content);
          issues.addAll(fileIssues);
        }
      }

      print('🔍 Detectados ${issues.length} problemas potenciales');
    } catch (e) {
      print('❌ Error al detectar problemas: $e');
    }

    return issues;
  }

  /// Genera sugerencias de fixes para errores comunes
  static List<ErrorFix> suggestFixes(CompilationError error) {
    final fixes = <ErrorFix>[];

    // Fixes para errores comunes
    if (error.message.contains('Undefined name')) {
      fixes.add(ErrorFix(
        description: 'Agregar import faltante',
        code: '// Agregar: import \'package:...\';',
        confidence: 'high',
      ));
    }

    if (error.message.contains('The method') && error.message.contains('isn\'t defined')) {
      fixes.add(ErrorFix(
        description: 'Verificar nombre del método',
        code: '// Revisar si el método existe en la clase',
        confidence: 'medium',
      ));
    }

    if (error.message.contains('The getter') && error.message.contains('isn\'t defined')) {
      fixes.add(ErrorFix(
        description: 'Agregar propiedad faltante',
        code: '// Agregar la propiedad a la clase',
        confidence: 'high',
      ));
    }

    if (error.message.contains('Expected to find')) {
      fixes.add(ErrorFix(
        description: 'Error de sintaxis - revisar puntuación',
        code: '// Verificar paréntesis, llaves, puntos y comas',
        confidence: 'high',
      ));
    }

    return fixes;
  }

  // Métodos privados de análisis

  static void _analyzeLine(String line, CompilationResult result) {
    // Detectar inicio de compilación
    if (line.contains('Launching') || line.contains('Running')) {
      result.phase = 'launching';
    } else if (line.contains('Compiling') || line.contains('Building')) {
      result.phase = 'compiling';
    } else if (line.contains('Syncing') || line.contains('Installing')) {
      result.phase = 'installing';
    } else if (line.contains('Application finished')) {
      result.phase = 'finished';
    }

    // Detectar warnings
    if (line.contains('warning:') || line.contains('Warning:')) {
      result.warnings.add(line);
    }
  }

  static CompilationError? _parseError(String line) {
    // Formato típico: file.dart:line:column: error: message
    final match = RegExp(r'([^:]+):(\d+):(\d+):\s*(error|warning):\s*(.+)').firstMatch(line);
    
    if (match != null) {
      return CompilationError(
        file: match.group(1) ?? '',
        line: int.tryParse(match.group(2) ?? '0') ?? 0,
        column: int.tryParse(match.group(3) ?? '0') ?? 0,
        type: match.group(4) ?? 'error',
        message: match.group(5) ?? '',
      );
    }

    return null;
  }

  static void _analyzeTestLine(String line, TestResult result) {
    // Detectar tests pasados
    if (line.contains('✓') || line.contains('PASS')) {
      result.passed++;
      result.total++;
    }
    // Detectar tests fallados
    else if (line.contains('✗') || line.contains('FAIL')) {
      result.failed++;
      result.total++;
    }
    // Detectar tests skipped
    else if (line.contains('SKIP')) {
      result.skipped++;
      result.total++;
    }
  }

  static List<String> _generateSuggestions(StackTraceAnalysis analysis) {
    final suggestions = <String>[];

    if (analysis.errorType == 'Exception') {
      suggestions.add('Agregar try-catch para manejar la excepción');
      suggestions.add('Verificar que los datos de entrada sean válidos');
    }

    if (analysis.errorMessage?.contains('Null') ?? false) {
      suggestions.add('Verificar que las variables no sean null antes de usarlas');
      suggestions.add('Usar null-safety operators (?., ??, !)');
    }

    if (analysis.errorMessage?.contains('State') ?? false) {
      suggestions.add('Verificar el ciclo de vida del widget');
      suggestions.add('Asegurarse de que setState() se llame correctamente');
    }

    return suggestions;
  }

  static List<CodeIssue> _analyzeFileForIssues(String filePath, String content) {
    final issues = <CodeIssue>[];

    // Detectar print() en producción
    if (content.contains('print(')) {
      issues.add(CodeIssue(
        file: filePath,
        type: 'warning',
        message: 'Uso de print() detectado - considerar usar logger',
        severity: 'low',
      ));
    }

    // Detectar TODO/FIXME
    if (content.contains('TODO') || content.contains('FIXME')) {
      issues.add(CodeIssue(
        file: filePath,
        type: 'info',
        message: 'Comentarios TODO/FIXME pendientes',
        severity: 'low',
      ));
    }

    // Detectar clases muy grandes (> 500 líneas)
    final lines = content.split('\n');
    if (lines.length > 500) {
      issues.add(CodeIssue(
        file: filePath,
        type: 'warning',
        message: 'Archivo muy grande (${lines.length} líneas) - considerar refactorizar',
        severity: 'medium',
      ));
    }

    return issues;
  }
}

// Modelos de datos

class CompilationResult {
  final String platform;
  final String mode;
  final DateTime startTime;
  DateTime? endTime;
  int? exitCode;
  bool success = false;
  String phase = 'starting';
  List<String> output = [];
  List<String> errors = [];
  List<String> warnings = [];
  List<CompilationError> compilationErrors = [];

  CompilationResult({
    required this.platform,
    required this.mode,
    required this.startTime,
  });

  Duration? get duration => endTime != null ? endTime!.difference(startTime) : null;

  String get summary {
    final buffer = StringBuffer();
    buffer.writeln('Compilación $platform ($mode)');
    buffer.writeln('Estado: ${success ? "✅ Exitosa" : "❌ Fallida"}');
    if (duration != null) {
      buffer.writeln('Duración: ${duration!.inSeconds}s');
    }
    if (warnings.isNotEmpty) {
      buffer.writeln('Warnings: ${warnings.length}');
    }
    if (compilationErrors.isNotEmpty) {
      buffer.writeln('Errores: ${compilationErrors.length}');
    }
    return buffer.toString();
  }
}

class TestResult {
  final DateTime startTime;
  DateTime? endTime;
  int? exitCode;
  bool success = false;
  int total = 0;
  int passed = 0;
  int failed = 0;
  int skipped = 0;
  List<String> output = [];
  List<String> errors = [];

  TestResult({required this.startTime});

  Duration? get duration => endTime != null ? endTime!.difference(startTime) : null;

  String get summary {
    final buffer = StringBuffer();
    buffer.writeln('Tests: $passed/$total pasados');
    if (failed > 0) buffer.writeln('Fallidos: $failed');
    if (skipped > 0) buffer.writeln('Omitidos: $skipped');
    if (duration != null) {
      buffer.writeln('Duración: ${duration!.inSeconds}s');
    }
    return buffer.toString();
  }
}

class CompilationError {
  final String file;
  final int line;
  final int column;
  final String type; // 'error' o 'warning'
  final String message;

  CompilationError({
    required this.file,
    required this.line,
    required this.column,
    required this.type,
    required this.message,
  });

  @override
  String toString() {
    return '$file:$line:$column: $type: $message';
  }
}

class StackTraceAnalysis {
  final String rawTrace;
  String? errorType;
  String? errorMessage;
  String? primaryFile;
  int? primaryLine;
  List<StackFrame> frames = [];
  List<String> suggestions = [];

  StackTraceAnalysis({required this.rawTrace});

  String get summary {
    final buffer = StringBuffer();
    if (errorType != null) {
      buffer.writeln('Tipo: $errorType');
    }
    if (errorMessage != null) {
      buffer.writeln('Mensaje: $errorMessage');
    }
    if (primaryFile != null) {
      buffer.writeln('Archivo: $primaryFile:$primaryLine');
    }
    if (suggestions.isNotEmpty) {
      buffer.writeln('\nSugerencias:');
      for (var suggestion in suggestions) {
        buffer.writeln('- $suggestion');
      }
    }
    return buffer.toString();
  }
}

class StackFrame {
  final String file;
  final int line;
  final int column;
  final String content;

  StackFrame({
    required this.file,
    required this.line,
    required this.column,
    required this.content,
  });
}

class CodeIssue {
  final String file;
  final String type; // 'error', 'warning', 'info'
  final String message;
  final String severity; // 'low', 'medium', 'high'

  CodeIssue({
    required this.file,
    required this.type,
    required this.message,
    required this.severity,
  });
}

class ErrorFix {
  final String description;
  final String code;
  final String confidence; // 'low', 'medium', 'high'

  ErrorFix({
    required this.description,
    required this.code,
    required this.confidence,
  });
}
