import 'dart:async';
import 'package:flutter/material.dart';

/// Servicio de feedback visual de la IA
/// Proporciona indicadores de actividad y estado en tiempo real

class AIFeedbackService {
  // Stream controllers para feedback en tiempo real
  final _activityController = StreamController<AIActivity>.broadcast();
  final _suggestionController = StreamController<ProactiveSuggestion>.broadcast();
  final _thinkingController = StreamController<ThinkingProcess>.broadcast();

  Stream<AIActivity> get activityStream => _activityController.stream;
  Stream<ProactiveSuggestion> get suggestionStream => _suggestionController.stream;
  Stream<ThinkingProcess> get thinkingStream => _thinkingController.stream;

  AIActivity? _currentActivity;
  List<AIActivity> _activityHistory = [];
  List<ProactiveSuggestion> _suggestions = [];

  /// Reporta una actividad de la IA
  void reportActivity({
    required String action,
    required ActivityType type,
    String? filePath,
    Map<String, dynamic>? metadata,
  }) {
    final activity = AIActivity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      action: action,
      type: type,
      filePath: filePath,
      timestamp: DateTime.now(),
      metadata: metadata,
    );

    _currentActivity = activity;
    _activityHistory.add(activity);
    _activityController.add(activity);

    print('🤖 IA: $action ${filePath != null ? "($filePath)" : ""}');
  }

  /// Inicia un proceso de pensamiento
  void startThinking(String process, {String? context}) {
    final thinking = ThinkingProcess(
      process: process,
      context: context,
      startTime: DateTime.now(),
    );
    _thinkingController.add(thinking);
    print('💭 IA pensando: $process');
  }

  /// Finaliza el proceso de pensamiento
  void stopThinking() {
    // Enviar señal de fin
    _thinkingController.add(ThinkingProcess(
      process: '',
      startTime: DateTime.now(),
      isComplete: true,
    ));
  }

  /// Genera una sugerencia proactiva
  void suggestNext({
    required String suggestion,
    required SuggestionPriority priority,
    String? reasoning,
    String? actionCode,
    VoidCallback? onAccept,
  }) {
    final proactiveSuggestion = ProactiveSuggestion(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      suggestion: suggestion,
      priority: priority,
      reasoning: reasoning,
      actionCode: actionCode,
      onAccept: onAccept,
      timestamp: DateTime.now(),
    );

    _suggestions.add(proactiveSuggestion);
    _suggestionController.add(proactiveSuggestion);

    print('💡 Sugerencia: $suggestion (${priority.name})');
  }

  /// Genera sugerencias basadas en el contexto actual
  List<ProactiveSuggestion> generateContextualSuggestions({
    required String projectPath,
    List<String>? recentFiles,
    List<String>? recentErrors,
  }) {
    final suggestions = <ProactiveSuggestion>[];

    // Sugerencia 1: Si hay errores recientes
    if (recentErrors != null && recentErrors.isNotEmpty) {
      suggestions.add(ProactiveSuggestion(
        id: 'fix_errors_${DateTime.now().millisecondsSinceEpoch}',
        suggestion: 'Hay ${recentErrors.length} error(es) detectados. ¿Quieres que los analice?',
        priority: SuggestionPriority.high,
        reasoning: 'Errores encontrados durante la compilación',
        actionCode: 'ANALYZE_ERRORS',
        timestamp: DateTime.now(),
      ));
    }

    // Sugerencia 2: Si hay archivos sin tests
    suggestions.add(ProactiveSuggestion(
      id: 'add_tests_${DateTime.now().millisecondsSinceEpoch}',
      suggestion: '¿Quieres que genere tests para los archivos modificados recientemente?',
      priority: SuggestionPriority.medium,
      reasoning: 'Mejorar cobertura de tests',
      actionCode: 'GENERATE_TESTS',
      timestamp: DateTime.now(),
    ));

    // Sugerencia 3: Documentación
    if (recentFiles != null && recentFiles.isNotEmpty) {
      suggestions.add(ProactiveSuggestion(
        id: 'add_docs_${DateTime.now().millisecondsSinceEpoch}',
        suggestion: '¿Necesitas que documente las clases modificadas?',
        priority: SuggestionPriority.low,
        reasoning: 'Mantener código documentado',
        actionCode: 'ADD_DOCUMENTATION',
        timestamp: DateTime.now(),
      ));
    }

    // Sugerencia 4: Refactoring
    suggestions.add(ProactiveSuggestion(
      id: 'refactor_${DateTime.now().millisecondsSinceEpoch}',
      suggestion: '¿Quieres que analice oportunidades de refactoring?',
      priority: SuggestionPriority.low,
      reasoning: 'Mejorar calidad del código',
      actionCode: 'ANALYZE_REFACTORING',
      timestamp: DateTime.now(),
    ));

    return suggestions;
  }

  /// Obtiene el historial de actividades
  List<AIActivity> getActivityHistory({int? limit}) {
    if (limit != null && limit < _activityHistory.length) {
      return _activityHistory.reversed.take(limit).toList();
    }
    return _activityHistory.reversed.toList();
  }

  /// Limpia el historial
  void clearHistory() {
    _activityHistory.clear();
    _suggestions.clear();
  }

  /// Obtiene estadísticas de actividad
  ActivityStats getStats() {
    final stats = ActivityStats();

    for (var activity in _activityHistory) {
      switch (activity.type) {
        case ActivityType.reading:
          stats.filesRead++;
          break;
        case ActivityType.analyzing:
          stats.analyses++;
          break;
        case ActivityType.editing:
          stats.edits++;
          break;
        case ActivityType.creating:
          stats.creates++;
          break;
        case ActivityType.compiling:
          stats.compilations++;
          break;
        case ActivityType.testing:
          stats.tests++;
          break;
        case ActivityType.thinking:
          // Thinking no se cuenta en stats detalladas
          break;
      }
    }

    return stats;
  }

  void dispose() {
    _activityController.close();
    _suggestionController.close();
    _thinkingController.close();
  }
}

/// Tipos de actividad de la IA
enum ActivityType {
  reading,      // Leyendo archivos
  analyzing,    // Analizando código
  editing,      // Editando archivos
  creating,     // Creando archivos
  compiling,    // Compilando
  testing,      // Ejecutando tests
  thinking,     // Procesando/pensando
}

/// Prioridad de sugerencias
enum SuggestionPriority {
  high,    // Urgente/importante
  medium,  // Recomendado
  low,     // Opcional
}

/// Modelo de actividad de la IA
class AIActivity {
  final String id;
  final String action;
  final ActivityType type;
  final String? filePath;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  AIActivity({
    required this.id,
    required this.action,
    required this.type,
    this.filePath,
    required this.timestamp,
    this.metadata,
  });

  /// Icono asociado a la actividad
  IconData get icon {
    switch (type) {
      case ActivityType.reading:
        return Icons.folder_open;
      case ActivityType.analyzing:
        return Icons.analytics;
      case ActivityType.editing:
        return Icons.edit;
      case ActivityType.creating:
        return Icons.add_circle;
      case ActivityType.compiling:
        return Icons.build;
      case ActivityType.testing:
        return Icons.bug_report;
      case ActivityType.thinking:
        return Icons.psychology;
    }
  }

  /// Color asociado a la actividad
  Color get color {
    switch (type) {
      case ActivityType.reading:
        return Colors.blue;
      case ActivityType.analyzing:
        return Colors.purple;
      case ActivityType.editing:
        return Colors.orange;
      case ActivityType.creating:
        return Colors.green;
      case ActivityType.compiling:
        return Colors.deepPurple;
      case ActivityType.testing:
        return Colors.teal;
      case ActivityType.thinking:
        return Colors.amber;
    }
  }

  /// Texto descriptivo
  String get description {
    switch (type) {
      case ActivityType.reading:
        return 'Leyendo';
      case ActivityType.analyzing:
        return 'Analizando';
      case ActivityType.editing:
        return 'Editando';
      case ActivityType.creating:
        return 'Creando';
      case ActivityType.compiling:
        return 'Compilando';
      case ActivityType.testing:
        return 'Testeando';
      case ActivityType.thinking:
        return 'Pensando';
    }
  }
}

/// Proceso de pensamiento de la IA
class ThinkingProcess {
  final String process;
  final String? context;
  final DateTime startTime;
  final bool isComplete;

  ThinkingProcess({
    required this.process,
    this.context,
    required this.startTime,
    this.isComplete = false,
  });
}

/// Sugerencia proactiva de la IA
class ProactiveSuggestion {
  final String id;
  final String suggestion;
  final SuggestionPriority priority;
  final String? reasoning;
  final String? actionCode;
  final VoidCallback? onAccept;
  final DateTime timestamp;
  bool dismissed = false;

  ProactiveSuggestion({
    required this.id,
    required this.suggestion,
    required this.priority,
    this.reasoning,
    this.actionCode,
    this.onAccept,
    required this.timestamp,
  });

  /// Icono según prioridad
  IconData get icon {
    switch (priority) {
      case SuggestionPriority.high:
        return Icons.priority_high;
      case SuggestionPriority.medium:
        return Icons.lightbulb;
      case SuggestionPriority.low:
        return Icons.info_outline;
    }
  }

  /// Color según prioridad
  Color get color {
    switch (priority) {
      case SuggestionPriority.high:
        return Colors.red;
      case SuggestionPriority.medium:
        return Colors.orange;
      case SuggestionPriority.low:
        return Colors.blue;
    }
  }

  /// Texto de prioridad
  String get priorityText {
    switch (priority) {
      case SuggestionPriority.high:
        return 'URGENTE';
      case SuggestionPriority.medium:
        return 'RECOMENDADO';
      case SuggestionPriority.low:
        return 'OPCIONAL';
    }
  }
}

/// Estadísticas de actividad
class ActivityStats {
  int filesRead = 0;
  int analyses = 0;
  int edits = 0;
  int creates = 0;
  int compilations = 0;
  int tests = 0;

  int get total => filesRead + analyses + edits + creates + compilations + tests;

  @override
  String toString() {
    return '''
Actividad Total: $total
- Archivos leídos: $filesRead
- Análisis: $analyses
- Ediciones: $edits
- Creaciones: $creates
- Compilaciones: $compilations
- Tests: $tests
''';
  }
}
