import 'dart:io';
import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'cursor_theme.dart';
import 'model_selector.dart';
import 'documentation_selector.dart';
import '../services/settings_service.dart';

/// Modo de interacción del chat estilo Cursor.
enum ChatAgentMode {
  /// Puede leer, buscar y editar archivos (tools ON).
  agent,

  /// Solo responde con el contexto @; no modifica archivos (tools OFF).
  ask,
}

class CursorChatInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachFile;
  final bool isLoading;
  final VoidCallback? onStop;
  final String? placeholder;
  final Function(String)? onModelChanged;
  final Function(String)? onDocumentationSelected;
  final List<String>? selectedImages; // Imágenes seleccionadas para previsualizar
  final String? selectedFilePath; // Archivo seleccionado para previsualizar
  final Function(int)? onRemoveImage; // Callback para remover imagen (recibe índice)
  final VoidCallback? onRemoveFile; // Callback para remover archivo
  /// Imágenes arrastradas / pegadas (rutas locales), estilo Cursor.
  final ValueChanged<List<String>>? onImagesDropped;
  final ChatAgentMode chatMode;
  final ValueChanged<ChatAgentMode>? onChatModeChanged;

  const CursorChatInput({
    super.key,
    required this.controller,
    required this.onSend,
    this.onAttachImage,
    this.onAttachFile,
    this.isLoading = false,
    this.onStop,
    this.placeholder,
    this.onModelChanged,
    this.onDocumentationSelected,
    this.selectedImages,
    this.selectedFilePath,
    this.onRemoveImage,
    this.onRemoveFile,
    this.onImagesDropped,
    this.chatMode = ChatAgentMode.agent,
    this.onChatModeChanged,
  });

  @override
  State<CursorChatInput> createState() => _CursorChatInputState();
}

class _CursorChatInputState extends State<CursorChatInput> {
  String _currentModel = SettingsService.defaultModel;
  bool _autoMode = false;
  OverlayEntry? _overlayEntry;
  bool _draggingOver = false;

  static const _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
    '.tif',
    '.tiff',
  };

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  bool _isImagePath(String path) {
    final lower = path.toLowerCase();
    return _imageExtensions.any(lower.endsWith);
  }

  void _safeSetDragging(bool value) {
    if (!mounted || _draggingOver == value) return;
    setState(() => _draggingOver = value);
  }

  void _handleDroppedFiles(DropDoneDetails details) {
    final paths = <String>[];
    for (final file in details.files) {
      final path = file.path;
      if (path.isEmpty) continue;
      if (_isImagePath(path) || (file.mimeType?.startsWith('image/') ?? false)) {
        paths.add(path);
      }
    }
    if (paths.isEmpty) return;
    // Diferir al siguiente frame: el DropTarget aún está en el árbol;
    // setState del padre en el mismo tick puede dejar Elements defunct.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onImagesDropped?.call(paths);
    });
  }

  /// Guarda bytes de imagen del clipboard como PNG en systemTemp y
  /// dispara el chip de adjunto vía [onImagesDropped].
  Future<String?> _savePastedImageBytes(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    // Capturas macOS (Cmd+Ctrl+Shift+4) suelen ser PNG; forzamos .png
    // salvo que el magic number indique otro formato.
    final ext = _extensionForImageBytes(bytes);
    final file = File(
      '${Directory.systemTemp.path}/pasted_screenshot_'
      '${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  String _extensionForImageBytes(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return '.jpg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return '.png';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return '.gif';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return '.webp';
    }
    return '.png';
  }

  /// Cmd/Ctrl+V: ruta de imagen en texto, archivos del pasteboard, o bytes.
  Future<void> _handleClipboardPasteForImages() async {
    if (widget.onImagesDropped == null) return;

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      final path = text.replaceFirst(RegExp(r'^file://'), '');
      if (_isImagePath(path) && File(path).existsSync()) {
        widget.onImagesDropped!([path]);
        return;
      }
    }

    try {
      final files = await Pasteboard.files();
      final imageFiles = files.where(_isImagePath).where((p) => File(p).existsSync()).toList();
      if (imageFiles.isNotEmpty) {
        widget.onImagesDropped!(imageFiles);
        return;
      }
    } catch (_) {}

    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final saved = await _savePastedImageBytes(imageBytes);
        if (saved != null) {
          widget.onImagesDropped!([saved]);
        }
      }
    } catch (e) {
      print('⚠️ Pasteboard image paste failed: $e');
    }
  }

  Future<void> _loadModel() async {
    // getSelectedModel migra defaults viejos → gpt-4.1
    final model = await SettingsService.getSelectedModel();
    final autoMode = await SettingsService.getAutoMode();
    if (!mounted) return;
    setState(() {
      _currentModel = model;
      _autoMode = autoMode;
    });
    // Sincronizar OpenAIService / prefs si venía el default legacy
    widget.onModelChanged?.call(model);
  }

  void _showModelSelector() {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    // Función para calcular posición dinámicamente
    Offset calculatePosition(bool autoMode) {
      final selectorWidth = 260.0;
      final selectorHeight = autoMode ? 100.0 : 380.0;
      
      // Posición X: alineado con el botón (esquina izquierda del chat)
      final left = offset.dx;
      
      // Posición Y: ARRIBA del botón (porque ahora los botones están abajo)
      final top = offset.dy - selectorHeight - 4; // 4px de margen arriba
      
      // Asegurar que no se salga de la pantalla
      final finalLeft = left.clamp(8.0, screenSize.width - selectorWidth - 8);
      final finalTop = top.clamp(8.0, screenSize.height - selectorHeight - 8);
      
      return Offset(finalLeft, finalTop);
    }

    _overlayEntry = OverlayEntry(
      builder: (context) {
        // Recalcular posición cuando cambia el modo Auto
        final position = calculatePosition(_autoMode);
        
        return Stack(
          children: [
            // Área transparente para cerrar al tocar fuera
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeOverlay,
                behavior: HitTestBehavior.translucent,
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
            // Selector de modelos
            Positioned(
              left: position.dx,
              top: position.dy,
              child: Material(
                color: Colors.transparent,
                child: ModelSelector(
                  currentModel: _currentModel,
                  autoMode: _autoMode,
                  onModelChanged: (model) {
                    print('✅ Modelo seleccionado en CursorChatInput: $model');
                    setState(() {
                      _currentModel = model;
                    });
                    widget.onModelChanged?.call(model);
                    _closeOverlay(); // Cerrar el overlay después de seleccionar
                  },
                  onAutoChanged: (auto) async {
                    if (mounted) {
                      setState(() {
                        _autoMode = auto;
                      });
                    }
                    await SettingsService.saveAutoMode(auto);
                    // Recalcular overlay solo si sigue montado e insertado
                    final entry = _overlayEntry;
                    if (mounted && entry != null && entry.mounted) {
                      entry.markNeedsBuild();
                    }
                  },
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _showDocumentationSelector() {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Área transparente para cerrar al tocar fuera
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeOverlay,
              behavior: HitTestBehavior.translucent,
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
          // Selector de documentación (arriba de los botones)
          Positioned(
            left: offset.dx - 400 + size.width,
            top: offset.dy - 500, // Ajustar según necesidad
            child: Material(
              color: Colors.transparent,
              child: DocumentationSelector(
                onDocumentationSelected: (url) {
                  try {
                    // Insertar @url en el campo de texto
                    final text = widget.controller.text;
                    final selection = widget.controller.selection;
                    
                    // Validar la selección - verificar que los índices sean válidos
                    final textLength = text.length;
                    final start = (selection.start >= 0 && selection.start <= textLength) 
                        ? selection.start 
                        : textLength;
                    final end = (selection.end >= 0 && selection.end <= textLength) 
                        ? selection.end 
                        : textLength;
                    
                    // Asegurar que start <= end
                    final validStart = start <= end ? start : end;
                    final validEnd = end >= start ? end : start;
                    
                    // Insertar el tag
                    final tag = '@$url ';
                    final newText = text.replaceRange(validStart, validEnd, tag);
                    widget.controller.text = newText;
                    
                    // Posicionar el cursor después del tag insertado
                    final newOffset = (validStart + tag.length).clamp(0, newText.length);
                    widget.controller.selection = TextSelection.collapsed(
                      offset: newOffset,
                    );
                    
                    widget.onDocumentationSelected?.call(url);
                    _closeOverlay(); // Cerrar el overlay después de seleccionar
                  } catch (e, stackTrace) {
                    print('❌ Error al insertar tag de documentación: $e');
                    print('Stack trace: $stackTrace');
                    // Si hay error, simplemente agregar al final
                    final text = widget.controller.text;
                    widget.controller.text = '$text@$url ';
                    widget.controller.selection = TextSelection.collapsed(
                      offset: widget.controller.text.length,
                    );
                    widget.onDocumentationSelected?.call(url);
                    _closeOverlay();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _closeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// Inserta `@` en el cursor para abrir el menú de contexto (Files / Docs / …).
  void _insertAtMention() {
    _closeOverlay();
    final text = widget.controller.text;
    final sel = widget.controller.selection;
    final start = sel.isValid ? sel.start.clamp(0, text.length) : text.length;
    final end = sel.isValid ? sel.end.clamp(0, text.length) : text.length;
    final lo = start <= end ? start : end;
    final hi = end >= start ? end : start;
    final newText = text.replaceRange(lo, hi, '@');
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lo + 1),
    );
  }

  @override
  void dispose() {
    _closeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enable: mounted,
      onDragEntered: (_) => _safeSetDragging(true),
      onDragExited: (_) => _safeSetDragging(false),
      onDragDone: (details) {
        _safeSetDragging(false);
        _handleDroppedFiles(details);
      },
      child: GestureDetector(
      onTap: _closeOverlay,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _draggingOver
              ? CursorTheme.primary.withOpacity(0.08)
              : CursorTheme.surface,
          border: Border(
            top: BorderSide(
              color: _draggingOver ? CursorTheme.primary : CursorTheme.border,
              width: _draggingOver ? 2 : 1,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_draggingOver) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: CursorTheme.primary.withOpacity(0.6),
                    width: 1.5,
                  ),
                  color: CursorTheme.primary.withOpacity(0.12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_outlined, size: 16, color: CursorTheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Suelta la imagen aquí para adjuntarla al chat',
                      style: TextStyle(
                        color: CursorTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Previsualización de imágenes/archivos (si hay)
            if (widget.selectedImages != null && widget.selectedImages!.isNotEmpty) ...[
              Container(
                height: 100,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.selectedImages!.length,
                  itemBuilder: (context, index) {
                    final imagePath = widget.selectedImages![index];
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(imagePath),
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                          // Botón para remover
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Material(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                onTap: widget.onRemoveImage != null
                                    ? () => widget.onRemoveImage!(index)
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            
            // Previsualización de archivo (si hay)
            if (widget.selectedFilePath != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CursorTheme.background.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: CursorTheme.border.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.insert_drive_file,
                      size: 20,
                      color: CursorTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.selectedFilePath!.split('/').last,
                        style: TextStyle(
                          color: CursorTheme.textPrimary,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.onRemoveFile != null)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: widget.onRemoveFile,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: CursorTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            
            // Campo de texto ARRIBA (como Cursor)
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              decoration: BoxDecoration(
                color: CursorTheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: CursorTheme.border.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;

                  // Return envía; Shift+Return inserta nueva línea (como Cursor).
                  // Con maxLines: null, onSubmitted casi nunca se dispara en desktop.
                  final isEnter =
                      event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter;
                  if (isEnter &&
                      !HardwareKeyboard.instance.isShiftPressed &&
                      !HardwareKeyboard.instance.isAltPressed &&
                      !HardwareKeyboard.instance.isMetaPressed &&
                      !HardwareKeyboard.instance.isControlPressed) {
                    if (!widget.isLoading) {
                      widget.onSend();
                    }
                    return KeyEventResult.handled;
                  }

                  // Cmd/Ctrl+V: ruta de imagen, archivos, o bytes (captura macOS).
                  final isPaste = (HardwareKeyboard.instance.isMetaPressed ||
                          HardwareKeyboard.instance.isControlPressed) &&
                      event.logicalKey == LogicalKeyboardKey.keyV;
                  if (!isPaste || widget.onImagesDropped == null) {
                    return KeyEventResult.ignored;
                  }
                  _handleClipboardPasteForImages();
                  return KeyEventResult.ignored; // no bloquear pegar texto
                },
                child: TextField(
                  controller: widget.controller,
                  style: const TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                  maxLines: null,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  onSubmitted: (_) {
                    if (!widget.isLoading) widget.onSend();
                  },
                  onTap: _closeOverlay,
                  decoration: InputDecoration(
                    hintText: widget.placeholder ??
                        'Plan, @ for context, / for commands',
                    hintStyle: TextStyle(
                      color: CursorTheme.textDisabled.withOpacity(0.7),
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    isDense: true,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Controles ABAJO (como Cursor) - Row flexible para evitar overflow
            Row(
              children: [
                // Controles izquierda (flexibles)
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Selector Agent / Ask (estilo Cursor)
                        _buildModeSelector(),

                        const SizedBox(width: 8),

                        // Selector de modelo (estilo Cursor - pill button)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              _closeOverlay();
                              _showModelSelector();
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: CursorTheme.background.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: CursorTheme.border.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.psychology_outlined,
                                    size: 14,
                                    color: CursorTheme.textSecondary.withOpacity(0.8),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _getModelDisplayName(_currentModel),
                                    style: TextStyle(
                                      color: CursorTheme.textSecondary.withOpacity(0.9),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 14,
                                    color: CursorTheme.textSecondary.withOpacity(0.6),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 8),
                        
                        // Toggle Auto (estilo Cursor - pill button)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () async {
                              setState(() {
                                _autoMode = !_autoMode;
                              });
                              await SettingsService.saveAutoMode(_autoMode);
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _autoMode 
                                    ? CursorTheme.primary.withOpacity(0.2)
                                    : CursorTheme.background.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _autoMode
                                      ? CursorTheme.primary.withOpacity(0.5)
                                      : CursorTheme.border.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Auto',
                                    style: TextStyle(
                                      color: _autoMode
                                          ? CursorTheme.primary
                                          : CursorTheme.textSecondary.withOpacity(0.9),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 14,
                                    color: _autoMode
                                        ? CursorTheme.primary.withOpacity(0.8)
                                        : CursorTheme.textSecondary.withOpacity(0.6),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 4),

                        // @ → inserta "@" y abre el menú de contexto (Docs incluido)
                        _CompactIconButton(
                          tooltip: 'Add context (@)',
                          onTap: _insertAtMention,
                          child: Text(
                            '@',
                            style: TextStyle(
                              color: CursorTheme.textSecondary.withOpacity(0.85),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1,
                            ),
                          ),
                        ),
                        if (widget.onAttachImage != null)
                          _CompactIconButton(
                            tooltip: 'Adjuntar imagen',
                            onTap: widget.onAttachImage!,
                            child: Icon(
                              Icons.image_outlined,
                              size: 15,
                              color: CursorTheme.textSecondary.withOpacity(0.85),
                            ),
                          ),
                        if (widget.onAttachFile != null)
                          _CompactIconButton(
                            tooltip: 'Adjuntar archivo',
                            onTap: widget.onAttachFile!,
                            child: Icon(
                              Icons.insert_drive_file_outlined,
                              size: 15,
                              color: CursorTheme.textSecondary.withOpacity(0.85),
                            ),
                          ),
                        _CompactIconButton(
                          tooltip: 'Docs (URL de documentación)',
                          onTap: () {
                            _closeOverlay();
                            _showDocumentationSelector();
                          },
                          child: Icon(
                            Icons.menu_book_outlined,
                            size: 15,
                            color: CursorTheme.textSecondary.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(width: 6),
                
                // Botón enviar/stop (estilo Cursor) - compacto
                Material(
                  color: widget.isLoading 
                      ? Colors.red.withOpacity(0.9)
                      : CursorTheme.primary,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    onTap: widget.isLoading 
                        ? (widget.onStop ?? () {})
                        : widget.onSend,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      child: widget.isLoading
                          ? const Icon(Icons.stop, size: 14, color: Colors.white)
                          : const Icon(Icons.send, size: 13, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildModeSelector() {
    final isAgent = widget.chatMode == ChatAgentMode.agent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onChatModeChanged == null
            ? null
            : () {
                final next = isAgent ? ChatAgentMode.ask : ChatAgentMode.agent;
                widget.onChatModeChanged!(next);
              },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isAgent
                ? CursorTheme.primary.withOpacity(0.15)
                : CursorTheme.background.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isAgent
                  ? CursorTheme.primary.withOpacity(0.45)
                  : CursorTheme.border.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAgent ? Icons.smart_toy_outlined : Icons.chat_bubble_outline,
                size: 14,
                color: isAgent
                    ? CursorTheme.primary
                    : CursorTheme.textSecondary.withOpacity(0.8),
              ),
              const SizedBox(width: 6),
              Text(
                isAgent ? 'Agent' : 'Ask',
                style: TextStyle(
                  color: isAgent
                      ? CursorTheme.primary
                      : CursorTheme.textSecondary.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getModelDisplayName(String model) {
    switch (model) {
      case 'gpt-4o-mini':
        return 'GPT-4o Mini';
      case 'gpt-4o':
        return 'GPT-4o';
      case 'gpt-4.1':
        return 'GPT-4.1';
      case 'o4-mini':
        return 'o4-mini';
      case 'gpt-4-turbo':
        return 'GPT-4 Turbo';
      case 'gpt-4':
        return 'GPT-4';
      case 'gpt-3.5-turbo':
        return 'GPT-3.5 Turbo';
      default:
        return model;
    }
  }
}

/// Botón de acción compacto (estilo Cursor) para @ / imagen / archivo / docs.
class _CompactIconButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final String? tooltip;

  const _CompactIconButton({
    required this.child,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(child: child),
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}


