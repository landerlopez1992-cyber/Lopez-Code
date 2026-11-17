import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/project_service.dart';
import '../services/file_service.dart';
import '../services/agent_activity_service.dart';
import '../services/screen_discovery_service.dart';
import 'cursor_theme.dart';
import 'app_toast.dart';

class ProjectExplorer extends StatefulWidget {
  final Function(String)? onFileSelected;
  final Function(String)? onFileDoubleClick;
  final Function(String)? onFileDelete;
  final Function(String)? onFileViewCode;
  final Function(String)? onFileCopy;
  /// Clic en una pantalla detectada (estilo FlutterFlow).
  final Function(String path)? onScreenSelected;
  /// Callback opcional para pedir abrir/seleccionar proyecto (empty state).
  final VoidCallback? onRequestOpenProject;
  final String mode; // 'explorer' o 'search'
  /// Archivo que el agente está editando → resalte intermitente + expandir ruta.
  final String? agentActivePath;

  const ProjectExplorer({
    super.key,
    this.onFileSelected,
    this.onFileDoubleClick,
    this.onFileDelete,
    this.onFileViewCode,
    this.onFileCopy,
    this.onScreenSelected,
    this.onRequestOpenProject,
    this.mode = 'explorer',
    this.agentActivePath,
  });

  @override
  State<ProjectExplorer> createState() => _ProjectExplorerState();
}

class _ProjectExplorerState extends State<ProjectExplorer>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _projectTree;
  String? _projectPath;
  String? _selectedPath;
  bool _isLoading = true;
  Set<String> _expandedPaths = {};
  String? _lastLoadedPath; // Para detectar cambios de proyecto
  final GlobalKey _agentRowKey = GlobalKey();
  late final AnimationController _agentPulse;
  final AgentActivityService _agentActivity = AgentActivityService();

  // Estado para búsqueda (modo search legacy + filtro del explorador)
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _filterFocus = FocusNode();
  List<String> _searchResults = [];
  bool _isSearching = false;
  /// Filtro en vivo del árbol (nombres de archivo/carpeta).
  String _treeFilter = '';
  List<Map<String, String>> _treeFilterHits = [];
  bool _screensExpanded = true;
  bool _filesExpanded = true;

  @override
  void initState() {
    super.initState();
    _agentPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _agentActivity.addListener(_onAgentActivity);
    _loadProject();
    _searchController.addListener(_onSearchChanged);
    final initial = widget.agentActivePath ?? _agentActivity.activePath;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _revealAgentPath(initial);
      });
    }
  }

  @override
  void didUpdateWidget(covariant ProjectExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.agentActivePath != oldWidget.agentActivePath &&
        widget.agentActivePath != null) {
      _revealAgentPath(widget.agentActivePath!);
    }
  }

  void _onAgentActivity() {
    final path = _agentActivity.activePath;
    if (path == null || path.isEmpty) {
      if (_selectedPath != null && mounted) {
        setState(() {}); // quitar pulso
      }
      return;
    }
    _revealAgentPath(path);
  }
  
  @override
  void dispose() {
    _agentActivity.removeListener(_onAgentActivity);
    _agentPulse.dispose();
    _searchController.dispose();
    _filterFocus.dispose();
    super.dispose();
  }

  String _norm(String p) => p.replaceAll('\\', '/');

  bool _samePath(String? a, String? b) {
    if (a == null || b == null) return false;
    return _norm(a) == _norm(b);
  }

  /// Ruta activa del agente (prop o servicio global) — solo archivos reales.
  String? get _effectiveAgentPath {
    if (!_agentActivity.hasFileTarget &&
        (widget.agentActivePath == null || widget.agentActivePath!.isEmpty)) {
      return null;
    }
    return widget.agentActivePath ?? _agentActivity.activePath;
  }

  /// Match flexible: path exacto, sufijo relativo, o mismo basename.
  bool _matchesAgentFile(String treePath) {
    final agent = _effectiveAgentPath;
    if (agent == null || agent.isEmpty) return false;
    final a = _norm(agent);
    final t = _norm(treePath);
    if (a == t) return true;
    if (a.endsWith('/${t.split('/').last}') &&
        a.split('/').last == t.split('/').last) {
      // Mismo nombre de archivo
      final base = t.split('/').last;
      if (base.contains('.')) return a.endsWith('/$base') || a == base;
    }
    if (_projectPath != null) {
      final root = _norm(_projectPath!);
      if (t.startsWith('$root/')) {
        final rel = t.substring(root.length + 1);
        if (a.endsWith('/$rel') || a.endsWith(rel) || a == rel) return true;
      }
    }
    return false;
  }

  bool _isAgentAncestor(String dirPath) {
    final agent = _effectiveAgentPath;
    if (agent == null || agent.isEmpty) return false;
    final d = _norm(dirPath);
    final a = _norm(agent);
    if (a.startsWith('$d/')) return true;
    // Si el match es por basename, expandir carpetas del match en árbol
    final matched = _findTreePathMatchingAgent();
    if (matched != null && _norm(matched).startsWith('$d/')) return true;
    return false;
  }

  String? _findTreePathMatchingAgent() {
    final agent = _effectiveAgentPath;
    if (agent == null || _projectTree == null) return null;
    String? found;
    void walk(Map<String, dynamic> node) {
      if (found != null) return;
      final path = node['path'] as String?;
      final type = node['type'] as String?;
      if (path != null && type == 'file' && _matchesAgentFile(path)) {
        found = path;
        return;
      }
      final children = node['children'] as List<dynamic>?;
      if (children == null) return;
      for (final c in children) {
        walk(c as Map<String, dynamic>);
      }
    }
    walk(_projectTree!);
    return found;
  }

  /// Expande carpetas padre, selecciona el archivo y hace scroll hasta él.
  void _revealAgentPath(String absolutePath) {
    if (_projectPath == null) return;
    final root = _norm(_projectPath!);
    // Preferir el path real del árbol si el agente trae pub-cache / relativo.
    final treePath = _findTreePathMatchingAgent() ?? absolutePath;
    final target = _norm(treePath);
    final toExpand = <String>{root};
    if (target.startsWith('$root/')) {
      final relative = target.substring(root.length + 1);
      final parts = relative.split('/');
      var acc = root;
      for (var i = 0; i < parts.length - 1; i++) {
        acc = '$acc/${parts[i]}';
        toExpand.add(acc);
      }
    }
    if (!mounted) return;
    setState(() {
      _expandedPaths.addAll(toExpand);
      _selectedPath = treePath;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _agentRowKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 280),
          alignment: 0.35,
          curve: Curves.easeOut,
        );
      }
    });
  }
  
  void _onSearchChanged() {
    if (widget.mode == 'search') {
      _searchFiles(_searchController.text);
      return;
    }
    // Explorador: filtrar árbol por nombre de archivo/carpeta.
    final q = _searchController.text.trim();
    setState(() {
      _treeFilter = q;
      _treeFilterHits = q.isEmpty ? [] : _collectNameMatches(_projectTree, q);
    });
  }

  /// Recorre el árbol y devuelve coincidencias por nombre (archivo o carpeta).
  List<Map<String, String>> _collectNameMatches(
    Map<String, dynamic>? node,
    String query,
  ) {
    final out = <Map<String, String>>[];
    if (node == null || query.isEmpty) return out;
    final needle = query.toLowerCase();

    void walk(Map<String, dynamic> item) {
      final name = (item['name'] as String? ?? '');
      final path = (item['path'] as String? ?? '');
      final type = (item['type'] as String? ?? 'file');
      if (name.toLowerCase().contains(needle) ||
          path.toLowerCase().contains(needle)) {
        // No listar la raíz del proyecto como hit.
        if (path != _projectPath) {
          out.add({'name': name, 'path': path, 'type': type});
        }
      }
      final children = item['children'] as List<dynamic>?;
      if (children != null) {
        for (final child in children) {
          walk(child as Map<String, dynamic>);
        }
      }
    }

    walk(node);
    out.sort((a, b) {
      final aName = a['name']!.toLowerCase();
      final bName = b['name']!.toLowerCase();
      final aStarts = aName.startsWith(needle);
      final bStarts = bName.startsWith(needle);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return aName.compareTo(bName);
    });
    return out;
  }
  
  Future<void> _searchFiles(String query) async {
    if (query.isEmpty || _projectPath == null) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await FileService.searchFiles(_projectPath!, query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      print('❌ Error al buscar archivos: $e');
    }
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
    final isSelected = _samePath(_selectedPath, path);
    final isDirectory = type == 'directory';
    final children = item['children'] as List<dynamic>?;
    final isAgentFile = !isDirectory && _matchesAgentFile(path);
    final isAgentFolder = isDirectory && _isAgentAncestor(path);

    Widget row = GestureDetector(
      onSecondaryTap: () {
        _showContextMenu(
          context,
          path,
          name,
          isDirectory: isDirectory,
        );
      },
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
          child: AnimatedBuilder(
            animation: _agentPulse,
            builder: (context, child) {
              Color? bg;
              if (isAgentFile) {
                bg = Color.lerp(
                  const Color(0xFF1A3A5C),
                  CursorTheme.primary.withOpacity(0.55),
                  _agentPulse.value,
                );
              } else if (isAgentFolder) {
                bg = Color.lerp(
                  Colors.transparent,
                  CursorTheme.primary.withOpacity(0.28),
                  _agentPulse.value,
                );
              } else if (isSelected) {
                bg = CursorTheme.explorerItemSelected;
              }

              return Container(
                key: isAgentFile ? _agentRowKey : null,
                padding: EdgeInsets.only(
                  left: level * 18.0 + 10,
                  right: 10,
                  top: 3,
                  bottom: 3,
                ),
                color: bg ?? Colors.transparent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: isAgentFile
                        ? Border.all(
                            color: CursorTheme.primary.withOpacity(
                              0.35 + _agentPulse.value * 0.45,
                            ),
                            width: 1,
                          )
                        : null,
                  ),
                  child: child,
                ),
              );
            },
            child: Row(
              children: [
                if (isDirectory) ...[
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 14,
                    color: CursorTheme.textSecondary.withOpacity(0.8),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded || isAgentFolder
                        ? Icons.folder_open
                        : Icons.folder,
                    size: 16,
                    color: isAgentFolder
                        ? CursorTheme.primary
                        : const Color(0xFFFFB800),
                  ),
                ] else ...[
                  const SizedBox(width: 20),
                  Icon(
                    _getFileIcon(name),
                    size: 16,
                    color: isAgentFile
                        ? CursorTheme.primary
                        : _getFileColor(name).withOpacity(0.9),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: (isSelected || isAgentFile)
                          ? CursorTheme.textPrimary
                          : CursorTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: (isSelected || isAgentFile || isAgentFolder)
                          ? FontWeight.w600
                          : FontWeight.normal,
                      height: 1.4,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isAgentFile)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 12,
                      color: CursorTheme.primary.withOpacity(
                        0.5 + _agentPulse.value * 0.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        if (isDirectory &&
            isExpanded &&
            children != null &&
            children.isNotEmpty) ...[
          for (var child in children) ...[
            _buildTreeItem(child as Map<String, dynamic>, level + 1),
          ],
        ],
      ],
    );
  }

  void _showContextMenu(
    BuildContext context,
    String filePath,
    String fileName, {
    required bool isDirectory,
  }) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final parentDir = isDirectory
        ? filePath
        : (File(filePath).parent.path);

    showMenu<String>(
      context: context,
      position: position,
      color: CursorTheme.surface,
      items: [
        if (!isDirectory)
          const PopupMenuItem<String>(
            value: 'view_code',
            child: Row(
              children: [
                Icon(Icons.code, size: 18, color: CursorTheme.textPrimary),
                SizedBox(width: 8),
                Text(
                  'Abrir',
                  style: TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'new_file',
          child: Row(
            children: [
              const Icon(
                Icons.note_add_outlined,
                size: 18,
                color: CursorTheme.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                isDirectory ? 'Nuevo archivo aquí' : 'Nuevo archivo',
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'new_folder',
          child: Row(
            children: [
              const Icon(
                Icons.create_new_folder_outlined,
                size: 18,
                color: CursorTheme.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                isDirectory ? 'Nueva carpeta aquí' : 'Nueva carpeta',
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.drive_file_rename_outline,
                  size: 18, color: CursorTheme.textPrimary),
              SizedBox(width: 8),
              Text(
                'Renombrar',
                style: TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        if (!isDirectory)
          const PopupMenuItem<String>(
            value: 'duplicate',
            child: Row(
              children: [
                Icon(Icons.copy_all_outlined,
                    size: 18, color: CursorTheme.textPrimary),
                SizedBox(width: 8),
                Text(
                  'Duplicar',
                  style: TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuItem<String>(
          value: 'copy_path',
          child: Row(
            children: [
              Icon(Icons.link, size: 18, color: CursorTheme.textPrimary),
              SizedBox(width: 8),
              Text(
                'Copiar ruta',
                style: TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'Eliminar',
                style: TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ).then((value) async {
      if (value == null) return;
      switch (value) {
        case 'view_code':
          widget.onFileViewCode?.call(filePath);
          break;
        case 'new_file':
          await _createNewFile(parentDir);
          break;
        case 'new_folder':
          await _createNewFolder(parentDir);
          break;
        case 'rename':
          await _renameEntry(filePath, fileName, isDirectory: isDirectory);
          break;
        case 'duplicate':
          await _duplicateFile(filePath);
          break;
        case 'copy_path':
          await Clipboard.setData(ClipboardData(text: filePath));
          widget.onFileCopy?.call(filePath);
          if (mounted) {
            AppToast.info(context, 'Ruta copiada al portapapeles');
          }
          break;
        case 'delete':
          await _confirmAndDelete(
            filePath,
            fileName,
            isDirectory: isDirectory,
          );
          break;
      }
    });
  }

  Future<String?> _promptName({
    required String title,
    required String label,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CursorTheme.surface,
        title: Text(
          title,
          style: const TextStyle(color: CursorTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: CursorTheme.textPrimary),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: CursorTheme.textSecondary),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: CursorTheme.border),
            ),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: CursorTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text(
              'OK',
              style: TextStyle(color: CursorTheme.primary),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return null;
    if (result.contains('/') || result.contains('\\') || result.contains('..')) {
      if (mounted) {
        AppToast.error(context, 'Nombre inválido');
      }
      return null;
    }
    return result;
  }

  List<ProjectScreen> get _discoveredScreens {
    final all = ScreenDiscoveryService.fromTree(
      _projectTree,
      projectPath: _projectPath,
    );
    if (_treeFilter.isEmpty) return all;
    final q = _treeFilter.toLowerCase();
    return all
        .where(
          (s) =>
              s.displayName.toLowerCase().contains(q) ||
              s.path.toLowerCase().contains(q),
        )
        .toList();
  }

  void _openScreen(ProjectScreen screen) {
    setState(() => _selectedPath = screen.path);
    if (widget.onScreenSelected != null) {
      widget.onScreenSelected!(screen.path);
    } else {
      widget.onFileSelected?.call(screen.path);
    }
  }

  Future<void> _createNewScreen() async {
    if (_projectPath == null) return;
    final title = await _promptName(
      title: 'Nueva pantalla',
      label: 'Nombre (ej. Perfil, Checkout)',
    );
    if (title == null) return;

    final screens = ScreenDiscoveryService.fromTree(
      _projectTree,
      projectPath: _projectPath,
    );
    final hasPubspec =
        await File('$_projectPath/pubspec.yaml').exists();
    final preferHtml = !hasPubspec &&
        (screens.isEmpty ||
            screens.any((s) => s.kind == ProjectScreenKind.html));
    final fileName = ScreenDiscoveryService.fileSlug(
      title,
      extension: preferHtml ? 'html' : 'dart',
    );

    String path;
    String contents;
    if (preferHtml) {
      path = '$_projectPath/$fileName'.replaceAll('//', '/');
      contents = '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>$title</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: system-ui, -apple-system, sans-serif;
      background: #0f172a;
      color: #e2e8f0;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    h1 { font-weight: 600; letter-spacing: -0.02em; }
  </style>
</head>
<body>
  <h1>$title</h1>
</body>
</html>
''';
    } else {
      final screensDir = Directory('$_projectPath/lib/screens');
      if (!await screensDir.exists()) {
        await screensDir.create(recursive: true);
      }
      final classBase = ScreenDiscoveryService.prettyName(
        fileName,
        stripExt: '.dart',
      ).replaceAll(' ', '');
      final className =
          classBase.isEmpty ? 'NuevaPantalla' : '${classBase}Screen';
      path = '${screensDir.path}/$fileName'.replaceAll('//', '/');
      contents = '''import 'package:flutter/material.dart';

class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('$title')),
      body: const Center(child: Text('$title')),
    );
  }
}
''';
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        throw Exception('Ya existe: $fileName');
      }
      await file.create(recursive: true);
      await file.writeAsString(contents);
      await _loadProject();
      if (!mounted) return;
      setState(() => _selectedPath = path);
      _openScreen(
        ProjectScreen(
          path: path,
          displayName: title,
          kind: preferHtml
              ? ProjectScreenKind.html
              : ProjectScreenKind.flutter,
        ),
      );
      AppToast.info(context, 'Pantalla creada: $title');
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'No se pudo crear la pantalla: $e');
      }
    }
  }

  Widget _buildSectionHeader({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
        child: Row(
          children: [
            Icon(
              expanded
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
              size: 16,
              color: CursorTheme.textSecondary,
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildScreensSection() {
    final screens = _discoveredScreens;
    if (screens.isEmpty && _treeFilter.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
          title: 'PANTALLAS',
          expanded: _screensExpanded,
          onToggle: () =>
              setState(() => _screensExpanded = !_screensExpanded),
          trailing: IconButton(
            icon: const Icon(Icons.add, size: 15),
            color: CursorTheme.textSecondary,
            tooltip: 'Nueva pantalla',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            splashRadius: 14,
            onPressed: _createNewScreen,
          ),
        ),
        if (_screensExpanded) ...[
          if (screens.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 2, 12, 8),
              child: Text(
                'No hay pantallas aún.\nUsa + para crear una.',
                style: TextStyle(
                  color: CursorTheme.textDisabled,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            )
          else
            ...screens.map((screen) {
              final selected = _samePath(_selectedPath, screen.path);
              final isAgent = _matchesAgentFile(screen.path);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openScreen(screen),
                  onDoubleTap: () =>
                      widget.onFileDoubleClick?.call(screen.path),
                  child: AnimatedBuilder(
                    animation: _agentPulse,
                    builder: (context, _) {
                      Color? bg;
                      if (isAgent) {
                        bg = Color.lerp(
                          const Color(0xFF1A3A5C),
                          CursorTheme.primary.withOpacity(0.55),
                          _agentPulse.value,
                        );
                      } else if (selected) {
                        bg = CursorTheme.explorerItemSelected;
                      }
                      return Container(
                        key: isAgent ? _agentRowKey : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        color: bg,
                        child: Row(
                          children: [
                            Icon(
                              screen.kind == ProjectScreenKind.html
                                  ? Icons.web_asset
                                  : Icons.phone_iphone_outlined,
                              size: 15,
                              color: selected
                                  ? Colors.white
                                  : (screen.kind == ProjectScreenKind.html
                                      ? Colors.orange
                                      : const Color(0xFF54C5F8)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                screen.displayName,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : CursorTheme.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              screen.kind == ProjectScreenKind.html
                                  ? 'HTML'
                                  : 'UI',
                              style: TextStyle(
                                color: CursorTheme.textDisabled,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
        ],
      ],
    );
  }

  Future<void> _createNewFile(String parentDir) async {
    final name = await _promptName(
      title: 'Nuevo archivo',
      label: 'Nombre (ej. main.dart)',
    );
    if (name == null) return;
    final path = '$parentDir/$name'.replaceAll('//', '/');
    try {
      final file = File(path);
      if (await file.exists()) {
        throw Exception('Ya existe: $name');
      }
      await file.create(recursive: true);
      await file.writeAsString('');
      await _loadProject();
      if (mounted) {
        setState(() => _expandedPaths.add(parentDir));
      }
      widget.onFileViewCode?.call(path);
      if (mounted) {
        AppToast.info(context, 'Creado: $name');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error al crear archivo: $e');
      }
    }
  }

  Future<void> _createNewFolder(String parentDir) async {
    final name = await _promptName(
      title: 'Nueva carpeta',
      label: 'Nombre de la carpeta',
    );
    if (name == null) return;
    final path = '$parentDir/$name'.replaceAll('//', '/');
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        throw Exception('Ya existe: $name');
      }
      await dir.create(recursive: true);
      await _loadProject();
      if (mounted) {
        setState(() {
          _expandedPaths.add(parentDir);
          _expandedPaths.add(path);
        });
      }
      if (mounted) {
        AppToast.info(context, 'Carpeta creada: $name');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error al crear carpeta: $e');
      }
    }
  }

  Future<void> _renameEntry(
    String path,
    String currentName, {
    required bool isDirectory,
  }) async {
    final name = await _promptName(
      title: 'Renombrar',
      label: 'Nuevo nombre',
      initial: currentName,
    );
    if (name == null || name == currentName) return;
    final parent = File(path).parent.path;
    final newPath = '$parent/$name'.replaceAll('//', '/');
    try {
      if (isDirectory) {
        await Directory(path).rename(newPath);
      } else {
        await File(path).rename(newPath);
      }
      await _loadProject();
      if (!isDirectory) {
        widget.onFileViewCode?.call(newPath);
      }
      if (mounted) {
        AppToast.info(context, 'Renombrado a $name');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error al renombrar: $e');
      }
    }
  }

  Future<void> _duplicateFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('El archivo no existe');
      }
      final dir = file.parent.path;
      final name = filePath.split('/').last;
      final dot = name.lastIndexOf('.');
      final base = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      var candidate = '$dir/${base}_copy$ext';
      var i = 2;
      while (await File(candidate).exists()) {
        candidate = '$dir/${base}_copy$i$ext';
        i++;
      }
      await file.copy(candidate);
      await _loadProject();
      widget.onFileViewCode?.call(candidate);
      if (mounted) {
        AppToast.success(
          context,
          'Duplicado: ${candidate.split('/').last}',
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error al duplicar: $e');
      }
    }
  }

  Future<void> _confirmAndDelete(
    String filePath,
    String fileName, {
    required bool isDirectory,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CursorTheme.surface,
        title: Text(
          isDirectory ? 'Eliminar carpeta' : 'Eliminar archivo',
          style: const TextStyle(color: CursorTheme.textPrimary),
        ),
        content: Text(
          isDirectory
              ? '¿Eliminar la carpeta "$fileName" y todo su contenido?\n\nEsta acción no se puede deshacer.'
              : '¿Eliminar "$fileName"?\n\nEsta acción no se puede deshacer.',
          style: const TextStyle(color: CursorTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: CursorTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (isDirectory) {
        await Directory(filePath).delete(recursive: true);
      } else {
        await File(filePath).delete();
      }
      widget.onFileDelete?.call(filePath);
      await _loadProject();
      if (mounted) {
        AppToast.info(context, 'Eliminado: $fileName');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error al eliminar: $e');
      }
    }
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
                if (widget.onRequestOpenProject != null) {
                  widget.onRequestOpenProject!();
                  return;
                }
                final path = await FilePicker.platform.getDirectoryPath();
                if (path == null) return;
                await ProjectService.saveProjectPath(path);
                await _loadProject();
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Seleccionar Proyecto'),
            ),
          ],
        ),
      );
    }

    // Si el modo es búsqueda, mostrar el panel de búsqueda
    if (widget.mode == 'search') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de búsqueda
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
                const Icon(Icons.search, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre de archivo...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Resultados de búsqueda
          Expanded(
            child: _isSearching
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _searchResults.isEmpty && _searchController.text.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 48,
                              color: CursorTheme.textSecondary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No se encontraron archivos',
                              style: TextStyle(
                                color: CursorTheme.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _searchResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search,
                                  size: 48,
                                  color: CursorTheme.textSecondary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Escribe para buscar archivos...',
                                  style: TextStyle(
                                    color: CursorTheme.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final filePath = _searchResults[index];
                              final fileName = filePath.split('/').last;
                              final isSelected = _selectedPath == filePath;
                              
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedPath = filePath;
                                    });
                                    widget.onFileSelected?.call(filePath);
                                  },
                                  onDoubleTap: () {
                                    widget.onFileDoubleClick?.call(filePath);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    color: isSelected
                                        ? CursorTheme.explorerItemSelected
                                        : Colors.transparent,
                                    child: Row(
                                      children: [
                                        Icon(
                                          _getFileIcon(fileName),
                                          size: 16,
                                          color: _getFileColor(fileName),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            fileName,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Colors.white
                                                  : CursorTheme.textPrimary,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          filePath.replaceAll(_projectPath!, ''),
                                          style: TextStyle(
                                            color: CursorTheme.textSecondary,
                                            fontSize: 11,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      );
    }
    
    // Modo explorador normal
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
                icon: const Icon(Icons.note_add_outlined, size: 16),
                color: Colors.white70,
                onPressed: () => _createNewFile(_projectPath!),
                tooltip: 'Nuevo archivo',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                splashRadius: 14,
              ),
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                color: Colors.white70,
                onPressed: () => _createNewFolder(_projectPath!),
                tooltip: 'Nueva carpeta',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                splashRadius: 14,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                color: Colors.white70,
                onPressed: _loadProject,
                tooltip: 'Actualizar',
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                splashRadius: 14,
              ),
            ],
          ),
        ),
        // Filtro rápido por nombre (archivos / carpetas)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: TextField(
            controller: _searchController,
            focusNode: _filterFocus,
            style: const TextStyle(
              color: CursorTheme.textPrimary,
              fontSize: 12,
            ),
            cursorColor: CursorTheme.primary,
            decoration: InputDecoration(
              hintText: 'Filtrar archivos y carpetas…',
              hintStyle: const TextStyle(
                color: CursorTheme.textDisabled,
                fontSize: 12,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              prefixIcon: const Icon(
                Icons.filter_list,
                size: 15,
                color: CursorTheme.textSecondary,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 30,
                minHeight: 28,
              ),
              suffixIcon: _treeFilter.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      color: CursorTheme.textSecondary,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () => _searchController.clear(),
                    ),
              filled: true,
              fillColor: CursorTheme.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: CursorTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: CursorTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: CursorTheme.primary),
              ),
            ),
          ),
        ),
        // Pantallas + árbol (o resultados del filtro)
        Expanded(
          child: _treeFilter.isEmpty
              ? ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    _buildScreensSection(),
                    _buildSectionHeader(
                      title: 'ARCHIVOS',
                      expanded: _filesExpanded,
                      onToggle: () => setState(
                        () => _filesExpanded = !_filesExpanded,
                      ),
                    ),
                    if (_filesExpanded) _buildTreeItem(_projectTree!, 0),
                  ],
                )
              : (_treeFilterHits.isEmpty && _discoveredScreens.isEmpty)
                  ? const Center(
                      child: Text(
                        'Sin coincidencias',
                        style: TextStyle(
                          color: CursorTheme.textDisabled,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        _buildScreensSection(),
                        if (_treeFilterHits.isNotEmpty) ...[
                          _buildSectionHeader(
                            title: 'ARCHIVOS',
                            expanded: true,
                            onToggle: () {},
                          ),
                          ...List.generate(_treeFilterHits.length, (index) {
                        final hit = _treeFilterHits[index];
                        final name = hit['name']!;
                        final path = hit['path']!;
                        final isDir = hit['type'] == 'directory';
                        final rel = _projectPath != null
                            ? path.replaceFirst('$_projectPath/', '')
                            : path;
                        final isSelected = _samePath(_selectedPath, path);
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              if (isDir) {
                                setState(() {
                                  _expandedPaths.add(path);
                                  _selectedPath = path;
                                  _searchController.clear();
                                });
                              } else {
                                setState(() => _selectedPath = path);
                                widget.onFileSelected?.call(path);
                              }
                            },
                            onDoubleTap: () {
                              if (!isDir) {
                                widget.onFileDoubleClick?.call(path);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              color: isSelected
                                  ? CursorTheme.explorerItemSelected
                                  : Colors.transparent,
                              child: Row(
                                children: [
                                  Icon(
                                    isDir
                                        ? Icons.folder
                                        : _getFileIcon(name),
                                    size: 16,
                                    color: isDir
                                        ? const Color(0xFFFFB800)
                                        : _getFileColor(name),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            color: CursorTheme.textPrimary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (rel != name)
                                          Text(
                                            rel,
                                            style: const TextStyle(
                                              color: CursorTheme.textSecondary,
                                              fontSize: 10,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                          }),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }
}

