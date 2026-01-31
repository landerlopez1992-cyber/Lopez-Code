import 'dart:io';
import 'dart:async';
import 'dart:convert';

/// Servicio avanzado de debugging y análisis de compilación
/// Proporciona herramientas para ejecutar, analizar y depurar código Flutter

class AdvancedDebuggingService {
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

  /// Ejecuta flutter run y analiza la salida en tiempo real
  static Future<CompilationResult> runFlutterApp({
    required String projectPath,
    String platform = 'macos',
    String mode = 'debug',
    bool useWebServer = false, // Si es true, usa web-server en lugar de chrome para plataforma web
    String? webRenderer, // html | canvaskit | auto
    Function(String line)? onOutput,
    Function(CompilationError error)? onError,
  }) async {
    final result = CompilationResult(
      platform: platform,
      mode: mode,
      startTime: DateTime.now(),
    );

    try {
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
      
      // Para Web, usar -d chrome o -d web-server
      if (platform == 'web') {
        print('🌐 Ejecutando Flutter Web...');
        onOutput?.call('🌐 Iniciando compilación para Web...');
        onOutput?.call('💡 Web no requiere dispositivo físico o emulador');
        
        // Usar web-server si se solicita (no abre navegador externo), de lo contrario usar chrome
        final webDevice = useWebServer ? 'web-server' : 'chrome';
        final List<String> args = ['run', '-d', webDevice];
        if (mode == 'release') {
          args.add('--release');
        } else if (mode == 'profile') {
          args.add('--profile');
        }
        // debug es el modo por defecto, no necesita flag
        if (webRenderer != null && webRenderer.isNotEmpty) {
          args.add('--web-renderer=$webRenderer');
        }
        
        if (useWebServer) {
          print('🌐 Usando web-server (NO abrirá navegador externo)');
          onOutput?.call('🌐 Usando web-server (servidor interno sin navegador externo)');
        } else {
          print('🌐 Usando Chrome (abrirá navegador externo)');
          onOutput?.call('🌐 Usando Chrome (abrirá navegador en ventana separada)');
        }
        
        print('🌐 Comando: flutter ${args.join(' ')}');
        print('🌐 Working Directory: $projectPath');
        final process = await Process.start(
          'flutter',
          args,
          workingDirectory: projectPath,
          runInShell: true,
        );
        
        return _processFlutterOutput(process, result, onOutput, onError);
      }
      
      // Para otras plataformas, verificar dispositivos disponibles
      final devices = await getAvailableDevices();
      
      if (devices.isEmpty) {
        onOutput?.call('⚠️ No se detectaron dispositivos disponibles');
        onOutput?.call('💡 Ejecuta "flutter devices" en la terminal para verificar');
      } else {
        onOutput?.call('📱 Dispositivos disponibles: ${devices.length}');
        for (var device in devices) {
          final devicePlatform = device['platform'] ?? device['category'] ?? 'desconocida';
          onOutput?.call('  - ${device['name']} (${device['id']}) - $devicePlatform');
        }
      }
      
      // Encontrar el ID del dispositivo correcto
      String? deviceId = await findDeviceId(platform);
      
      if (deviceId == null) {
        final errorMsg = '❌ No se encontró dispositivo disponible para la plataforma "$platform".\n'
            '📱 Dispositivos detectados (${devices.length}):\n'
            '${devices.isEmpty ? "   - Ningún dispositivo disponible\n" : devices.map((d) => "   - ${d['name']} (ID: ${d['id']}, Plataforma: ${d['platform'] ?? d['category'] ?? "desconocida"})\n").join("")}'
            '💡 Soluciones posibles:\n'
            '   1. Verifica que el emulador/dispositivo esté abierto y listo\n'
            '   2. Ejecuta "flutter devices" en la terminal para verificar\n'
            '   3. Para Android: Abre Android Studio > AVD Manager y inicia un emulador\n'
            '   4. Para iOS: Abre el Simulador desde Xcode\n'
            '   5. Para macOS: Asegúrate de tener Xcode instalado';
        result.errors.add(errorMsg);
        result.success = false;
        result.endTime = DateTime.now(); // Establecer endTime para indicar que el proceso terminó
        result.phase = 'error'; // Marcar como error
        // Enviar el mensaje de error también a onOutput para que se muestre en Debug Console
        onOutput?.call(errorMsg);
        onError?.call(CompilationError(
          file: '',
          line: 0,
          column: 0,
          type: 'error',
          message: errorMsg,
        ));
        print('❌ ABORTANDO: No se encontró dispositivo para "$platform". NO se ejecutará flutter run.');
        return result;
      }
      
      print('🚀 Iniciando flutter run en $deviceId ($platform, $mode)...');
      print('🚀 Working Directory: $projectPath');
      onOutput?.call('🚀 Ejecutando en dispositivo: $deviceId');
      onOutput?.call('📁 Proyecto: $projectPath');

      final process = await Process.start(
        'flutter',
        ['run', '-d', deviceId, '--$mode'],
        workingDirectory: projectPath,
        runInShell: true,
      );
      
      return _processFlutterOutput(process, result, onOutput, onError);

    } catch (e) {
      print('❌ Error al ejecutar flutter run: $e');
      result.endTime = DateTime.now();
      result.success = false;
      result.errors.add('Error: $e');
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
    final outputController = StreamController<String>();
    final errorController = StreamController<String>();

    // Capturar stdout
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      outputController.add(line);
      result.output.add(line);
      onOutput?.call(line);

      // Analizar línea para detectar errores o warnings
      _analyzeLine(line, result);
    });

    // Capturar stderr (errores reales de compilación)
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      errorController.add(line);
      result.errors.add(line);
      
      // También agregar a output para que se muestre en Debug Console
      outputController.add(line);
      result.output.add(line);
      onOutput?.call(line);

      // Parsear error
      final error = _parseError(line);
      if (error != null) {
        result.compilationErrors.add(error);
        onError?.call(error);
      }
    });

    // Esperar a que termine
    final exitCode = await process.exitCode;
    result.exitCode = exitCode;
    result.endTime = DateTime.now();
    result.success = exitCode == 0;

    print(result.success 
        ? '✅ Compilación exitosa' 
        : '❌ Compilación fallida (exit code: $exitCode)');

    return result;
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

  /// Analiza errores de compilación de Dart/Flutter
  static Future<List<CompilationError>> analyzeCompilationErrors(
    String projectPath,
  ) async {
    final errors = <CompilationError>[];

    try {
      print('🔍 Analizando errores de compilación...');

      final process = await Process.run(
        'flutter',
        ['analyze'],
        workingDirectory: projectPath,
      );

      final output = process.stdout.toString();
      final lines = output.split('\n');

      for (var line in lines) {
        final error = _parseError(line);
        if (error != null) {
          errors.add(error);
        }
      }

      print('📊 Encontrados ${errors.length} errores/warnings');
    } catch (e) {
      print('❌ Error al analizar: $e');
    }

    return errors;
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
