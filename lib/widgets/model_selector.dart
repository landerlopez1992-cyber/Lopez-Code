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
      width: 320,
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
          // Barra de búsqueda
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
            child: TextField(
              style: TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Search models',
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
            ),
          ),
          
          // Toggles
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: CursorTheme.border,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                _buildToggle('Auto', _autoMode, (value) {
                  setState(() {
                    _autoMode = value;
                  });
                  widget.onAutoChanged(value);
                }),
                const SizedBox(height: 8),
                _buildToggle('MAX Mode', false, (value) {
                  // TODO: Implementar MAX Mode
                }),
                const SizedBox(height: 8),
                _buildToggle('Use Multiple Models', false, (value) {
                  // TODO: Implementar múltiples modelos
                }),
              ],
            ),
          ),
          
          // Lista de modelos
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _availableModels.length,
              itemBuilder: (context, index) {
                final model = _availableModels[index];
                final isSelected = _selectedModel == model.id;
                
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedModel = model.id;
                    });
                    widget.onModelChanged(model.id);
                    SettingsService.saveSelectedModel(model.id);
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                model.name,
                                style: TextStyle(
                                  color: CursorTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              if (model.description != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  model.description!,
                                  style: TextStyle(
                                    color: CursorTheme.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (model.hasBrain)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.psychology,
                              size: 16,
                              color: CursorTheme.primary,
                            ),
                          ),
                        if (isSelected)
                          Icon(
                            Icons.check,
                            size: 18,
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

  Widget _buildToggle(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: CursorTheme.textPrimary,
            fontSize: 13,
          ),
        ),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Container(
            width: 44,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: value
                  ? CursorTheme.primary
                  : CursorTheme.surface.withOpacity(0.5),
              border: Border.all(
                color: value
                    ? CursorTheme.primary
                    : CursorTheme.border,
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  left: value ? 22 : 2,
                  top: 2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
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
