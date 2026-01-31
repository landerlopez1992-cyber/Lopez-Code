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
  final ScrollController _lineNumbersScrollController = ScrollController();
  final ScrollController _codeScrollController = ScrollController();
  bool _isModified = false;
  String? _currentFilePath;
  bool _isSaving = false;
  List<TextSpan>? _cachedSpans;
  String? _cachedCode;
  bool _isScrolling = false; // Flag para evitar loops infinitos al sincronizar

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
    // Sincronizar scroll entre números de línea y código
    _lineNumbersScrollController.addListener(_syncLineNumbersScroll);
    _codeScrollController.addListener(_syncCodeScroll);
    print('📝 CodeEditorPanel.initState: Contenido inicial (${widget.initialContent?.length ?? 0} caracteres)');
  }

  @override
  void didUpdateWidget(CodeEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Actualizar el contenido si cambió
    if (widget.initialContent != oldWidget.initialContent && widget.initialContent != null) {
      print('📝 CodeEditorPanel.didUpdateWidget: Actualizando contenido (${widget.initialContent!.length} caracteres)');
      _codeController.text = widget.initialContent!;
      _isModified = false;
      // Invalidar cache cuando cambia el contenido
      _cachedSpans = null;
      _cachedCode = null;
    }
  }

  void _syncLineNumbersScroll() {
    if (!_isScrolling && _lineNumbersScrollController.hasClients) {
      _isScrolling = true;
      if (_codeScrollController.hasClients) {
        _codeScrollController.jumpTo(_lineNumbersScrollController.offset);
      }
      _isScrolling = false;
    }
  }

  void _syncCodeScroll() {
    if (!_isScrolling && _codeScrollController.hasClients) {
      _isScrolling = true;
      if (_lineNumbersScrollController.hasClients) {
        _lineNumbersScrollController.jumpTo(_codeScrollController.offset);
      }
      _isScrolling = false;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _lineNumbersScrollController.removeListener(_syncLineNumbersScroll);
    _codeScrollController.removeListener(_syncCodeScroll);
    _lineNumbersScrollController.dispose();
    _codeScrollController.dispose();
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

  /// Construye el editor con syntax highlighting (estilo Cursor IDE)
  Widget _buildSyntaxHighlightedEditor() {
    final code = _codeController.text;
    
    // Si el código está vacío, mostrar editor con línea 1
    if (code.isEmpty) {
      return _buildEditorWithLineNumbers('', [const TextSpan(text: '', style: TextStyle(color: CursorTheme.codeText))]);
    }

    // Usar cache si el código no ha cambiado
    if (_cachedSpans != null && _cachedCode == code) {
      return _buildEditorWithLineNumbers(code, _cachedSpans!);
    }

    // Para archivos grandes, usar parsing simplificado
    if (code.length > 50000) {
      return _buildSimpleEditor(code);
    }

    // Parsear el código de forma optimizada
    final spans = _parseCodeOptimized(code);
    _cachedSpans = spans;
    _cachedCode = code;
    
    return _buildEditorWithLineNumbers(code, spans);
  }

  /// Parsing optimizado del código (mejorado para coincidir exactamente con Cursor IDE)
  List<TextSpan> _parseCodeOptimized(String code) {
    // Colores exactos de Cursor IDE Dark+ theme
    const tagColor = Color(0xFF569CD6); // Azul para tags HTML
    const attributeColor = Color(0xFF92C5F7); // Azul claro para atributos
    const valueColor = Color(0xFFCE9178); // Naranja para valores de atributos
    const commentColor = Color(0xFF6A9955); // Verde para comentarios
    const textColor = Color(0xFFD4D4D4); // Gris claro para texto normal
    const keywordColor = Color(0xFFC586C0); // Morado para palabras clave CSS
    const stringColor = Color(0xFFCE9178); // Naranja para strings
    const punctuationColor = Color(0xFFD4D4D4); // Gris para puntuación

    final spans = <TextSpan>[];
    final lines = code.split('\n');
    
    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      
      if (line.isEmpty) {
        spans.add(const TextSpan(text: '\n'));
        continue;
      }

      int i = 0;
      while (i < line.length) {
        // PRIORIDAD 1: Detectar comentarios HTML: <!-- ... -->
        if (i < line.length - 3 && line.substring(i, i + 4) == '<!--') {
          final commentEnd = line.indexOf('-->', i);
          if (commentEnd != -1) {
            spans.add(TextSpan(
              text: line.substring(i, commentEnd + 3),
              style: const TextStyle(color: commentColor),
            ));
            i = commentEnd + 3;
            continue;
          } else {
            // Comentario sin cerrar, aplicar color hasta el final
            spans.add(TextSpan(
              text: line.substring(i),
              style: const TextStyle(color: commentColor),
            ));
            i = line.length;
            continue;
          }
        }

        // PRIORIDAD 2: Detectar comentarios CSS: /* ... */
        if (i < line.length - 1 && line.substring(i, i + 2) == '/*') {
          final commentEnd = line.indexOf('*/', i);
          if (commentEnd != -1) {
            spans.add(TextSpan(
              text: line.substring(i, commentEnd + 2),
              style: const TextStyle(color: commentColor),
            ));
            i = commentEnd + 2;
            continue;
          } else {
            spans.add(TextSpan(
              text: line.substring(i),
              style: const TextStyle(color: commentColor),
            ));
            i = line.length;
            continue;
          }
        }

        // PRIORIDAD 3: Detectar tags HTML: <tag> o </tag>
        if (line[i] == '<') {
          final tagEnd = line.indexOf('>', i);
          if (tagEnd != -1) {
            final tagContent = line.substring(i, tagEnd + 1);
            
            // Tag de cierre: </tag>
            if (tagContent.startsWith('</')) {
              spans.add(const TextSpan(text: '</', style: TextStyle(color: tagColor)));
              final tagName = tagContent.substring(2, tagContent.length - 1).trim();
              if (tagName.isNotEmpty) {
                spans.add(TextSpan(
                  text: tagName,
                  style: const TextStyle(color: tagColor, fontWeight: FontWeight.w500),
                ));
              }
              spans.add(const TextSpan(text: '>', style: TextStyle(color: tagColor)));
              i = tagEnd + 1;
              continue;
            }
            
            // Tag de apertura o auto-cerrado: <tag> o <tag />
            final isSelfClosing = tagContent.endsWith('/>');
            final tagNameEnd = tagContent.indexOf(' ', 1);
            final tagNameEnd2 = tagContent.indexOf('>', 1);
            final tagNameEnd3 = isSelfClosing ? tagContent.indexOf('/', 1) : -1;
            
            int tagNameEndFinal = tagNameEnd;
            if (tagNameEnd == -1 || (tagNameEnd2 != -1 && tagNameEnd2 < tagNameEnd)) {
              tagNameEndFinal = tagNameEnd2 != -1 ? tagNameEnd2 : tagContent.length - 1;
            }
            if (isSelfClosing && tagNameEnd3 != -1 && tagNameEnd3 < tagNameEndFinal) {
              tagNameEndFinal = tagNameEnd3;
            }
            
            spans.add(const TextSpan(text: '<', style: TextStyle(color: tagColor)));
            
            if (tagNameEndFinal > 1) {
              final tagName = tagContent.substring(1, tagNameEndFinal).trim();
              if (tagName.isNotEmpty) {
                spans.add(TextSpan(
                  text: tagName,
                  style: const TextStyle(color: tagColor, fontWeight: FontWeight.w500),
                ));
              }
            }
            
            // Parsear atributos si existen
            if (tagNameEndFinal < tagContent.length - (isSelfClosing ? 2 : 1)) {
              final attrsStart = tagNameEndFinal;
              final attrsEnd = isSelfClosing ? tagContent.length - 2 : tagContent.length - 1;
              if (attrsEnd > attrsStart) {
                final attrs = tagContent.substring(attrsStart, attrsEnd);
                _parseAttributes(attrs, spans, attributeColor, valueColor, stringColor, punctuationColor);
              }
            }
            
            if (isSelfClosing) {
              spans.add(const TextSpan(text: ' />', style: TextStyle(color: tagColor)));
            } else {
              spans.add(const TextSpan(text: '>', style: TextStyle(color: tagColor)));
            }
            
            i = tagEnd + 1;
            continue;
          }
        }
        
        // PRIORIDAD 4: Detectar propiedades CSS: property: value;
        // Solo si no estamos dentro de un tag HTML
        if (line.contains(':') && !line.substring(0, i).contains('<')) {
          final colonIndex = line.indexOf(':', i);
          if (colonIndex != -1) {
            // Verificar que no sea parte de un atributo HTML (dentro de comillas)
            final beforeColon = line.substring(0, colonIndex);
            final doubleQuotes = beforeColon.split('"').length - 1;
            final singleQuotes = beforeColon.split("'").length - 1;
            
            // Si hay un número impar de comillas antes de ':', estamos dentro de un atributo
            if (doubleQuotes % 2 == 0 && singleQuotes % 2 == 0) {
              final property = line.substring(i, colonIndex).trim();
              final semicolonIndex = line.indexOf(';', colonIndex);
              final value = semicolonIndex != -1 
                  ? line.substring(colonIndex + 1, semicolonIndex).trim()
                  : line.substring(colonIndex + 1).trim();
              
              if (property.isNotEmpty) {
                spans.add(TextSpan(
                  text: property,
                  style: const TextStyle(color: keywordColor),
                ));
                spans.add(const TextSpan(text: ':', style: TextStyle(color: punctuationColor)));
                if (value.isNotEmpty) {
                  spans.add(TextSpan(
                    text: ' $value',
                    style: const TextStyle(color: valueColor),
                  ));
                }
                if (semicolonIndex != -1) {
                  spans.add(const TextSpan(text: ';', style: TextStyle(color: punctuationColor)));
                  i = semicolonIndex + 1;
                } else {
                  i = line.length;
                }
                continue;
              }
            }
          }
        }
        
        // Texto normal
        spans.add(TextSpan(
          text: line[i],
          style: const TextStyle(color: textColor),
        ));
        i++;
      }
      
      if (lineIndex < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    
    return spans;
  }

  /// Editor simplificado para archivos grandes (sin syntax highlighting completo)
  Widget _buildSimpleEditor(String code) {
    final lines = code.split('\n');
    final lineCount = lines.length;
    final lineNumbers = List.generate(lineCount, (index) => '${index + 1}');
    final maxLineNumberWidth = lineNumbers.last.length;
    final lineNumberWidth = 50 + (maxLineNumberWidth * 8.0);
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Panel de números de línea
        SingleChildScrollView(
          controller: _lineNumbersScrollController,
          child: Container(
            width: lineNumberWidth,
            padding: const EdgeInsets.only(left: 16, right: 8, top: 16, bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              border: Border(
                right: BorderSide(color: CursorTheme.border, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: lineNumbers.map((lineNum) {
                return Container(
                  height: 20.8,
                  alignment: Alignment.centerRight,
                  child: Text(
                    lineNum,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: CursorTheme.editorLineNumber,
                      height: 1.6,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // Panel de código (sin syntax highlighting para mejor rendimiento)
        Expanded(
          child: SingleChildScrollView(
            controller: _codeScrollController,
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 16, right: 16),
            child: SelectableText(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: CursorTheme.codeText,
                height: 1.6,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Construye el editor con numeración de líneas
  Widget _buildEditorWithLineNumbers(String code, List<TextSpan> spans) {
    final lineCount = code.isEmpty ? 1 : code.split('\n').length;
    final lineNumbers = List.generate(lineCount, (index) => '${index + 1}');
    final maxLineNumberWidth = lineNumbers.isEmpty ? 1 : lineNumbers.last.length;
    final lineNumberWidth = 50 + (maxLineNumberWidth * 8.0);
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Panel de números de línea con scroll sincronizado
        SingleChildScrollView(
          controller: _lineNumbersScrollController,
          child: Container(
            width: lineNumberWidth,
            padding: const EdgeInsets.only(left: 16, right: 8, top: 16, bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              border: Border(
                right: BorderSide(color: CursorTheme.border, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: lineNumbers.map((lineNum) {
                return Container(
                  height: 20.8, // height: 1.6 * 13 (fontSize)
                  alignment: Alignment.centerRight,
                  child: Text(
                    lineNum,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: CursorTheme.editorLineNumber,
                      height: 1.6,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // Panel de código con scroll sincronizado
        Expanded(
          child: SingleChildScrollView(
            controller: _codeScrollController,
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 16, right: 16),
            child: SelectableText.rich(
              TextSpan(
                children: spans,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.6,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Parsea atributos HTML y crea TextSpans con colores (mejorado)
  void _parseAttributes(String attrs, List<TextSpan> spans, Color attributeColor, Color valueColor, Color stringColor, Color punctuationColor) {
    if (attrs.trim().isEmpty) return;
    
    // Buscar atributos en el formato: attr="value" o attr='value' o attr=value
    final regexDouble = RegExp(r'(\S+)\s*=\s*"([^"]*)"');
    final regexSingle = RegExp(r"(\S+)\s*=\s*'([^']*)'");
    final regexNoQuotes = RegExp(r"(\S+)\s*=\s*(\S+)");
    
    int lastIndex = 0;
    final allMatches = <RegExpMatch>[];
    
    // Buscar todos los matches
    allMatches.addAll(regexDouble.allMatches(attrs));
    allMatches.addAll(regexSingle.allMatches(attrs));
    allMatches.addAll(regexNoQuotes.allMatches(attrs));
    
    // Ordenar por posición de inicio
    allMatches.sort((a, b) => a.start.compareTo(b.start));
    
    // Eliminar duplicados (preferir comillas sobre sin comillas)
    final filteredMatches = <RegExpMatch>[];
    for (int i = 0; i < allMatches.length; i++) {
      bool isDuplicate = false;
      for (int j = 0; j < i; j++) {
        if (allMatches[i].start < allMatches[j].end && allMatches[i].end > allMatches[j].start) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        filteredMatches.add(allMatches[i]);
      }
    }
    
    for (final match in filteredMatches) {
      // Texto antes del atributo (espacios, etc.)
      if (match.start > lastIndex) {
        final beforeText = attrs.substring(lastIndex, match.start);
        spans.add(TextSpan(
          text: beforeText,
          style: TextStyle(color: punctuationColor),
        ));
      }
      
      // Nombre del atributo
      final attrName = match.group(1)!;
      spans.add(TextSpan(
        text: attrName,
        style: TextStyle(color: attributeColor),
      ));
      
      // Signo = y espacios alrededor
      final equalsIndex = attrs.indexOf('=', match.start);
      if (equalsIndex != -1) {
        final beforeEquals = attrs.substring(match.start + attrName.length, equalsIndex);
        spans.add(TextSpan(
          text: beforeEquals,
          style: TextStyle(color: punctuationColor),
        ));
        spans.add(TextSpan(
          text: '=',
          style: TextStyle(color: punctuationColor),
        ));
        
        // Valor del atributo
        final afterEquals = attrs.substring(equalsIndex + 1, match.end);
        final trimmedAfter = afterEquals.trim();
        
        if (trimmedAfter.startsWith('"') || trimmedAfter.startsWith("'")) {
          // Atributo con comillas
          final quote = trimmedAfter[0];
          spans.add(TextSpan(
            text: quote,
            style: TextStyle(color: stringColor),
          ));
          if (trimmedAfter.length > 2) {
            spans.add(TextSpan(
              text: trimmedAfter.substring(1, trimmedAfter.length - 1),
              style: TextStyle(color: valueColor),
            ));
          }
          spans.add(TextSpan(
            text: quote,
            style: TextStyle(color: stringColor),
          ));
        } else {
          // Atributo sin comillas
          spans.add(TextSpan(
            text: trimmedAfter,
            style: TextStyle(color: valueColor),
          ));
        }
      }
      
      lastIndex = match.end;
    }
    
    // Texto restante
    if (lastIndex < attrs.length) {
      spans.add(TextSpan(
        text: attrs.substring(lastIndex),
        style: TextStyle(color: punctuationColor),
      ));
    }
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

          // Editor de código con syntax highlighting
          Expanded(
            child: Container(
              color: CursorTheme.editorBackground,
              child: _buildSyntaxHighlightedEditor(),
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

