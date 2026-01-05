import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/file_service.dart';
import 'cursor_theme.dart';

enum DeviceType {
  mobile,
  tablet,
  web,
}

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
  DeviceType _deviceType = DeviceType.mobile;
  Offset _position = const Offset(0, 0);
  double _scale = 1.0;
  Offset _lastPanUpdate = Offset.zero;

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
    final screenSize = MediaQuery.of(context).size;
    
    return Container(
      width: screenSize.width,
      height: screenSize.height,
      color: Colors.black.withOpacity(0.95),
      child: Center(
        child: Transform.scale(
          scale: _scale,
          child: Transform.translate(
            offset: _position,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: screenSize.width * 0.95,
                maxHeight: screenSize.height * 0.95,
              ),
              decoration: BoxDecoration(
                color: CursorTheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header movible
                  GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _position += details.delta;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CursorTheme.explorerBackground,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.phone_android, color: CursorTheme.primary, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Vista Previa: ${widget.filePath.split('/').last}',
                              style: const TextStyle(
                                color: CursorTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          // Selector de dispositivo
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: CursorTheme.surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: CursorTheme.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildDeviceButton(DeviceType.mobile, Icons.phone_android),
                                _buildDeviceButton(DeviceType.tablet, Icons.tablet),
                                _buildDeviceButton(DeviceType.web, Icons.laptop),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Botones de zoom
                          IconButton(
                            icon: const Icon(Icons.zoom_out, size: 16),
                            color: CursorTheme.textSecondary,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () {
                              setState(() {
                                _scale = (_scale - 0.1).clamp(0.5, 2.0);
                              });
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.zoom_in, size: 16),
                            color: CursorTheme.textSecondary,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () {
                              setState(() {
                                _scale = (_scale + 0.1).clamp(0.5, 2.0);
                              });
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            color: CursorTheme.textSecondary,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Content
                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: _getDeviceWidth(),
                        maxHeight: _getDeviceHeight(),
                      ),
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Error al cargar archivo',
                                        style: TextStyle(color: CursorTheme.textPrimary, fontSize: 16),
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceButton(DeviceType type, IconData icon) {
    final isSelected = _deviceType == type;
    return InkWell(
      onTap: () {
        setState(() {
          _deviceType = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isSelected ? CursorTheme.primary.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isSelected ? CursorTheme.primary : CursorTheme.textSecondary,
        ),
      ),
    );
  }

  double _getDeviceWidth() {
    switch (_deviceType) {
      case DeviceType.mobile:
        return 375;
      case DeviceType.tablet:
        return 768;
      case DeviceType.web:
        return 1200;
    }
  }

  double _getDeviceHeight() {
    switch (_deviceType) {
      case DeviceType.mobile:
        return 812;
      case DeviceType.tablet:
        return 1024;
      case DeviceType.web:
        return 800;
    }
  }

  Widget _buildPreview() {
    final deviceWidth = _getDeviceWidth();
    final deviceHeight = _getDeviceHeight();
    
    // Frame de dispositivo
    return Center(
      child: Container(
        width: deviceWidth,
        height: deviceHeight,
        decoration: BoxDecoration(
          color: _deviceType == DeviceType.mobile 
              ? const Color(0xFF1E1E1E)
              : const Color(0xFF2D2D2D),
          borderRadius: _deviceType == DeviceType.mobile
              ? BorderRadius.circular(40)
              : BorderRadius.circular(12),
          border: Border.all(
            color: _deviceType == DeviceType.mobile 
                ? Colors.grey[800]! 
                : Colors.grey[700]!,
            width: _deviceType == DeviceType.mobile ? 12 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              spreadRadius: 10,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: _deviceType == DeviceType.mobile
              ? BorderRadius.circular(28)
              : BorderRadius.circular(10),
          child: Container(
            decoration: const BoxDecoration(
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

    // Analizar el código para extraer información básica y construir preview visual
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

    // Construir preview visual basado en el código
    return Container(
      color: Colors.white,
      child: content.contains('Scaffold')
          ? _buildScaffoldPreview(content)
          : content.contains('Container')
              ? _buildContainerPreview(content)
              : content.contains('Column')
                  ? _buildColumnPreview(content)
                  : content.contains('Row')
                      ? _buildRowPreview(content)
                      : _buildDefaultPreview(content),
    );
  }

  Widget _buildScaffoldPreview(String content) {
    // Detectar si tiene AppBar
    final hasAppBar = content.contains('appBar:');
    String? appBarTitle;
    // Buscar título de forma simple
    final titleStart = content.indexOf('title:');
    if (titleStart != -1) {
      final titleSection = content.substring(titleStart, titleStart + 100);
      final quoteStart = titleSection.indexOf("'");
      if (quoteStart == -1) {
        final doubleQuoteStart = titleSection.indexOf('"');
        if (doubleQuoteStart != -1) {
          final quoteEnd = titleSection.indexOf('"', doubleQuoteStart + 1);
          if (quoteEnd != -1) {
            appBarTitle = titleSection.substring(doubleQuoteStart + 1, quoteEnd);
          }
        }
      } else {
        final quoteEnd = titleSection.indexOf("'", quoteStart + 1);
        if (quoteEnd != -1) {
          appBarTitle = titleSection.substring(quoteStart + 1, quoteEnd);
        }
      }
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
        mainAxisSize: MainAxisSize.min,
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
          // Mostrar código fuente del archivo como preview
          Container(
            constraints: BoxConstraints(maxHeight: 500),
            padding: const EdgeInsets.all(16),
            color: backgroundColor,
            child: SingleChildScrollView(
              child: SelectableText(
                _fileContent ?? '',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualPreview(String content) {
    // Intentar extraer widgets y texto del código para mostrar una preview visual
    final widgets = <Widget>[];
    
    // Buscar Text widgets
    final textPattern = RegExp(r'Text\([\'"]([^\'"]+)[\'"]\)');
    final textMatches = textPattern.allMatches(content);
    for (var match in textMatches) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            match.group(1) ?? '',
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
        ),
      );
    }
    
    // Buscar ElevatedButton/TextButton
    final buttonPattern = RegExp(r'(ElevatedButton|TextButton)\([^)]*child:\s*Text\([\'"]([^\'"]+)[\'"]\)');
    final buttonMatches = buttonPattern.allMatches(content);
    for (var match in buttonMatches) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ElevatedButton(
            onPressed: () {},
            child: Text(match.group(2) ?? 'Button'),
          ),
        ),
      );
    }
    
    // Buscar AppBar title
    final appBarTitlePattern = RegExp(r'appBar:.*?title:\s*Text\([\'"]([^\'"]+)[\'"]\)');
    final appBarMatch = appBarTitlePattern.firstMatch(content);
    
    if (widgets.isEmpty && appBarMatch == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.phone_android, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              widget.filePath.split('/').last,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Vista previa visual',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widgets,
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
      child: _buildVisualPreview(content),
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

