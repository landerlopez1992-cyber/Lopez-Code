import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/file_service.dart';
import '../services/project_service.dart';
import 'cursor_theme.dart';

class CodeEditorPanel extends StatefulWidget {
  final String? filePath;
  final String? initialContent;
  final Function(String)? onSave;
  final Function()? onClose;

  const CodeEditorPanel({
    super.key,
    this.filePath,
    this.initialContent,
    this.onSave,
    this.onClose,
  });

  @override
  State<CodeEditorPanel> createState() => _CodeEditorPanelState();
}

class _CodeEditorPanelState extends State<CodeEditorPanel> {
  late TextEditingController _codeController;
  bool _isModified = false;
  String? _currentFilePath;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentFilePath = widget.filePath;
    _codeController = TextEditingController(text: widget.initialContent ?? '');
    _codeController.addListener(() {
      if (!_isModified) {
        setState(() {
          _isModified = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _saveFile() async {
    if (_currentFilePath == null || _currentFilePath!.isEmpty) {
      _showSaveAsDialog();
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Verificar que el archivo está en el proyecto
      final isInProject = await ProjectService.isPathInProject(_currentFilePath!);
      if (!isInProject) {
        throw Exception('El archivo debe estar dentro del proyecto seleccionado');
      }

      await FileService.writeFile(_currentFilePath!, _codeController.text);
      
      setState(() {
        _isModified = false;
        _isSaving = false;
      });

      widget.onSave?.call(_currentFilePath!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Archivo guardado: ${_currentFilePath!.split('/').last}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSaveAsDialog() {
    final TextEditingController pathController = TextEditingController(
      text: _currentFilePath ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guardar archivo como'),
        content: TextField(
          controller: pathController,
          decoration: const InputDecoration(
            labelText: 'Ruta del archivo',
            hintText: '/ruta/al/archivo.ext',
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final path = pathController.text.trim();
              if (path.isNotEmpty) {
                setState(() {
                  _currentFilePath = path;
                });
                Navigator.of(context).pop();
                await _saveFile();
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _codeController.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Código copiado al portapapeles'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _selectAll() {
    _codeController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _codeController.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CursorTheme.editorBackground,
      child: Column(
        children: [
          // Barra de herramientas
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: CursorTheme.surface,
              border: Border(
                bottom: BorderSide(color: CursorTheme.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                // Nombre del archivo
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.code,
                        size: 16,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _currentFilePath != null
                              ? _currentFilePath!.split('/').last
                              : 'Nuevo archivo',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_isModified)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
                
                // Botones de acción
                IconButton(
                  icon: const Icon(Icons.select_all, size: 18),
                  color: CursorTheme.textSecondary,
                  onPressed: _selectAll,
                  tooltip: 'Seleccionar todo',
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  color: CursorTheme.textSecondary,
                  onPressed: _copyToClipboard,
                  tooltip: 'Copiar',
                ),
                if (_isSaving)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(CursorTheme.textSecondary),
                      ),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.save, size: 18),
                    color: _isModified ? Colors.green : CursorTheme.textSecondary,
                    onPressed: _isModified ? _saveFile : null,
                    tooltip: 'Guardar',
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: CursorTheme.textSecondary,
                  onPressed: widget.onClose,
                  tooltip: 'Cerrar',
                ),
              ],
            ),
          ),

          // Editor de código
          Expanded(
            child: Container(
              color: CursorTheme.editorBackground,
              child: TextField(
                controller: _codeController,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: CursorTheme.codeText,
                  height: 1.6,
                  letterSpacing: 0.2,
                ),
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                  hintText: 'Escribe tu código aquí...',
                  hintStyle: TextStyle(
                    color: CursorTheme.textDisabled,
                    fontFamily: 'monospace',
                  ),
                ),
                textAlignVertical: TextAlignVertical.top,
              ),
            ),
          ),

          // Barra de estado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: CursorTheme.primary,
              border: Border(
                top: BorderSide(color: CursorTheme.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                if (_currentFilePath != null) ...[
                  Icon(Icons.insert_drive_file, size: 12, color: Colors.white70),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _currentFilePath!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  'Líneas: ${_codeController.text.split('\n').length} | '
                  'Caracteres: ${_codeController.text.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

