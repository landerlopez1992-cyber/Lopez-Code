import 'package:flutter/material.dart';
import 'cursor_theme.dart';
import '../services/settings_service.dart';

/// Widget para seleccionar el modelo de IA
class ModelSelector extends StatefulWidget {
  final String currentModel;
  final Function(String) onModelChanged;
  final Function(bool) onAutoChanged;
  final bool autoMode;

  const ModelSelector({
    super.key,
    required this.currentModel,
    required this.onModelChanged,
    required this.onAutoChanged,
    this.autoMode = false,
  });

  @override
  State<ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<ModelSelector> {
  bool _autoMode = false;
  String _selectedModel = 'gpt-4o-mini';
  
  // Lista de modelos disponibles de OpenAI (oficial según docs)
  // Fuente: https://platform.openai.com/docs/models
  final List<AIModel> _availableModels = [
    AIModel(
      id: 'gpt-4o',
      name: 'GPT-4o',
      description: 'Más inteligente, más rápido, visión y audio',
      hasBrain: true,
    ),
    AIModel(
      id: 'gpt-4o-mini',
      name: 'GPT-4o Mini',
      description: 'Modelo asequible e inteligente',
      hasBrain: false,
    ),
    AIModel(
      id: 'gpt-4-turbo',
      name: 'GPT-4 Turbo',
      description: 'Modelo anterior con conocimiento hasta dic 2023',
      hasBrain: false,
    ),
    AIModel(
      id: 'gpt-4',
      name: 'GPT-4',
      description: 'Modelo base (conocimiento hasta sep 2021)',
      hasBrain: false,
    ),
    AIModel(
      id: 'gpt-3.5-turbo',
      name: 'GPT-3.5 Turbo',
      description: 'Rápido y económico para tareas simples',
      hasBrain: false,
    ),
    AIModel(
      id: 'o1',
      name: 'o1',
      description: 'Razonamiento complejo avanzado',
      hasBrain: true,
    ),
    AIModel(
      id: 'o1-mini',
      name: 'o1-mini',
      description: 'Razonamiento rápido más asequible',
      hasBrain: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _autoMode = widget.autoMode;
    _selectedModel = widget.currentModel;
  }

  @override
  void didUpdateWidget(ModelSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentModel != widget.currentModel) {
      _selectedModel = widget.currentModel;
    }
    if (oldWidget.autoMode != widget.autoMode) {
      _autoMode = widget.autoMode;
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = _autoMode ? 100.0 : 380.0;
    
    return Container(
      width: 260, // Más compacto como Cursor (foto 4)
      constraints: BoxConstraints(
        maxHeight: maxHeight,
      ),
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CursorTheme.border.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barra de búsqueda (solo visible cuando Auto está desactivado)
          if (!_autoMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: CursorTheme.border.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    size: 14,
                    color: CursorTheme.textSecondary.withOpacity(0.6),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      style: TextStyle(
                        color: CursorTheme.textPrimary,
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search models',
                        hintStyle: TextStyle(
                          color: CursorTheme.textSecondary.withOpacity(0.5),
                          fontSize: 12,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Toggle Auto
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: _autoMode ? null : Border(
                bottom: BorderSide(
                  color: CursorTheme.border.withOpacity(0.3),
                  width: 1,
                ),
              ),
            ),
            child: _buildToggle('Auto', _autoMode, (value) {
              setState(() {
                _autoMode = value;
              });
              widget.onAutoChanged(value);
            }),
          ),
          
          // Mensaje cuando Auto está activo (MUY compacto para evitar overflow)
          if (_autoMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(maxHeight: 50),
              child: Text(
                'Balanced quality and speed, recommended for most tasks.',
                style: TextStyle(
                  color: CursorTheme.textSecondary.withOpacity(0.6),
                  fontSize: 9.5,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          
          // Lista de modelos (solo visible cuando Auto está desactivado)
          if (!_autoMode)
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxHeight - 60, // Restar altura de búsqueda + toggle
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  itemCount: _availableModels.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: CursorTheme.border.withOpacity(0.15),
                    indent: 10,
                    endIndent: 10,
                  ),
                  itemBuilder: (context, index) {
                    final model = _availableModels[index];
                    final isSelected = _selectedModel == model.id;
                    
                    return _ModelSelectorItem(
                      model: model,
                      isSelected: isSelected,
                      onTap: () {
                        print('🎯 Modelo seleccionado en ModelSelector: ${model.id} (${model.name})');
                        setState(() {
                          _selectedModel = model.id;
                        });
                        widget.onModelChanged(model.id);
                        SettingsService.saveSelectedModel(model.id);
                        print('💾 Modelo guardado en SettingsService: ${model.id}');
                        // No cerramos aquí, el padre lo hace
                      },
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToggle(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: CursorTheme.textPrimary,
            fontSize: 11.5,
            fontWeight: value ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Container(
            width: 38,
            height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: value
                  ? CursorTheme.primary
                  : CursorTheme.background,
              border: Border.all(
                color: value
                    ? CursorTheme.primary
                    : CursorTheme.border.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  left: value ? 18 : 2,
                  top: 2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AIModel {
  final String id;
  final String name;
  final String? description;
  final bool hasBrain;

  AIModel({
    required this.id,
    required this.name,
    this.description,
    this.hasBrain = false,
  });
}

/// Item individual del selector de modelos con hover effect
class _ModelSelectorItem extends StatefulWidget {
  final AIModel model;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModelSelectorItem({
    required this.model,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_ModelSelectorItem> createState() => _ModelSelectorItemState();
}

class _ModelSelectorItemState extends State<_ModelSelectorItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? CursorTheme.primary.withOpacity(0.1)
                  : _isHovered
                      ? CursorTheme.background
                      : Colors.transparent,
            ),
            child: Row(
              children: [
                // Icono del modelo (más pequeño aún)
                if (widget.model.hasBrain)
                  Icon(
                    Icons.psychology,
                    size: 14,
                    color: CursorTheme.primary.withOpacity(0.7),
                  )
                else
                  SizedBox.shrink(), // Sin icono para modelos estándar (como Cursor)
                if (widget.model.hasBrain) const SizedBox(width: 8),
                // Información del modelo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.model.name,
                        style: TextStyle(
                          color: CursorTheme.textPrimary,
                          fontSize: 11.5,
                          fontWeight: widget.isSelected
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                      if (widget.model.description != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          widget.model.description!,
                          style: TextStyle(
                            color: CursorTheme.textSecondary.withOpacity(0.6),
                            fontSize: 9.5,
                            height: 1.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Check para el seleccionado (más pequeño)
                AnimatedScale(
                  duration: const Duration(milliseconds: 150),
                  scale: widget.isSelected ? 1.0 : 0.0,
                  child: Icon(
                    Icons.check,
                    size: 14,
                    color: CursorTheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
