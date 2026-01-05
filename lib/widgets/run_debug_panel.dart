import 'package:flutter/material.dart';
import '../services/run_debug_service.dart';
import 'cursor_theme.dart';

class RunDebugPanel extends StatefulWidget {
  const RunDebugPanel({super.key});

  @override
  State<RunDebugPanel> createState() => _RunDebugPanelState();
}

class _RunDebugPanelState extends State<RunDebugPanel> {
  String _selectedMode = 'debug';
  String _selectedPlatform = 'macos';
  String _output = '';
  bool _isRunning = false;
  bool _isFlutterAvailable = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _checkFlutter();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkFlutter() async {
    final available = await RunDebugService.isFlutterAvailable();
    setState(() {
      _isFlutterAvailable = available;
    });
  }

  Future<void> _runProject() async {
    if (_isRunning) {
      await RunDebugService.stop();
      setState(() {
        _isRunning = false;
        _output = '';
      });
      return;
    }

    setState(() {
      _isRunning = true;
      _output = 'Iniciando ejecución...\n';
    });

    try {
      final result = await RunDebugService.runFlutterProject(
        mode: _selectedMode,
        platform: _selectedPlatform,
        onOutput: (output) {
          setState(() {
            _output += output;
            // Auto-scroll al final
            Future.delayed(const Duration(milliseconds: 100), () {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            });
          });
        },
        onError: (error) {
          setState(() {
            _output += 'ERROR: $error\n';
            // Auto-scroll al final
            Future.delayed(const Duration(milliseconds: 100), () {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            });
          });
        },
      );

      // El proceso se ejecuta en background, no esperamos que termine aquí
    } catch (e) {
      setState(() {
        _isRunning = false;
        _output += '❌ Error: $e\n';
      });
    }
  }

  Future<void> _stopProject() async {
    await RunDebugService.stop();
    setState(() {
      _isRunning = false;
      _output += '\n⏹️ Proceso detenido\n';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        border: Border(
          left: BorderSide(color: CursorTheme.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CursorTheme.background,
              border: Border(
                bottom: BorderSide(color: CursorTheme.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.play_circle, 
                  color: CursorTheme.primary, 
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Run and Debug',
                  style: TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // Selector de plataforma
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: CursorTheme.background,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: CursorTheme.border),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedPlatform,
                    underline: const SizedBox(),
                    iconSize: 14,
                    style: const TextStyle(
                      color: CursorTheme.textPrimary,
                      fontSize: 11,
                    ),
                    dropdownColor: CursorTheme.surface,
                    items: const [
                      DropdownMenuItem(
                        value: 'macos',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.desktop_mac, size: 14),
                            SizedBox(width: 4),
                            Text('macOS'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'ios',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.phone_iphone, size: 14),
                            SizedBox(width: 4),
                            Text('iOS'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'android',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.phone_android, size: 14),
                            SizedBox(width: 4),
                            Text('Android'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'web',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.web, size: 14),
                            SizedBox(width: 4),
                            Text('Web'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: _isRunning
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _selectedPlatform = value;
                              });
                            }
                          },
                  ),
                ),
                const SizedBox(width: 8),
                // Selector de modo
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: CursorTheme.background,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: CursorTheme.border),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedMode,
                    underline: const SizedBox(),
                    iconSize: 14,
                    style: const TextStyle(
                      color: CursorTheme.textPrimary,
                      fontSize: 11,
                    ),
                    dropdownColor: CursorTheme.surface,
                    items: const [
                      DropdownMenuItem(
                        value: 'debug',
                        child: Text('Debug'),
                      ),
                      DropdownMenuItem(
                        value: 'profile',
                        child: Text('Profile'),
                      ),
                      DropdownMenuItem(
                        value: 'release',
                        child: Text('Release'),
                      ),
                    ],
                    onChanged: _isRunning
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _selectedMode = value;
                              });
                            }
                          },
                  ),
                ),
              ],
            ),
          ),

          // Controles
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: CursorTheme.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isFlutterAvailable ? _runProject : null,
                  icon: Icon(
                    _isRunning ? Icons.stop : Icons.play_arrow,
                    size: 16,
                  ),
                  label: Text(_isRunning ? 'Detener' : 'Ejecutar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRunning 
                        ? Colors.red 
                        : CursorTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_isRunning)
                  ElevatedButton.icon(
                    onPressed: _stopProject,
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('Forzar Detención'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  ),
                const Spacer(),
                if (!_isFlutterAvailable)
                  const Text(
                    'Flutter no disponible',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),

          // Output
          Expanded(
            child: Container(
              color: CursorTheme.background,
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  _output.isEmpty 
                      ? 'Output aparecerá aquí...\n\nPresiona "Ejecutar" para iniciar el proyecto.'
                      : _output,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: CursorTheme.codeText,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

