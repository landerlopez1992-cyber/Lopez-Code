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
    return Container(
      width: 340,
      constraints: BoxConstraints(
        maxHeight: _autoMode ? 180 : 520, // Más compacto cuando Auto está activo
      ),
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CursorTheme.border.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barra de búsqueda (solo visible cuando Auto está desactivado)
          if (!_autoMode)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: CursorTheme.border.withOpacity(0.5),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    size: 16,
                    color: CursorTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      style: TextStyle(
                        color: CursorTheme.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search models',
                        hintStyle: TextStyle(
                          color: CursorTheme.textSecondary.withOpacity(0.7),
                          fontSize: 13,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: _autoMode ? null : Border(
                bottom: BorderSide(
                  color: CursorTheme.border.withOpacity(0.5),
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
          
          // Mensaje cuando Auto está activo
          if (_autoMode)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 48,
                    color: CursorTheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Modo Automático',
                    style: TextStyle(
                      color: CursorTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'El sistema seleccionará el mejor modelo según el contexto',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: CursorTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          
          // Lista de modelos (solo visible cuando Auto está desactivado)
          if (!_autoMode)
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _availableModels.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  thickness: 1,
                  color: CursorTheme.border.withOpacity(0.3),
                  indent: 16,
                  endIndent: 16,
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
        ],
      ),
    );
  }

  Widget _buildToggle(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome,
              size: 16,
              color: value ? CursorTheme.primary : CursorTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 13,
                fontWeight: value ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Container(
            width: 48,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: value
                  ? LinearGradient(
                      colors: [
                        CursorTheme.primary,
                        CursorTheme.primary.withOpacity(0.8),
                      ],
                    )
                  : null,
              color: value ? null : CursorTheme.background,
              border: Border.all(
                color: value
                    ? CursorTheme.primary
                    : CursorTheme.border.withOpacity(0.5),
                width: 1.5,
              ),
              boxShadow: value
                  ? [
                      BoxShadow(
                        color: CursorTheme.primary.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  left: value ? 24 : 2,
                  top: 2,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
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
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? CursorTheme.primary.withOpacity(0.08)
                  : _isHovered
                      ? CursorTheme.background
                      : Colors.transparent,
            ),
            child: Row(
              children: [
                // Icono del modelo
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? CursorTheme.primary.withOpacity(0.15)
                        : _isHovered
                            ? CursorTheme.surface
                            : CursorTheme.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: widget.isSelected
                          ? CursorTheme.primary.withOpacity(0.4)
                          : CursorTheme.border.withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    widget.model.hasBrain
                        ? Icons.psychology
                        : Icons.smart_toy_outlined,
                    size: 20,
                    color: widget.isSelected
                        ? CursorTheme.primary
                        : _isHovered
                            ? CursorTheme.textPrimary
                            : CursorTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: 14),
                // Información del modelo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.model.name,
                        style: TextStyle(
                          color: CursorTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: widget.isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (widget.model.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.model.description!,
                          style: TextStyle(
                            color: CursorTheme.textSecondary.withOpacity(0.85),
                            fontSize: 11.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Check para el seleccionado
                AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  scale: widget.isSelected ? 1.0 : 0.0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          CursorTheme.primary,
                          CursorTheme.primary.withOpacity(0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: CursorTheme.primary.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 14,
                      color: Colors.white,
                    ),
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
