import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

class DevToolsService {
  static Process? _devToolsProcess;
  static String? _lastDevToolsUrl;
  static Completer<String?>? _pendingLaunch;

  static Future<String?> openInspector({
    required String vmServiceUri,
    void Function(String line)? onLog,
  }) async {
    final trimmedUri = vmServiceUri.trim();
    if (trimmedUri.isEmpty) {
      onLog?.call('⚠️ VM Service URI vacío. No se puede abrir DevTools.');
      return null;
    }

    if (_lastDevToolsUrl != null) {
      await _launch(_lastDevToolsUrl!, onLog: onLog);
      return _lastDevToolsUrl;
    }

    if (_pendingLaunch != null) {
      return _pendingLaunch!.future;
    }

    _pendingLaunch = Completer<String?>();

    try {
      onLog?.call('🧩 Iniciando DevTools con VM Service: $trimmedUri');
      _devToolsProcess ??= await Process.start(
        'dart',
        [
          'devtools',
          '--vm-uri',
          trimmedUri,
          '--try-ports',
          '1',
        ],
        runInShell: true,
      );

      _devToolsProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        onLog?.call('🧩 DevTools: $line');
        final urlMatch =
            RegExp(r'Serving DevTools at:\s*(http://[^\s]+)').firstMatch(line);
        if (urlMatch != null) {
          final url = urlMatch.group(1)!.trim();
          _lastDevToolsUrl = url;
          _launch(url, onLog: onLog);
          if (!(_pendingLaunch?.isCompleted ?? true)) {
            _pendingLaunch?.complete(url);
            _pendingLaunch = null;
          }
        }
      });

      _devToolsProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        onLog?.call('⚠️ DevTools stderr: $line');
      });
    } catch (e) {
      onLog?.call('❌ Error iniciando DevTools: $e');
      if (!(_pendingLaunch?.isCompleted ?? true)) {
        _pendingLaunch?.complete(null);
        _pendingLaunch = null;
      }
      return null;
    }

    Future.delayed(const Duration(seconds: 6), () {
      if (!(_pendingLaunch?.isCompleted ?? true)) {
        _pendingLaunch?.complete(null);
        _pendingLaunch = null;
      }
    });

    return _pendingLaunch!.future;
  }

  static Future<void> _launch(String url, {void Function(String line)? onLog}) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        onLog?.call('✅ DevTools abierto en navegador: $url');
      } else {
        onLog?.call('❌ No se pudo abrir DevTools en navegador: $url');
      }
    } catch (e) {
      onLog?.call('❌ Error al abrir DevTools: $e');
    }
  }
}
