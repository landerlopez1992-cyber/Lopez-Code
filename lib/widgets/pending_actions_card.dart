import 'package:flutter/material.dart';
import '../models/pending_action.dart';
import 'cursor_theme.dart';

/// Tarjeta que muestra acciones pendientes en el chat
/// Similar a Cursor IDE - muestra acciones con botones para aceptar/rechazar
class PendingActionsCard extends StatelessWidget {
  final List<PendingAction> pendingActions;
  final Function(List<PendingAction>) onAccept;
  final Function() onReject;

  const PendingActionsCard({
    super.key,
    required this.pendingActions,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final rejectButton = TextButton(
      onPressed: onReject,
      style: TextButton.styleFrom(
        foregroundColor: Colors.red,
        alignment: Alignment.center,
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.close, size: 16),
          SizedBox(width: 4),
          Text('Rechazar'),
        ],
      ),
    );

    final acceptButton = ElevatedButton.icon(
      onPressed: () => onAccept(pendingActions),
      icon: const Icon(Icons.check, size: 16),
      label: const Text('Aceptar y Ejecutar'),
      style: ElevatedButton.styleFrom(
        backgroundColor: CursorTheme.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      constraints: const BoxConstraints(maxWidth: 600),
      decoration: BoxDecoration(
        color: CursorTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CursorTheme.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Acciones Pendientes de Confirmación',
                    style: const TextStyle(
                      color: CursorTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${pendingActions.length}',
                  style: TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          
          // Lista de acciones
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'La IA quiere ejecutar las siguientes acciones:',
                  style: TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                ...pendingActions.map((action) {
                  return _buildActionItem(action);
                }).toList(),
              ],
            ),
          ),
          
          // Botones de acción
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: CursorTheme.background,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 420;
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: double.infinity, child: acceptButton),
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity, child: rejectButton),
                    ],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    rejectButton,
                    const SizedBox(width: 8),
                    acceptButton,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(PendingAction action) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CursorTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: action.getRiskColor().withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header de la acción
          Row(
            children: [
              Icon(
                action.getActionIcon(),
                size: 16,
                color: action.getActionColor(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  action.getActionSummary(),
                  style: const TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Badge de riesgo
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: action.getRiskColor().withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: action.getRiskColor().withOpacity(0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      action.getRiskIcon(),
                      size: 10,
                      color: action.getRiskColor(),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      action.getRiskText(),
                      style: TextStyle(
                        color: action.getRiskColor(),
                        fontSize: 9,
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
            const SizedBox(height: 6),
            Text(
              action.description,
              style: TextStyle(
                color: CursorTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          
          // Archivo afectado
          if (action.arguments.containsKey('file_path')) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
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
        ],
      ),
    );
  }
}
