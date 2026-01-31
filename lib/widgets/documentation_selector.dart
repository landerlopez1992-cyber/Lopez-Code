import 'package:flutter/material.dart';
import 'cursor_theme.dart';
import '../services/documentation_service.dart';

/// Widget para seleccionar y gestionar documentación (similar a Cursor)
class DocumentationSelector extends StatefulWidget {
  final Function(String)? onDocumentationSelected;

  const DocumentationSelector({
    super.key,
    this.onDocumentationSelected,
  });

  @override
  State<DocumentationSelector> createState() => _DocumentationSelectorState();
}

class _DocumentationSelectorState extends State<DocumentationSelector> {
  List<DocumentationSource> _sources = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadDocumentation();
  }

  Future<void> _loadDocumentation() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final sources = await DocumentationService.getDocumentationSources();
      if (mounted) {
        setState(() {
          _sources = sources;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error al cargar documentación: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addDocumentation() async {
    if (!mounted) return;
    
    try {
      // Mostrar diálogo - ahora el diálogo guarda directamente
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (context) => _AddDocumentationDialog(),
      );

      // Si saved es true, significa que se guardó exitosamente
      if (saved == true && mounted) {
        // Recargar documentación
        await _loadDocumentation();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Documentación agregada correctamente'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('❌ Error al agregar documentación: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  List<DocumentationSource> get _filteredSources {
    if (_searchQuery.isEmpty) {
      return _sources;
    }
    return _sources.where((source) {
      return source.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          source.url.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      constraints: const BoxConstraints(maxHeight: 500),
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CursorTheme.border,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header con botón de cerrar y búsqueda
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: CursorTheme.border,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 18),
                  color: CursorTheme.textPrimary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    autofocus: true,
                    style: TextStyle(
                      color: CursorTheme.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search documentation...',
                      hintStyle: TextStyle(
                        color: CursorTheme.textSecondary,
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Lista de documentación
          Flexible(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _filteredSources.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.book_outlined,
                                size: 48,
                                color: CursorTheme.textSecondary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No hay documentación',
                                style: TextStyle(
                                  color: CursorTheme.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _addDocumentation,
                                child: const Text('Agregar documentación'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _filteredSources.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            // Header "Docs"
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.book_outlined,
                                    size: 16,
                                    color: CursorTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Docs',
                                    style: TextStyle(
                                      color: CursorTheme.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: _addDocumentation,
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      'Agregar',
                                      style: TextStyle(
                                        color: CursorTheme.primary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          final source = _filteredSources[index - 1];
                          final isSelected = source.isActive;

                          return InkWell(
                            onTap: () {
                              if (widget.onDocumentationSelected != null) {
                                widget.onDocumentationSelected!(source.url);
                              }
                              // No cerramos aquí, el padre lo hace
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              color: isSelected
                                  ? CursorTheme.primary.withValues(alpha: 0.1)
                                  : Colors.transparent,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.book_outlined,
                                    size: 16,
                                    color: CursorTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          source.name,
                                          style: TextStyle(
                                            color: CursorTheme.textPrimary,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Indexed ${_formatDate(source.indexedAt)}',
                                          style: TextStyle(
                                            color: CursorTheme.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check,
                                      size: 16,
                                      color: CursorTheme.primary,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'hoy';
    } else if (difference.inDays == 1) {
      return 'ayer';
    } else if (difference.inDays < 7) {
      return 'hace ${difference.inDays} días';
    } else {
      return '${date.day}/${date.month}/${date.year.toString().substring(2)}';
    }
  }
}

class _AddDocumentationDialog extends StatefulWidget {
  @override
  State<_AddDocumentationDialog> createState() =>
      _AddDocumentationDialogState();
}

class _AddDocumentationDialogState extends State<_AddDocumentationDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    final description = _descriptionController.text.trim();
    
    // Validación
    if (name.isEmpty || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Nombre y URL son requeridos'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    
    // Validar URL básica
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ La URL debe comenzar con http:// o https://'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    
    // Iniciar guardado
    if (!mounted) return;
    setState(() {
      _isSaving = true;
    });
    
    try {
      final source = DocumentationSource(
        name: name,
        url: url,
        indexedAt: DateTime.now(),
        description: description.isEmpty ? null : description,
      );
      
      // Guardar directamente
      final success = await DocumentationService.addDocumentationSource(source);
      
      if (!mounted) return;
      
      if (success) {
        // Cerrar diálogo solo si el guardado fue exitoso
        Navigator.of(context).pop(true);
      } else {
        // Mostrar error y permitir reintentar
        setState(() {
          _isSaving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Esta documentación ya existe'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error al guardar en diálogo: $e');
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al guardar: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: CursorTheme.surface,
      title: Text(
        'Agregar Documentación',
        style: TextStyle(color: CursorTheme.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            enabled: !_isSaving,
            style: TextStyle(color: CursorTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Nombre',
              labelStyle: TextStyle(color: CursorTheme.textSecondary),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: CursorTheme.border),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            enabled: !_isSaving,
            style: TextStyle(color: CursorTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'URL',
              labelStyle: TextStyle(color: CursorTheme.textSecondary),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: CursorTheme.border),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            enabled: !_isSaving,
            style: TextStyle(color: CursorTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Descripción (opcional)',
              labelStyle: TextStyle(color: CursorTheme.textSecondary),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: CursorTheme.border),
              ),
            ),
            maxLines: 2,
          ),
          if (_isSaving) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              'Guardando...',
              style: TextStyle(
                color: CursorTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: Text(
            'Cancelar',
            style: TextStyle(color: CursorTheme.textSecondary),
          ),
        ),
        TextButton(
          onPressed: _isSaving ? null : _handleSave,
          child: Text(
            'Agregar',
            style: TextStyle(color: CursorTheme.primary),
          ),
        ),
      ],
    );
  }
}
