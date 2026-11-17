import 'dart:async';
import 'dart:io';

import 'debug_console_service.dart';
import 'project_type_detector.dart';
import 'run_debug_service.dart';

/// Preview de diseño para proyectos HTML estáticos.
///
/// Vive al abrir el proyecto. NO marca Run/Debug (`isRunning`).
class HtmlPreviewService {
  HtmlPreviewService._();
  static final HtmlPreviewService instance = HtmlPreviewService._();

  Process? _process;
  String? _projectPath;
  String? _baseUrl;
  int? _port;
  bool _starting = false;

  String? get projectPath => _projectPath;
  String? get baseUrl => _baseUrl;
  bool get isLive {
    final p = _process;
    if (_baseUrl == null || _baseUrl!.isEmpty || p == null) return false;
    // Si el proceso ya salió, no está vivo.
    try {
      // ignore: unnecessary_null_comparison
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isHtmlProject(String path) async {
    if (path.isEmpty) return false;
    final type = await ProjectTypeDetector.detectProjectType(path);
    return type == ProjectType.html;
  }

  Future<bool> ensureRunning(
    String projectPath, {
    String? page,
    bool quiet = false,
  }) async {
    if (projectPath.isEmpty) return false;

    if (_starting) {
      for (var i = 0; i < 60 && _starting; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (_baseUrl != null && _projectPath == projectPath) {
        await showPage(page);
        return true;
      }
    }

    final type = await ProjectTypeDetector.detectProjectType(projectPath);
    if (type != ProjectType.html) return false;

    final debug = DebugConsoleService();

    if (_process != null &&
        _baseUrl != null &&
        _projectPath == projectPath &&
        await _portOpen(_port ?? 8000)) {
      if (!debug.hasPreviewUrl || !debug.isDesignPreview) {
        reattach();
      }
      await showPage(page);
      return true;
    }

    _starting = true;
    try {
      await stop(clearDebugUrl: false);

      final runCommand = await ProjectTypeDetector.getRunCommand(
        projectPath,
        ProjectType.html,
        isDebug: false,
      );

      var port = 8000;
      for (final arg in runCommand.args) {
        if (RegExp(r'^\d+$').hasMatch(arg)) {
          port = int.tryParse(arg) ?? 8000;
          break;
        }
      }

      Process? process;
      Object? lastError;
      for (final python in const ['python3', 'python']) {
        try {
          process = await Process.start(
            python,
            [
              '-m',
              'http.server',
              '$port',
              '--bind',
              '127.0.0.1',
            ],
            workingDirectory: runCommand.workingDirectory,
            runInShell: false,
          );
          break;
        } catch (e) {
          lastError = e;
          process = null;
        }
      }
      if (process == null) {
        throw StateError('No se pudo iniciar python: $lastError');
      }

      _process = process;
      _projectPath = projectPath;
      _port = port;
      _baseUrl = 'http://127.0.0.1:$port';

      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      unawaited(process.exitCode.then((code) {
        if (identical(_process, process)) {
          _process = null;
          print('⚠️ HtmlPreviewServer salió (code=$code)');
        }
      }));

      // Esperar a que el puerto acepte conexiones.
      var ready = false;
      for (var i = 0; i < 25; i++) {
        await Future.delayed(const Duration(milliseconds: 80));
        if (_process == null) break;
        if (await _portOpen(port)) {
          ready = true;
          break;
        }
      }
      if (!ready) {
        print('⚠️ HtmlPreview: puerto $port no respondió a tiempo');
      }

      final url = _composeUrl(page);
      debug.setDesignPreview(true, url: url);
      debug.setAppUrl(url);
      // No tocar isRunning: Run/Stop lo controla el toolbar.
      if (!quiet) {
        debug.addOutput('🌐 Preview de diseño → $url');
      }
      return true;
    } catch (e) {
      print('⚠️ HtmlPreviewService.ensureRunning: $e');
      debug.addOutput('❌ Preview de diseño falló: $e');
      return false;
    } finally {
      _starting = false;
    }
  }

  void reattach() {
    if (_baseUrl == null || _baseUrl!.isEmpty) return;
    final debug = DebugConsoleService();
    debug.setDesignPreview(true, url: _baseUrl);
    debug.setAppUrl(_baseUrl);
  }

  Future<void> showPage(String? page) async {
    if (_baseUrl == null) return;
    final url = _composeUrl(page);
    final debug = DebugConsoleService();
    final changed = debug.appUrl != url;
    debug.setDesignPreview(true, url: url);
    debug.setAppUrl(url);
    if (changed) {
      debug.bumpPreviewReload(force: true, hard: true);
    } else {
      debug.bumpPreviewReload(force: true, hard: false);
    }
  }

  Future<void> showHtmlFile(String absolutePath) async {
    final root = _projectPath;
    if (root == null || _baseUrl == null) return;
    final normRoot = root.replaceAll('\\', '/');
    final normPath = absolutePath.replaceAll('\\', '/');
    if (!normPath.startsWith(normRoot)) return;
    if (!normPath.toLowerCase().endsWith('.html')) return;
    var rel = normPath.substring(normRoot.length);
    if (rel.startsWith('/')) rel = rel.substring(1);
    await showPage(rel.isEmpty ? null : rel);
  }

  Future<void> refresh({bool hard = false}) async {
    if (_baseUrl == null && _projectPath != null) {
      await ensureRunning(_projectPath!);
      return;
    }
    if (_baseUrl == null) return;
    // Si el proceso murió, rearrancar.
    if (_process == null || !await _portOpen(_port ?? 8000)) {
      final path = _projectPath;
      if (path != null) {
        await ensureRunning(path);
        return;
      }
    }
    DebugConsoleService().bumpPreviewReload(force: true, hard: hard);
  }

  String _composeUrl(String? page) {
    final base = _baseUrl ?? '';
    if (page == null || page.isEmpty || page == '/' || page == 'index.html') {
      return base.endsWith('/') ? base : '$base/';
    }
    final clean = page.startsWith('/') ? page.substring(1) : page;
    return '$base/$clean';
  }

  Future<bool> _portOpen(int port) async {
    try {
      final s = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(milliseconds: 120),
      );
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop({bool clearDebugUrl = true}) async {
    final p = _process;
    _process = null;
    if (p != null) {
      try {
        p.kill(ProcessSignal.sigterm);
        await p.exitCode.timeout(
          const Duration(milliseconds: 700),
          onTimeout: () {
            try {
              p.kill(ProcessSignal.sigkill);
            } catch (_) {}
            return -1;
          },
        );
      } catch (_) {
        try {
          p.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    }
    final port = _port ?? 8000;
    try {
      await ProjectTypeDetector.killProcessOnPort(port);
    } catch (_) {}

    _baseUrl = null;
    _port = null;
    if (clearDebugUrl) {
      _projectPath = null;
      final debug = DebugConsoleService();
      debug.setDesignPreview(false);
      // No borrar URL/running si hay un flutter run activo (cambio HTML→Flutter).
      final flutterLive = RunDebugService.isRunning();
      if (!flutterLive) {
        debug.setAppUrl(null);
        debug.setRunning(false);
        debug.setCompilationProgress(0.0, '');
      }
    }
  }
}
