import 'package:flutter/material.dart';
import 'cursor_theme.dart';
import 'model_selector.dart';
import 'documentation_selector.dart';
import '../services/settings_service.dart';

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
  });

  @override
  State<CursorChatInput> createState() => _CursorChatInputState();
}

class _CursorChatInputState extends State<CursorChatInput> {
  String _currentModel = 'gpt-4o-mini';
  bool _autoMode = false;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    final model = await SettingsService.getSelectedModel();
    final autoMode = await SettingsService.getAutoMode();
    setState(() {
      _currentModel = model;
      _autoMode = autoMode;
    });
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
      
      // Posición Y: DEBAJO del botón
      final top = offset.dy + renderBox.size.height + 4; // 4px de margen debajo
      
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
                    setState(() {
                      _autoMode = auto;
                    });
                    await SettingsService.saveAutoMode(auto);
                    // Recalcular posición del overlay cuando cambia Auto
                    _overlayEntry?.markNeedsBuild();
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
          // Selector de documentación
          Positioned(
            left: offset.dx - 400 + size.width,
            top: offset.dy - 500,
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

  @override
  void dispose() {
    _closeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _closeOverlay,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: CursorTheme.surface,
          border: Border(
            top: BorderSide(color: CursorTheme.border, width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Botón de selector de modelo
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _closeOverlay();
                  _showModelSelector();
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.psychology_outlined,
                        size: 18,
                        color: CursorTheme.textSecondary.withOpacity(0.8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getModelDisplayName(_currentModel),
                        style: TextStyle(
                          color: CursorTheme.textSecondary.withOpacity(0.8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            
            // Botón @ para documentación
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _closeOverlay();
                  _showDocumentationSelector();
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '@',
                    style: TextStyle(
                      color: CursorTheme.textSecondary.withOpacity(0.8),
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            
            // Botones de adjuntar (más discretos como Cursor)
            if (widget.onAttachImage != null || widget.onAttachFile != null) ...[
              if (widget.onAttachImage != null)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onAttachImage,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.image_outlined,
                        size: 18,
                        color: CursorTheme.textSecondary.withOpacity(0.8),
                      ),
                    ),
                  ),
                ),
              if (widget.onAttachFile != null)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onAttachFile,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.insert_drive_file_outlined,
                        size: 18,
                        color: CursorTheme.textSecondary.withOpacity(0.8),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
            ],
            // Campo de texto (estilo Cursor)
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: CursorTheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: CursorTheme.border.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: widget.controller,
                  style: const TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 13,
                    height: 1.5, // Mejor interlineado
                  ),
                  maxLines: null,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => widget.onSend(),
                  onTap: _closeOverlay,
                  decoration: InputDecoration(
                    hintText: widget.placeholder ?? 'Plan, @ for context, / for commands',
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
            const SizedBox(width: 10),
            // Botón enviar/stop (estilo Cursor más pulido)
            Material(
              color: widget.isLoading 
                  ? Colors.red.withOpacity(0.9)
                  : CursorTheme.primary,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: widget.isLoading 
                    ? (widget.onStop ?? () {})
                    : widget.onSend,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  child: widget.isLoading
                      ? const Icon(Icons.stop, size: 18, color: Colors.white)
                      : const Icon(Icons.send, size: 18, color: Colors.white),
                ),
              ),
            ),
          ],
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


