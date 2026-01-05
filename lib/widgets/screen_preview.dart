import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/file_service.dart';
import 'cursor_theme.dart';

class ScreenPreview extends StatefulWidget {
  final String filePath;

  const ScreenPreview({super.key, required this.filePath});

  @override
  State<ScreenPreview> createState() => _ScreenPreviewState();
}

class _ScreenPreviewState extends State<ScreenPreview> {
  String? _fileContent;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final content = await FileService.readFile(widget.filePath);
      setState(() {
        _fileContent = content;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: CursorTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CursorTheme.explorerBackground,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone_android, color: CursorTheme.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Vista Previa: ${widget.filePath.split('/').last}',
                      style: const TextStyle(
                        color: CursorTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: CursorTheme.textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(
                                'Error al cargar archivo',
                                style: const TextStyle(color: CursorTheme.textPrimary, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: const TextStyle(color: CursorTheme.textSecondary, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : _buildPreview(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    // Frame de dispositivo móvil
    return Center(
      child: Container(
        width: 400,
        height: 800,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.grey[800]!, width: 12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              spreadRadius: 10,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
            ),
            child: _buildScreenContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildScreenContent() {
    if (_fileContent == null) {
      return const Center(
        child: Text(
          'No se pudo cargar el contenido',
          style: TextStyle(color: Colors.black),
        ),
      );
    }

    // Analizar el código para extraer información básica
    final content = _fileContent!;
    
    // Detectar si es un StatelessWidget o StatefulWidget
    final isStateless = content.contains('StatelessWidget');
    final isStateful = content.contains('StatefulWidget');
    
    // Intentar extraer el nombre del widget
    String? widgetName;
    final nameMatch = RegExp(r'class\s+(\w+)\s+extends\s+(StatelessWidget|StatefulWidget)').firstMatch(content);
    if (nameMatch != null) {
      widgetName = nameMatch.group(1);
    }

    // Mostrar una vista previa simple basada en el código
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Información del widget
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widgetName ?? 'Widget',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isStateful ? 'StatefulWidget' : (isStateless ? 'StatelessWidget' : 'Widget'),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Vista previa básica - mostrar elementos comunes
            if (content.contains('Scaffold'))
              _buildScaffoldPreview(content)
            else if (content.contains('Container'))
              _buildContainerPreview(content)
            else if (content.contains('Column'))
              _buildColumnPreview(content)
            else if (content.contains('Row'))
              _buildRowPreview(content)
            else
              _buildDefaultPreview(content),
          ],
        ),
      ),
    );
  }

  Widget _buildScaffoldPreview(String content) {
    // Detectar si tiene AppBar
    final hasAppBar = content.contains('appBar:');
    String? appBarTitle;
    final titleMatch = RegExp(r'title:\s*Text\([\'"]?([^\'"]+)[\'"]?\)').firstMatch(content);
    if (titleMatch != null) {
      appBarTitle = titleMatch.group(1);
    }

    // Detectar color de fondo
    Color backgroundColor = Colors.white;
    if (content.contains('backgroundColor:')) {
      final bgMatch = RegExp(r'backgroundColor:\s*Colors\.(\w+)').firstMatch(content);
      if (bgMatch != null) {
        final colorName = bgMatch.group(1)?.toLowerCase() ?? 'white';
        backgroundColor = _getColorFromName(colorName);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasAppBar)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Text(
                appBarTitle ?? 'App Title',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vista Previa de Pantalla',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Este es el contenido de tu pantalla Flutter. Los elementos se renderizarán aquí.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContainerPreview(String content) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: const Text(
        'Container Widget',
        style: TextStyle(color: Colors.black87),
      ),
    );
  }

  Widget _buildColumnPreview(String content) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.blue[100],
            child: const Text('Elemento 1'),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.blue[100],
            child: const Text('Elemento 2'),
          ),
        ],
      ),
    );
  }

  Widget _buildRowPreview(String content) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.blue[100],
              child: const Text('Elemento 1'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.blue[100],
              child: const Text('Elemento 2'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultPreview(String content) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          const Icon(Icons.widgets, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Vista Previa',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Widget Flutter',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorFromName(String name) {
    switch (name) {
      case 'white':
        return Colors.white;
      case 'black':
        return Colors.black;
      case 'blue':
        return Colors.blue;
      case 'red':
        return Colors.red;
      case 'green':
        return Colors.green;
      case 'grey':
      case 'gray':
        return Colors.grey;
      default:
        return Colors.white;
    }
  }
}

