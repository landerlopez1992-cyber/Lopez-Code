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
    setState(() {
      _isLoading = true;
    });

    try {
      final sources = await DocumentationService.getDocumentationSources();
      setState(() {
        _sources = sources;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error al cargar documentación: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addDocumentation() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _AddDocumentationDialog(),
    );

    if (result != null) {
      final source = DocumentationSource(
        name: result['name']!,
        url: result['url']!,
        indexedAt: DateTime.now(),
        description: result['description'],
      );

      final success = await DocumentationService.addDocumentationSource(source);
      if (success) {
        _loadDocumentation();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Documentación agregada'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Esta documentación ya existe'),
            backgroundColor: Colors.orange,
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
            color: Colors.black.withOpacity(0.2),
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
                                  ? CursorTheme.primary.withOpacity(0.1)
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

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    super.dispose();
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancelar',
            style: TextStyle(color: CursorTheme.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () {
            if (_nameController.text.isNotEmpty &&
                _urlController.text.isNotEmpty) {
              Navigator.of(context).pop({
                'name': _nameController.text,
                'url': _urlController.text,
                'description': _descriptionController.text.isEmpty
                    ? null
                    : _descriptionController.text,
              });
            }
          },
          child: Text(
            'Agregar',
            style: TextStyle(color: CursorTheme.primary),
          ),
        ),
      ],
    );
  }
}
