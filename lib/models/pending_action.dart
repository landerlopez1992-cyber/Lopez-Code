import 'package:flutter/material.dart';

class PendingAction {
  final String id;
  final String functionName; // 'edit_file', 'create_file', 'read_file', etc.
  final Map<String, dynamic> arguments;
  final String description; // Descripción en lenguaje humano de qué va a hacer
  final DateTime timestamp;
  final String? toolCallId; // ID del tool_call de OpenAI para asociar respuesta
  final String riskLevel; // 'LOW', 'MEDIUM', 'HIGH'
  final List<String> affectedFiles; // Lista de archivos que se verán afectados
  final String? reasoning; // Por qué se propone este cambio
  final String? diff; // Diff del cambio (para edit_file)
  final String? oldContent; // Contenido anterior (para rollback)
  final String? newContent; // Contenido nuevo

  PendingAction({
    required this.id,
    required this.functionName,
    required this.arguments,
    required this.description,
    required this.timestamp,
    this.toolCallId,
    String? riskLevel,
    this.affectedFiles = const [],
    this.reasoning,
    this.diff,
    this.oldContent,
    this.newContent,
  }) : riskLevel = riskLevel ?? _calculateRiskLevel(functionName, arguments);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'functionName': functionName,
      'arguments': arguments,
      'description': description,
      'timestamp': timestamp.toIso8601String(),
      'toolCallId': toolCallId,
      'riskLevel': riskLevel,
      'affectedFiles': affectedFiles,
      'reasoning': reasoning,
      'diff': diff,
      'oldContent': oldContent,
      'newContent': newContent,
    };
  }

  factory PendingAction.fromJson(Map<String, dynamic> json) {
    return PendingAction(
      id: json['id'],
      functionName: json['functionName'],
      arguments: Map<String, dynamic>.from(json['arguments']),
      description: json['description'],
      timestamp: DateTime.parse(json['timestamp']),
      toolCallId: json['toolCallId'],
      riskLevel: json['riskLevel'],
      affectedFiles: json['affectedFiles'] != null 
          ? List<String>.from(json['affectedFiles']) 
          : [],
      reasoning: json['reasoning'],
      diff: json['diff'],
      oldContent: json['oldContent'],
      newContent: json['newContent'],
    );
  }

  /// Determina el nivel de riesgo basado en el tipo de acción y archivos afectados
  static String _calculateRiskLevel(String functionName, Map<String, dynamic> arguments) {
    // Archivos críticos que requieren confirmación extra
    final criticalFiles = [
      'pubspec.yaml',
      'main.dart',
      'build.gradle',
      'Info.plist',
      '.gitignore',
      '.env',
      'AndroidManifest.xml',
      'Podfile',
    ];

    // Operaciones de alto riesgo
    if (functionName == 'delete_file' || 
        functionName == 'delete_folder' ||
        functionName == 'execute_command') {
      return 'HIGH';
    }

    // Verificar si afecta archivos críticos
    final filePath = arguments['file_path'] as String?;
    if (filePath != null) {
      final fileName = filePath.split('/').last;
      if (criticalFiles.any((critical) => fileName.contains(critical))) {
        return 'HIGH';
      }
    }

    // Operaciones de medio riesgo
    if (functionName == 'edit_file' || 
        functionName == 'compile_project' ||
        functionName == 'download_file') {
      return 'MEDIUM';
    }

    // Operaciones de bajo riesgo
    return 'LOW';
  }

  /// Obtiene el color asociado al nivel de riesgo
  Color getRiskColor() {
    switch (riskLevel) {
      case 'HIGH':
        return Colors.red;
      case 'MEDIUM':
        return Colors.orange;
      case 'LOW':
      default:
        return Colors.green;
    }
  }

  /// Obtiene el icono asociado al nivel de riesgo
  IconData getRiskIcon() {
    switch (riskLevel) {
      case 'HIGH':
        return Icons.error_outline;
      case 'MEDIUM':
        return Icons.warning_amber_outlined;
      case 'LOW':
      default:
        return Icons.check_circle_outline;
    }
  }

  /// Obtiene el texto descriptivo del nivel de riesgo
  String getRiskText() {
    switch (riskLevel) {
      case 'HIGH':
        return 'ALTO RIESGO';
      case 'MEDIUM':
        return 'RIESGO MEDIO';
      case 'LOW':
      default:
        return 'BAJO RIESGO';
    }
  }

  // Helper para obtener descripción amigable según el tipo de acción
  String getActionSummary() {
    switch (functionName) {
      case 'edit_file':
        final filePath = arguments['file_path'] as String? ?? 'archivo';
        return 'Editar archivo: $filePath';
      case 'create_file':
        final filePath = arguments['file_path'] as String? ?? 'nuevo archivo';
        return 'Crear archivo: $filePath';
      case 'read_file':
        final filePath = arguments['file_path'] as String? ?? 'archivo';
        return 'Leer archivo: $filePath';
      case 'compile_project':
        final platform = arguments['platform'] as String? ?? 'macos';
        final mode = arguments['mode'] as String? ?? 'debug';
        return 'Compilar proyecto ($platform, $mode)';
      case 'execute_command':
        final command = arguments['command'] as String? ?? 'comando';
        return 'Ejecutar comando: $command';
      case 'download_file':
        final url = arguments['url'] as String? ?? 'URL';
        return 'Descargar archivo desde: $url';
      case 'navigate_web':
        final url = arguments['url'] as String? ?? 'URL';
        return 'Navegar a: $url';
      default:
        return 'Ejecutar: $functionName';
    }
  }

  /// Obtiene el icono de la acción
  IconData getActionIcon() {
    switch (functionName) {
      case 'edit_file':
        return Icons.edit;
      case 'create_file':
        return Icons.add_circle_outline;
      case 'read_file':
        return Icons.visibility;
      case 'compile_project':
        return Icons.build;
      case 'execute_command':
        return Icons.terminal;
      case 'download_file':
        return Icons.download;
      case 'navigate_web':
        return Icons.language;
      default:
        return Icons.code;
    }
  }

  /// Obtiene el color de la acción
  Color getActionColor() {
    switch (functionName) {
      case 'edit_file':
        return Colors.orange;
      case 'create_file':
        return Colors.green;
      case 'read_file':
        return Colors.blue;
      case 'compile_project':
        return Colors.purple;
      case 'execute_command':
        return Colors.teal;
      case 'download_file':
        return Colors.indigo;
      case 'navigate_web':
        return Colors.cyan;
      default:
        return Colors.grey;
    }
  }
}
