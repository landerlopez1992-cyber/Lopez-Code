import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../services/project_service.dart';
import 'cursor_theme.dart';

/// Terminal integrada (PTY + xterm) para el panel inferior de Voryxel Code.
/// Sesión persistente en [workingDirectory] (projectPath).
class IntegratedTerminalPanel extends StatefulWidget {
  final String? workingDirectory;

  const IntegratedTerminalPanel({
    super.key,
    this.workingDirectory,
  });

  @override
  State<IntegratedTerminalPanel> createState() =>
      IntegratedTerminalPanelState();
}

class IntegratedTerminalPanelState extends State<IntegratedTerminalPanel> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  Pty? _pty;
  StreamSubscription<String>? _outputSub;
  String? _cwd;
  String? _error;
  bool _starting = false;

  static const _theme = TerminalTheme(
    cursor: CursorTheme.primary,
    selection: Color(0x59007ACC),
    foreground: Color(0xFFCCCCCC),
    background: CursorTheme.surface,
    black: Color(0xFF000000),
    red: Color(0xFFCD3131),
    green: Color(0xFF0DBC79),
    yellow: Color(0xFFE5E510),
    blue: Color(0xFF2472C8),
    magenta: Color(0xFFBC3FBC),
    cyan: Color(0xFF11A8CD),
    white: Color(0xFFE5E5E5),
    brightBlack: Color(0xFF666666),
    brightRed: Color(0xFFF14C4C),
    brightGreen: Color(0xFF23D18B),
    brightYellow: Color(0xFFF5F543),
    brightBlue: Color(0xFF3B8EEA),
    brightMagenta: Color(0xFFD670D6),
    brightCyan: Color(0xFF29B8DB),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _terminalController = TerminalController();
    _terminal.onOutput = (data) {
      _pty?.write(utf8.encode(data));
    };
    _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      _pty?.resize(height, width);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _startShell());
  }

  @override
  void didUpdateWidget(covariant IntegratedTerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.workingDirectory != oldWidget.workingDirectory &&
        widget.workingDirectory != null &&
        widget.workingDirectory != _cwd) {
      killSession();
      _startShell();
    }
  }

  @override
  void dispose() {
    _outputSub?.cancel();
    try {
      _pty?.kill();
    } catch (_) {}
    super.dispose();
  }

  Future<String> _resolveCwd() async {
    final fromWidget = widget.workingDirectory?.trim();
    if (fromWidget != null && fromWidget.isNotEmpty) {
      return fromWidget;
    }
    return (await ProjectService.getProjectPath()) ?? Directory.current.path;
  }

  /// Entorno completo del host para que PATH/flutter/git sean reales (como Cursor).
  Map<String, String> _shellEnvironment() {
    final env = Map<String, String>.from(Platform.environment);
    env['TERM'] = 'xterm-256color';
    env['COLORTERM'] = 'truecolor';
    // Asegura binarios típicos de macOS si PATH viene recortado por el launcher.
    final extras = <String>[
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '${Platform.environment['HOME'] ?? ''}/flutter/bin',
      '${Platform.environment['HOME'] ?? ''}/development/flutter/bin',
      '${Platform.environment['HOME'] ?? ''}/fvm/default/bin',
    ].where((p) => p.isNotEmpty).toList();
    final path = env['PATH'] ?? '/usr/bin:/bin:/usr/sbin:/sbin';
    final merged = <String>{...extras, ...path.split(':')};
    env['PATH'] = merged.join(':');
    return env;
  }

  Future<void> _startShell() async {
    if (_starting) return;
    _starting = true;
    setState(() => _error = null);

    try {
      final cwd = await _resolveCwd();
      _cwd = cwd;

      // Shell de login interactivo real → historial ↑/↓, tab-complete, colores.
      final shell = Platform.isWindows
          ? (Platform.environment['COMSPEC'] ?? 'cmd.exe')
          : (Platform.environment['SHELL'] ?? '/bin/zsh');
      final args = Platform.isWindows ? <String>[] : <String>['-l', '-i'];

      final rows = _terminal.viewHeight > 0 ? _terminal.viewHeight : 24;
      final cols = _terminal.viewWidth > 0 ? _terminal.viewWidth : 100;

      final pty = Pty.start(
        shell,
        arguments: args,
        workingDirectory: cwd,
        rows: rows,
        columns: cols,
        environment: _shellEnvironment(),
      );

      _pty = pty;
      await _outputSub?.cancel();
      _outputSub = pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_terminal.write);

      pty.exitCode.then((code) {
        if (!mounted) return;
        _terminal.write('\r\n[proceso terminado · exit $code]\r\n');
        setState(() {});
      });

      final user = Platform.environment['USER'] ?? 'user';
      final host = Platform.localHostname.split('.').first;
      final project = cwd.split(Platform.pathSeparator).last;
      _terminal.write(
        '\x1b[90mVoryxel Code Terminal · $user@$host · $project %\x1b[0m\r\n',
      );
    } catch (e) {
      _error = 'No se pudo iniciar la terminal: $e';
      _terminal.write('Error: $e\r\n');
    } finally {
      _starting = false;
      if (mounted) setState(() {});
    }
  }

  void clearScreen() {
    _terminal.buffer.clear();
    _terminal.buffer.setCursor(0, 0);
    _terminal.write('\x1b[2J\x1b[H');
  }

  void killSession() {
    try {
      _pty?.kill(ProcessSignal.sigkill);
    } catch (_) {}
    _outputSub?.cancel();
    _outputSub = null;
    _pty = null;
  }

  Future<void> restartSession() async {
    killSession();
    _terminal.buffer.clear();
    _terminal.buffer.setCursor(0, 0);
    await _startShell();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            color: CursorTheme.background,
            border: Border(
              bottom: BorderSide(color: CursorTheme.border, width: 1),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 14, color: CursorTheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _cwd != null
                      ? _cwd!.replaceAll(RegExp(r'^/Users/[^/]+'), '~')
                      : 'Terminal',
                  style: const TextStyle(
                    fontSize: 11,
                    color: CursorTheme.textSecondary,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 14),
                color: CursorTheme.textSecondary,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 24),
                tooltip: 'Reiniciar shell',
                onPressed: restartSession,
              ),
              IconButton(
                icon: const Icon(Icons.clear_all, size: 14),
                color: CursorTheme.textSecondary,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 24),
                tooltip: 'Clear',
                onPressed: clearScreen,
              ),
              IconButton(
                icon: const Icon(Icons.stop_circle_outlined, size: 14),
                color: const Color(0xFFE57373),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 24),
                tooltip: 'Kill',
                onPressed: () {
                  killSession();
                  _terminal.write('\r\n[killed]\r\n');
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        Expanded(
          child: TerminalView(
            _terminal,
            controller: _terminalController,
            autofocus: true,
            backgroundOpacity: 0,
            theme: _theme,
            textStyle: const TerminalStyle(
              fontSize: 12,
              fontFamily: 'Menlo',
              fontFamilyFallback: ['monospace', 'Courier'],
            ),
            padding: const EdgeInsets.all(8),
          ),
        ),
      ],
    );
  }
}
