import 'package:flutter/material.dart';
import '../models/pending_action.dart';
import 'cursor_theme.dart';

class ConfirmationDialog extends StatelessWidget {
  final List<PendingAction> pendingActions;
  final Function(List<PendingAction> acceptedActions) onConfirm;
  final Function() onReject;

  const ConfirmationDialog({
    super.key,
    required this.pendingActions,
    required this.onConfirm,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: CursorTheme.surface,
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, 
            color: Colors.orange, 
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Confirmar Acciones',
              style: const TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500, // ✅ FIX: Ancho fijo en lugar de constraints
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400), // ✅ FIX: Solo maxHeight
          child: SingleChildScrollView( // ✅ FIX: ScrollView para evitar overflow
            child: Column(
              mainAxisSize: MainAxisSize.min, // ✅ FIX: Tamaño mínimo
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'La IA quiere ejecutar las siguientes acciones:',
                  style: const TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                // ✅ FIX: Usar Column en lugar de ListView para evitar problemas de layout
                ...pendingActions.map((action) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: CursorTheme.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: action.getRiskColor().withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header con icono, título y nivel de riesgo
                        Row(
                          children: [
                            Icon(
                              action.getActionIcon(),
                              size: 18,
                              color: action.getActionColor(),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                action.getActionSummary(),
                                style: const TextStyle(
                                  color: CursorTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            // Badge de nivel de riesgo
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: action.getRiskColor().withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: action.getRiskColor().withOpacity(0.5),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    action.getRiskIcon(),
                                    size: 12,
                                    color: action.getRiskColor(),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    action.getRiskText(),
                                    style: TextStyle(
                                      color: action.getRiskColor(),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // Descripción
                        if (action.description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            action.description,
                            style: const TextStyle(
                              color: CursorTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        // Razonamiento (por qué se propone)
                        if (action.reasoning != null && action.reasoning!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.blue.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.lightbulb_outline,
                                  size: 14,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    action.reasoning!,
                                    style: const TextStyle(
                                      color: CursorTheme.textSecondary,
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Archivo afectado
                        if (action.arguments.containsKey('file_path')) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.insert_drive_file,
                                size: 12,
                                color: CursorTheme.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  action.arguments['file_path'],
                                  style: TextStyle(
                                    color: CursorTheme.textSecondary.withOpacity(0.8),
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        // Mostrar diff si está disponible
                        if (action.diff != null && action.diff!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => _showDiffDialog(context, action),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: CursorTheme.codeBackground,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: CursorTheme.border,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.compare_arrows,
                                    size: 14,
                                    color: CursorTheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Ver cambios (diff)',
                                    style: TextStyle(
                                      color: CursorTheme.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 14,
                                    color: CursorTheme.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, 
                        size: 18, 
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Estas acciones se ejecutarán después de tu confirmación.',
                          style: const TextStyle(
                            color: CursorTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            onReject();
            Navigator.of(context).pop();
          },
          child: const Text(
            'Rechazar',
            style: TextStyle(color: Colors.red),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            onConfirm(pendingActions);
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: CursorTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Aceptar y Ejecutar'),
        ),
      ],
    );
  }

  /// Muestra un diálogo con el diff completo
  void _showDiffDialog(BuildContext context, PendingAction action) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CursorTheme.surface,
        title: Row(
          children: [
            Icon(
              Icons.compare_arrows,
              color: CursorTheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cambios Propuestos',
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Container(
          constraints: const BoxConstraints(
            maxWidth: 700,
            maxHeight: 500,
          ),
          width: 700,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Archivo
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CursorTheme.background,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.insert_drive_file,
                      size: 14,
                      color: CursorTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        action.arguments['file_path'] ?? 'archivo',
                        style: const TextStyle(
                          color: CursorTheme.textPrimary,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Diff
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CursorTheme.codeBackground,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: CursorTheme.border,
                      width: 1,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      action.diff ?? 'No hay diff disponible',
                      style: const TextStyle(
                        color: CursorTheme.textPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cerrar',
              style: TextStyle(color: CursorTheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

