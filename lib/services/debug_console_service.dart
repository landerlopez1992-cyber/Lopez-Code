import 'package:flutter/foundation.dart';

import '../models/problem_item.dart';
import 'advanced_debugging_service.dart';
import 'platform_service.dart';
import 'project_platform_support.dart';
import 'run_debug_service.dart';
import 'project_service.dart';

/// Servicio compartido para el Debug Console Panel
/// Permite que ChatScreen actualice el panel en MultiChatScreen
class DebugConsoleService extends ChangeNotifier {
  static final DebugConsoleService _instance = DebugConsoleService._internal();
  factory DebugConsoleService() => _instance;
  DebugConsoleService._internal();

  double _panelHeight = 250.0; // Visible por defecto con altura 250
  List<String> _output = [];
  List<String> _debugConsole = [];
  List<ProblemItem> _problemItems = [];
  bool _isVisible = true; // Visible por defecto
  bool _isRunning = false;
  bool _isAnalyzing = false;
  String? _appUrl; // URL de la app ejecutándose (para web)
  String? _vmServiceUri; // URI del VM Service (para Inspector nativo)
  double _compilationProgress = 0.0; // Progreso de compilación (0.0 - 1.0)
  String _compilationStatus = ''; // Estado actual de compilación
  /// 0 = Problems, 1 = Output, 2 = Debug Console, 3 = Terminal
  int _preferredConsoleTab = 0;

  /// Feedback visual estilo Cursor en Hot Reload / Hot Restart.
  /// `idle` | `reloading` | `restarting`
  String _hotAction = 'idle';

  double get panelHeight => _panelHeight;
  List<String> get output => List.unmodifiable(_output);
  List<String> get debugConsole => List.unmodifiable(_debugConsole);

  /// Problemas estructurados de `flutter analyze` (fuente de verdad del panel).
  List<ProblemItem> get problemItems => List.unmodifiable(_problemItems);

  /// Compatibilidad: representación textual de cada [ProblemItem].
  List<String> get problems =>
      _problemItems.map((p) => p.toString()).toList(growable: false);

  bool get isVisible => _isVisible;
  bool get isRunning => _isRunning;
  bool get isAnalyzing => _isAnalyzing;
  String? get appUrl => _appUrl;
  String? get vmServiceUri => _vmServiceUri;
  double get compilationProgress => _compilationProgress;
  String get compilationStatus => _compilationStatus;
  int get preferredConsoleTab => _preferredConsoleTab;

  /// `idle` | `reloading` | `restarting`
  String get hotAction => _hotAction;
  bool get isHotReloading => _hotAction == 'reloading';
  bool get isHotRestarting => _hotAction == 'restarting';
  bool get isHotBusy => _hotAction != 'idle';

  void _setHotAction(String action) {
    if (_hotAction == action) return;
    _hotAction = action;
    notifyListeners();
  }

  /// Abre el panel inferior y selecciona la pestaña Output (logs en vivo).
  void showOutputTab() {
    _preferredConsoleTab = 1;
    if (_panelHeight == 0) {
      _panelHeight = 250.0;
      _isVisible = true;
    }
    notifyListeners();
  }

  void setPreferredConsoleTab(int index) {
    final clamped = index.clamp(0, 3);
    if (_preferredConsoleTab != clamped) {
      _preferredConsoleTab = clamped;
      notifyListeners();
    }
  }

  /// Abre el panel inferior y selecciona la pestaña Terminal.
  void showTerminalTab() {
    _preferredConsoleTab = 3;
    if (_panelHeight == 0) {
      _panelHeight = 250.0;
      _isVisible = true;
    }
    notifyListeners();
  }

  /// Parsea una línea de `flutter run` y actualiza fase/progreso en vivo.
  void updateProgressFromFlutterLine(String line) {
    final lower = line.toLowerCase();
    double progress = _compilationProgress;
    String status = _compilationStatus;

    if (lower.contains('resolving dependencies') ||
        lower.contains('got dependencies') ||
        lower.contains('downloading packages') ||
        lower.contains('running "flutter pub get"')) {
      status = 'Resolviendo dependencias...';
      progress = progress < 0.2 ? 0.2 : progress;
    } else if (lower.contains('running gradle') ||
        lower.contains('running xcode build') ||
        lower.contains('running pod install') ||
        lower.contains('cocoapods')) {
      status = 'Configurando nativo...';
      progress = progress < 0.35 ? 0.35 : progress;
    } else if (lower.contains('compiling') ||
        lower.contains('building flutter') ||
        lower.contains('building') ||
        lower.contains('assembling') ||
        lower.contains('lib/main.dart') ||
        lower.contains('kernel snapshot')) {
      status = 'Compilando aplicación...';
      progress = progress < 0.55 ? 0.55 : progress;
    } else if (lower.contains('installing') ||
        lower.contains('launching') ||
        lower.contains('syncing files to device') ||
        lower.contains('waiting for') ||
        lower.contains('starting application')) {
      status = 'Instalando y lanzando...';
      progress = progress < 0.85 ? 0.85 : progress;
    } else if (lower.contains('flutter run key commands') ||
        lower.contains('an observatory debugger') ||
        (lower.contains('devtools') && lower.contains('available at')) ||
        lower.contains('application finished launching') ||
        lower.contains('is being served at') ||
        lower.contains('serving at http')) {
      final p = PlatformService().selectedPlatform.toLowerCase();
      if (lower.contains('served at') || lower.contains('serving at')) {
        status = p == 'web'
            ? 'Aplicación web ejecutándose'
            : '${ProjectPlatformSupport.humanLabel(p)} ejecutándose';
      } else {
        status = 'Aplicación ejecutándose';
      }
      progress = 1.0;
    } else if (RegExp(r'(\d+)%').hasMatch(line)) {
      final percentMatch = RegExp(r'(\d+)%').firstMatch(line);
      if (percentMatch != null) {
        final percent = int.parse(percentMatch.group(1)!);
        progress = percent / 100.0;
        status = 'Compilando aplicación... $percent%';
      }
    } else {
      return;
    }

    setCompilationProgress(progress, status);
  }

  void setPanelHeight(double height) {
    _panelHeight = height;
    _isVisible = height > 0;
    notifyListeners();
  }

  /// Output = log crudo completo del proceso (flutter run / build / deploy).
  void addOutput(String line) {
    _output.add(line);
    notifyListeners();
  }

  /// Debug Console = trazas en vivo de la app + eventos del IDE
  /// (print/debugPrint, excepciones, hot reload, tips, URLs).
  void addDebugConsole(String line) {
    _debugConsole.add(line);
    notifyListeners();
  }

  /// Ruido típico del toolchain Flutter (queda en Output, no en Debug).
  bool _isFlutterToolNoise(String lower) {
    const noise = [
      'resolving dependencies',
      'got dependencies',
      'downloading packages',
      'running "flutter pub get"',
      'running gradle',
      'running xcode build',
      'running pod install',
      'cocoapods',
      'waiting for connection from debug service',
      'syncing files to device',
      'installing and launching',
      'flutter run key commands',
      'an observatory debugger and profiler',
      'a dart vm service on',
      'the flutter devtools debugger',
      'to hot reload',
      'to hot restart',
      'to quit',
      'to detach',
      'trying to load',
      'changing current working directory',
      'no supported devices connected',
      'checking for wireless devices',
    ];
    for (final n in noise) {
      if (lower.contains(n)) return true;
    }
    // Líneas de progreso de compilación del tool
    if (lower.contains('compiling') &&
        (lower.contains('for ') || lower.contains('lib/'))) {
      return true;
    }
    if (lower.startsWith('✓ built') || lower.startsWith('√ built')) {
      return true;
    }
    return false;
  }

  /// Línea de runtime de la app (print, stack, framework, carga en vivo).
  bool _isAppRuntimeTrace(String line, String lower) {
    if (lower.contains('exception') ||
        lower.contains('error:') ||
        lower.contains('failed') ||
        lower.contains('unhandled') ||
        lower.contains('overflowed') ||
        lower.contains('renderflex') ||
        lower.contains('another exception was thrown') ||
        lower.contains('the following assertion was thrown')) {
      return true;
    }
    // Stack frames Dart
    if (RegExp(r'^\s*#\d+\s+').hasMatch(line) ||
        lower.contains('package:flutter/') ||
        lower.contains('dart:')) {
      return true;
    }
    // Logs Android / iOS / web del isolate
    if (lower.contains('i/flutter') ||
        lower.contains('e/flutter') ||
        lower.contains('w/flutter') ||
        lower.contains('d/flutter') ||
        lower.startsWith('flutter:')) {
      return true;
    }
    // Hot reload/restart resultado (útil en Debug)
    if (lower.contains('performing hot reload') ||
        lower.contains('performing hot restart') ||
        lower.contains('reloaded ') ||
        lower.contains('restarted application')) {
      return true;
    }
    // URL de la app lista (punto de “ya corre”)
    if (lower.contains('is being served at') ||
        RegExp(r'https?://(?:localhost|127\.0\.0\.1):\d+').hasMatch(line)) {
      return true;
    }
    // Cualquier print de la app: si NO es ruido del tool, es traza de runtime
    if (!_isFlutterToolNoise(lower) && line.trim().isNotEmpty) {
      // Filtra banners ANSI casi vacíos / separadores del tool
      final stripped = line.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '').trim();
      if (stripped.isEmpty || stripped == '─' || stripped.startsWith('═══')) {
        return false;
      }
      // Tras app running, la mayoría de líneas son prints / logs de negocio
      if (_isRunning || _compilationProgress >= 0.95) {
        return true;
      }
    }
    return false;
  }

  /// Access log de `python -m http.server` (una línea por GET).
  bool _isStaticHttpAccessLog(String lower) {
    return (lower.contains('"get ') ||
            lower.contains('"post ') ||
            lower.contains('"head ') ||
            lower.contains('"put ')) &&
        (lower.contains(' http/') ||
            lower.contains('" 200') ||
            lower.contains('" 304') ||
            lower.contains('" 404'));
  }

  /// Enruta stdout/stderr del proceso Flutter:
  /// • siempre → Output (log crudo)
  /// • trazas de runtime / errores → Debug Console (en vivo)
  void ingestProcessLine(String line) {
    final t = line.trimRight();
    if (t.isEmpty) return;
    final lower = t.toLowerCase();

    // Access log de http.server: silenciar por completo.
    // Si llegan al Output → notifyListeners → rebuild del Preview → otro GET /
    // → temblequeo / scroll roto.
    if (_isStaticHttpAccessLog(lower)) {
      return;
    }

    _output.add(t);

    if (_isAppRuntimeTrace(t, lower)) {
      _debugConsole.add(t);
    }
    notifyListeners();
  }

  /// Varias líneas / chunk de stdout|stderr del proceso.
  void ingestProcessChunk(String chunk) {
    var any = false;
    for (final line in chunk.split('\n')) {
      final t = line.trimRight();
      if (t.isEmpty) continue;
      final lower = t.toLowerCase();
      if (_isStaticHttpAccessLog(lower)) {
        continue;
      }
      _output.add(t);
      if (_isAppRuntimeTrace(t, lower)) {
        _debugConsole.add(t);
      }
      any = true;
    }
    if (any) notifyListeners();
  }

  /// Agrega un problema estructurado (preferido).
  void addProblemItem(ProblemItem item) {
    _problemItems.add(item);
    notifyListeners();
  }

  /// Compatibilidad con callers que aún pasan un String (p. ej. logs).
  /// No usa regex de consola como fuente primaria: crea un ítem info/error simple.
  void addProblem(String problem) {
    final parsed = _tryParseProblemString(problem);
    _problemItems.add(parsed);
    notifyListeners();
  }

  void setProblemItems(List<ProblemItem> items) {
    _problemItems = List<ProblemItem>.from(items);
    notifyListeners();
  }

  void clearOutput() {
    _output.clear();
    notifyListeners();
  }

  void clearDebugConsole() {
    _debugConsole.clear();
    notifyListeners();
  }

  void clearProblems() {
    _problemItems.clear();
    notifyListeners();
  }

  void clearAll() {
    _output.clear();
    _debugConsole.clear();
    _problemItems.clear();
    _vmServiceUri = null;
    notifyListeners();
  }

  void openPanel() {
    if (_panelHeight == 0) {
      _panelHeight = 200.0;
      _isVisible = true;
      notifyListeners();
    }
  }

  void closePanel() {
    _panelHeight = 0.0;
    _isVisible = false;
    notifyListeners();
  }

  void togglePanel() {
    if (_panelHeight > 0) {
      closePanel();
    } else {
      openPanel();
    }
  }

  void setRunning(bool running) {
    if (_isRunning != running) {
      _isRunning = running;
      notifyListeners();
    }
  }

  /// Marca el proceso como terminado (usado por stop / exit real).
  void notifyProcessEnded() {
    _isRunning = false;
    _appUrl = null;
    _vmServiceUri = null;
    _compilationProgress = 0.0;
    _compilationStatus = '';
    addDebugConsole('🛑 Proceso Flutter terminado');
    notifyListeners();
  }

  /// Detiene el `flutter run` real (SIGTERM → SIGKILL) y notifica a la UI.
  /// El Stop del toolbar / ChatScreen debe llamar esto (además de limpiar
  /// cualquier Process local) para evitar zombies.
  Future<void> requestStop() async {
    addDebugConsole('🛑 Deteniendo proceso Flutter...');
    await AdvancedDebuggingService.stop();
    await RunDebugService.stop();
    notifyProcessEnded();
  }

  /// Contador: el PhoneEmulator recarga el WebView cuando sube.
  int _previewReloadNonce = 0;
  int get previewReloadNonce => _previewReloadNonce;

  /// `false` = soft (⚡ Hot Reload / reload página).
  /// `true`  = hard (🔄 Hot Restart / cache-bust + URL raíz).
  bool _previewReloadHard = true;
  bool get previewReloadHard => _previewReloadHard;

  DateTime? _lastPreviewBumpAt;

  /// Fuerza reload del Preview (tras Hot Reload/Restart / edit del agente).
  /// Debounce: evita tormentas de recarga si el agente edita en ráfaga.
  /// [force] salta el debounce (rayo ⚡ / Hot Restart / botón manual).
  /// [hard] true = reinicio fuerte (cache-bust); false = soft reload.
  void bumpPreviewReload({bool force = false, bool hard = true}) {
    final now = DateTime.now();
    if (!force &&
        _lastPreviewBumpAt != null &&
        now.difference(_lastPreviewBumpAt!) <
            const Duration(milliseconds: 800)) {
      return;
    }
    _lastPreviewBumpAt = now;
    _previewReloadHard = hard;
    _previewReloadNonce++;
    notifyListeners();
  }

  /// ⚡ Hot Reload: aplica cambios de código sin reiniciar el estado.
  /// Flutter → stdin `r`. HTML → soft reload del WebView (misma URL).
  Future<bool> requestHotReload() async {
    _setHotAction('reloading');
    try {
      final ok = await AdvancedDebuggingService.hotReload() ||
          await RunDebugService.hotReload();
      final hasPreview = _appUrl != null && _appUrl!.isNotEmpty;
      if (ok) {
        addDebugConsole('⚡ Hot Reload (código en caliente)');
        if (hasPreview) {
          await Future<void>.delayed(const Duration(milliseconds: 450));
          bumpPreviewReload(force: true, hard: false);
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return true;
      }
      // HTML / preview sin flutter run: soft refresh (no reinicio total).
      if (hasPreview && _isRunning) {
        bumpPreviewReload(force: true, hard: false);
        addDebugConsole(
          '⚡ Hot Reload → Preview soft refresh (HTML)',
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
        return true;
      }
      addDebugConsole(
        '⚠️ Hot Reload: no hay proceso Flutter ni Preview activo',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return false;
    } finally {
      _setHotAction('idle');
    }
  }

  /// 🔄 Hot Restart: reinicia la app / Preview desde cero (estado limpio).
  /// Flutter → stdin `R`. HTML → hard reload con cache-bust a la URL raíz.
  Future<bool> requestHotRestart() async {
    _setHotAction('restarting');
    try {
      final ok = await AdvancedDebuggingService.hotRestart() ||
          await RunDebugService.hotRestart();
      final hasPreview = _appUrl != null && _appUrl!.isNotEmpty;
      if (ok) {
        addDebugConsole('🔄 Hot Restart (reinicio completo)');
        if (hasPreview) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          bumpPreviewReload(force: true, hard: true);
        }
        await Future<void>.delayed(const Duration(milliseconds: 350));
        return true;
      }
      if (hasPreview && _isRunning) {
        bumpPreviewReload(force: true, hard: true);
        addDebugConsole(
          '🔄 Hot Restart → Preview hard reload (HTML, estado limpio)',
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
        return true;
      }
      addDebugConsole(
        '⚠️ Hot Restart: no hay proceso Flutter ni Preview activo',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return false;
    } finally {
      _setHotAction('idle');
    }
  }

  /// ¿URL válida para el Preview (app Flutter), no DevTools / VM Service?
  static bool isPreviewAppUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final u = url.trim().toLowerCase();
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return false;
    if (u.startsWith('ws://') || u.startsWith('wss://')) return false;
    if (u.contains('devtools')) return false;
    if (u.contains('/dds')) return false;
    // VM Service / Observatory suelen llevar ?uri= o path /vm
    if (u.contains('uri=http') || u.contains('uri=ws')) return false;
    if (u.contains('/vm/') || u.endsWith('/vm')) return false;
    return true;
  }

  void setAppUrl(String? url) {
    // Nunca meter DevTools en el Preview (pantalla "Connected app").
    if (url != null && !isPreviewAppUrl(url)) {
      print('🚫 setAppUrl rechazada (no es app Preview): $url');
      // Guardar como VM Service si parece serlo.
      if (url.toLowerCase().contains('uri=') ||
          url.toLowerCase().contains('devtools') ||
          url.toLowerCase().startsWith('ws')) {
        setVmServiceUri(url);
      }
      return;
    }
    if (_appUrl != url) {
      print('🌐 DebugConsoleService.setAppUrl: "$_appUrl" -> "$url"');
      _appUrl = url;
      notifyListeners();
      print('✅ URL actualizada, notificando listeners...');
    }
  }

  void setVmServiceUri(String? uri) {
    if (_vmServiceUri != uri) {
      print('🧩 DebugConsoleService.setVmServiceUri: "$_vmServiceUri" -> "$uri"');
      _vmServiceUri = uri;
      notifyListeners();
    }
  }

  void setCompilationProgress(double progress, String status) {
    if (_compilationProgress != progress || _compilationStatus != status) {
      _compilationProgress = progress.clamp(0.0, 1.0);
      _compilationStatus = status;
      notifyListeners();
    }
  }

  void resetCompilationProgress() {
    _compilationProgress = 0.0;
    _compilationStatus = '';
    notifyListeners();
  }

  /// Ejecuta `flutter analyze` real y actualiza el panel Problems.
  Future<List<ProblemItem>> refreshProblemsFromAnalyze([String? projectPath]) async {
    final path = projectPath ?? await ProjectService.getProjectPath();
    if (path == null || path.isEmpty) {
      addDebugConsole('⚠️ No hay proyecto para flutter analyze');
      return [];
    }

    _isAnalyzing = true;
    notifyListeners();
    addDebugConsole('🔍 Ejecutando flutter analyze...');

    try {
      final items = await AdvancedDebuggingService.runFlutterAnalyze(path);
      _problemItems = List<ProblemItem>.from(items);
      addDebugConsole('📊 Problems actualizados: ${items.length}');
      openPanel();
      notifyListeners();
      return items;
    } catch (e) {
      addDebugConsole('❌ Error en flutter analyze: $e');
      return [];
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  ProblemItem _tryParseProblemString(String problem) {
    final classic = RegExp(
      r'^(.+?):(\d+):(\d+):\s*(error|warning|info):\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(problem);
    if (classic != null) {
      return ProblemItem.fromSeverityString(
        filePath: classic.group(1)!,
        line: int.tryParse(classic.group(2)!) ?? 0,
        column: int.tryParse(classic.group(3)!) ?? 0,
        severity: classic.group(4)!,
        message: classic.group(5)!.trim(),
      );
    }

    final lower = problem.toLowerCase();
    final severity = lower.contains('error')
        ? ProblemSeverity.error
        : lower.contains('warning')
            ? ProblemSeverity.warning
            : ProblemSeverity.info;

    return ProblemItem(
      filePath: '',
      line: 0,
      column: 0,
      severity: severity,
      message: problem,
    );
  }
}
