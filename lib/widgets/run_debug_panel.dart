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
  String _output = '';
  bool _isRunning = false;
  bool _isFlutterAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkFlutter();
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
        onOutput: (output) {
          setState(() {
            _output += output;
          });
        },
        onError: (error) {
          setState(() {
            _output += 'ERROR: $error\n';
          });
        },
      );

      setState(() {
        _isRunning = false;
        if (result['success'] == true) {
          _output += '\n✅ Ejecución completada exitosamente\n';
        } else {
          _output += '\n❌ Ejecución falló con código: ${result['exitCode']}\n';
        }
      });
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
                // Selector de modo
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: CursorTheme.background,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: CursorTheme.border),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedMode,
                    underline: const SizedBox(),
                    iconSize: 16,
                    style: const TextStyle(
                      color: CursorTheme.textPrimary,
                      fontSize: 12,
                    ),
                    dropdownColor: CursorTheme.surface,
                    items: const [
                      DropdownMenuItem(
                        value: 'debug',
                        child: Text('Debug'),
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

