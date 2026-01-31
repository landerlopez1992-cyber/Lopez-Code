import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/project_service.dart';
import 'cursor_theme.dart';

class ProjectExplorer extends StatefulWidget {
  final Function(String)? onFileSelected;
  final Function(String)? onFileDoubleClick;
  final Function(String)? onFileDelete;
  final Function(String)? onFileViewCode;
  final Function(String)? onFileViewScreen;
  final Function(String)? onFileCopy;

  const ProjectExplorer({
    super.key,
    this.onFileSelected,
    this.onFileDoubleClick,
    this.onFileDelete,
    this.onFileViewCode,
    this.onFileViewScreen,
    this.onFileCopy,
  });

  @override
  State<ProjectExplorer> createState() => _ProjectExplorerState();
}

class _ProjectExplorerState extends State<ProjectExplorer> {
  Map<String, dynamic>? _projectTree;
  String? _projectPath;
  String? _selectedPath;
  bool _isLoading = true;
  Set<String> _expandedPaths = {};
  String? _lastLoadedPath; // Para detectar cambios de proyecto

  @override
  void initState() {
    super.initState();
    _loadProject();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Verificar si el proyecto cambió
    _checkProjectChange();
  }

  Future<void> _checkProjectChange() async {
    try {
      final currentPath = await ProjectService.getProjectPath();
      final normalizedCurrent = currentPath?.replaceAll('\\', '/') ?? '';
      final normalizedLast = _lastLoadedPath?.replaceAll('\\', '/') ?? '';
      
      if (normalizedCurrent != normalizedLast && normalizedCurrent.isNotEmpty) {
        print('🔄 ProjectExplorer: Proyecto cambió. Recargando...');
        print('   Anterior: $_lastLoadedPath');
        print('   Nuevo: $currentPath');
        await _loadProject();
      }
    } catch (e) {
      print('❌ Error al verificar cambio de proyecto: $e');
    }
  }

  Future<void> _loadProject() async {
    setState(() {
      _isLoading = true;
      _projectTree = null; // Limpiar árbol anterior
      _expandedPaths.clear(); // Limpiar expansiones
    });

    try {
      final path = await ProjectService.getProjectPath();
      print('📂 ProjectExplorer: Cargando proyecto desde: $path');
      
      if (path != null && path.isNotEmpty) {
        // Verificar que el directorio existe
        final dir = Directory(path);
        if (!await dir.exists()) {
          print('❌ El directorio del proyecto no existe: $path');
          setState(() {
            _isLoading = false;
            _projectPath = null;
            _lastLoadedPath = null;
          });
          return;
        }

        _projectPath = path;
        _lastLoadedPath = path;
        
        print('📂 Construyendo estructura del proyecto...');
        final tree = await ProjectService.getProjectStructure();
        print('🌳 Árbol del proyecto cargado: ${tree.keys}');
        print('🌳 Tiene hijos: ${tree['children'] != null ? (tree['children'] as List).length : 0}');
        
        if (tree.isEmpty) {
          print('⚠️ El árbol del proyecto está vacío');
        } else {
          final children = tree['children'] as List<dynamic>?;
          if (children != null && children.isNotEmpty) {
            print('📁 Número de hijos en raíz: ${children.length}');
            print('📁 Primeros hijos: ${children.take(5).map((c) => c['name']).toList()}');
          } else {
            print('⚠️ No hay hijos en el árbol del proyecto');
          }
        }
        
        setState(() {
          _projectTree = tree;
          _isLoading = false;
          // Expandir raíz por defecto para mostrar contenido
          if (tree.isNotEmpty) {
            final rootPath = tree['path'] as String;
            _expandedPaths.add(rootPath);
            print('✅ Raíz expandida: $rootPath');
            
            // También expandir subdirectorios principales si existen
            final children = tree['children'] as List<dynamic>?;
            if (children != null && children.isNotEmpty) {
              print('📁 Expandir ${children.length} directorios principales...');
              // Expandir los primeros 10 directorios principales para no sobrecargar
              int expandedCount = 0;
              for (var child in children) {
                if (expandedCount >= 10) break; // Limitar a 10 para rendimiento
                final childMap = child as Map<String, dynamic>;
                if (childMap['type'] == 'directory') {
                  _expandedPaths.add(childMap['path'] as String);
                  expandedCount++;
                  print('📂 Directorio expandido: ${childMap['name']}');
                }
              }
              print('✅ Total de directorios expandidos: $expandedCount');
            } else {
              print('⚠️ No hay hijos en el árbol del proyecto o está vacío');
            }
          } else {
            print('⚠️ El árbol del proyecto está vacío');
          }
        });
        
        // Forzar rebuild después de un pequeño delay para asegurar que se muestre
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          setState(() {
            // Trigger rebuild para mostrar el árbol
          });
        }
        
        print('✅ ProjectExplorer: Proyecto cargado exitosamente');
      } else {
        print('⚠️ No hay proyecto seleccionado');
        setState(() {
          _isLoading = false;
          _projectPath = null;
          _lastLoadedPath = null;
        });
      }
    } catch (e, stackTrace) {
      print('❌ Error al cargar proyecto: $e');
      print('❌ Stack trace: $stackTrace');
      setState(() {
        _isLoading = false;
        _projectPath = null;
        _lastLoadedPath = null;
      });
    }
  }

  void _toggleExpand(String path) {
    setState(() {
      if (_expandedPaths.contains(path)) {
        _expandedPaths.remove(path);
      } else {
        _expandedPaths.add(path);
      }
    });
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'dart':
        return Icons.code;
      case 'js':
      case 'jsx':
        return Icons.javascript;
      case 'ts':
      case 'tsx':
        return Icons.type_specimen;
      case 'html':
        return Icons.html;
      case 'css':
        return Icons.style;
      case 'json':
        return Icons.data_object;
      case 'yaml':
      case 'yml':
        return Icons.settings;
      case 'md':
        return Icons.description;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
        return Icons.image;
      case 'pdf':
        return Icons.picture_as_pdf;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'dart':
        return Colors.blue;
      case 'js':
      case 'jsx':
        return Colors.yellow;
      case 'ts':
      case 'tsx':
        return Colors.blueAccent;
      case 'html':
        return Colors.orange;
      case 'css':
        return Colors.blue;
      case 'json':
        return Colors.green;
      case 'yaml':
      case 'yml':
        return Colors.purple;
      case 'md':
        return Colors.grey;
      default:
        return Colors.white70;
    }
  }

  Widget _buildTreeItem(Map<String, dynamic> item, int level) {
    final name = item['name'] as String;
    final path = item['path'] as String;
    final type = item['type'] as String;
    final isExpanded = _expandedPaths.contains(path);
    final isSelected = _selectedPath == path;
    final isDirectory = type == 'directory';
    final children = item['children'] as List<dynamic>?;
    
    // Debug para directorios
    if (isDirectory && level == 0) {
      print('ROOT - expandido: $isExpanded, hijos: ${children?.length ?? 0}');
      if (children != null && children.isNotEmpty) {
        print('Primeros hijos: ${children.take(3).map((c) => c['name']).toList()}');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onSecondaryTap: !isDirectory ? () {
            _showContextMenu(context, path, name);
          } : null,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (isDirectory) {
                  _toggleExpand(path);
                } else {
                  setState(() {
                    _selectedPath = path;
                  });
                  widget.onFileSelected?.call(path);
                }
              },
              onDoubleTap: () {
                if (!isDirectory) {
                  widget.onFileDoubleClick?.call(path);
                }
              },
              child: Container(
                padding: EdgeInsets.only(
                  left: level * 18.0 + 10, // Más espacio como Cursor
                  right: 10,
                  top: 3,
                  bottom: 3,
                ),
                color: isSelected
                    ? CursorTheme.explorerItemSelected
                    : Colors.transparent,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) {
                    if (!isSelected) {
                      // Efecto hover sutil
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: isSelected
                          ? CursorTheme.explorerItemSelected
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Icono de expandir/colapsar para directorios
                        if (isDirectory) ...[
                          Icon(
                            isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                            size: 14, // Más pequeño como Cursor
                            color: CursorTheme.textSecondary.withOpacity(0.8),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            isExpanded ? Icons.folder_open : Icons.folder,
                            size: 16,
                            color: const Color(0xFFFFB800), // Amarillo más suave como Cursor
                          ),
                        ] else ...[
                          const SizedBox(width: 20), // Espacio para alinear con directorios
                          Icon(
                            _getFileIcon(name),
                            size: 16,
                            color: _getFileColor(name).withOpacity(0.9),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              color: isSelected 
                                  ? CursorTheme.textPrimary 
                                  : CursorTheme.textSecondary,
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                              height: 1.4, // Mejor interlineado
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (isDirectory && isExpanded && children != null && children.isNotEmpty) ...[
          for (var child in children) ...[
            _buildTreeItem(child as Map<String, dynamic>, level + 1),
          ],
        ],
      ],
    );
  }

  void _showContextMenu(BuildContext context, String filePath, String fileName) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: CursorTheme.surface,
      items: [
        PopupMenuItem<String>(
          value: 'view_code',
          child: Row(
            children: [
              const Icon(Icons.code, size: 18, color: CursorTheme.textPrimary),
              const SizedBox(width: 8),
              const Text('Ver código', style: TextStyle(color: CursorTheme.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'view_screen',
          child: Row(
            children: [
              const Icon(Icons.phone_android, size: 18, color: CursorTheme.textPrimary),
              const SizedBox(width: 8),
              const Text('Ver pantalla', style: TextStyle(color: CursorTheme.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 18, color: CursorTheme.textPrimary),
              const SizedBox(width: 8),
              const Text('Copiar ruta', style: TextStyle(color: CursorTheme.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              const SizedBox(width: 8),
              const Text('Eliminar', style: TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        switch (value) {
          case 'view_code':
            widget.onFileViewCode?.call(filePath);
            break;
          case 'view_screen':
            widget.onFileViewScreen?.call(filePath);
            break;
          case 'copy':
            widget.onFileCopy?.call(filePath);
            break;
          case 'delete':
            _confirmDelete(context, filePath, fileName);
            break;
        }
      }
    });
  }

  void _confirmDelete(BuildContext context, String filePath, String fileName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CursorTheme.surface,
        title: const Text('Eliminar archivo', style: TextStyle(color: CursorTheme.textPrimary)),
        content: Text('¿Estás seguro de que deseas eliminar "$fileName"?\n\nEsta acción no se puede deshacer.', 
          style: const TextStyle(color: CursorTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('No', style: TextStyle(color: CursorTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onFileDelete?.call(filePath);
            },
            child: const Text('Sí', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_projectTree == null || _projectTree!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.folder_off,
              size: 48,
              color: CursorTheme.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              'No hay proyecto seleccionado',
              style: TextStyle(color: CursorTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () async {
                // Esto se manejará desde la pantalla principal
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Seleccionar Proyecto'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: CursorTheme.surface,
            border: Border(
              bottom: BorderSide(color: CursorTheme.border, width: 1),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder, size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _projectPath!.split('/').last,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                color: Colors.white70,
                onPressed: _loadProject,
                tooltip: 'Actualizar',
              ),
            ],
          ),
        ),
        // Tree
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _buildTreeItem(_projectTree!, 0),
            ],
          ),
        ),
      ],
    );
  }
}

