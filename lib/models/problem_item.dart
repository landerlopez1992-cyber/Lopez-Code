/// Diagnóstico estructurado de `flutter analyze` / Dart analyzer.
enum ProblemSeverity { error, warning, info }

class ProblemItem {
  /// Ruta relativa al proyecto (p. ej. `lib/main.dart`).
  final String filePath;
  final int line;
  final int column;
  final ProblemSeverity severity;
  final String message;
  final String code;

  const ProblemItem({
    required this.filePath,
    required this.line,
    required this.column,
    required this.severity,
    required this.message,
    this.code = '',
  });

  factory ProblemItem.fromSeverityString({
    required String filePath,
    required int line,
    required int column,
    required String severity,
    required String message,
    String code = '',
  }) {
    return ProblemItem(
      filePath: filePath,
      line: line,
      column: column,
      severity: parseSeverity(severity),
      message: message,
      code: code,
    );
  }

  static ProblemSeverity parseSeverity(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'error':
      case 'errores':
        return ProblemSeverity.error;
      case 'warning':
      case 'warn':
      case 'advertencia':
        return ProblemSeverity.warning;
      default:
        return ProblemSeverity.info;
    }
  }

  String get severityLabel {
    switch (severity) {
      case ProblemSeverity.error:
        return 'error';
      case ProblemSeverity.warning:
        return 'warning';
      case ProblemSeverity.info:
        return 'info';
    }
  }

  /// Representación estilo analyzer: `lib/a.dart:10:5: error: message (code)`
  @override
  String toString() {
    final codeSuffix = code.isNotEmpty ? ' ($code)' : '';
    if (filePath.isEmpty) {
      return '$severityLabel: $message$codeSuffix';
    }
    return '$filePath:$line:$column: $severityLabel: $message$codeSuffix';
  }

  ProblemItem copyWith({
    String? filePath,
    int? line,
    int? column,
    ProblemSeverity? severity,
    String? message,
    String? code,
  }) {
    return ProblemItem(
      filePath: filePath ?? this.filePath,
      line: line ?? this.line,
      column: column ?? this.column,
      severity: severity ?? this.severity,
      message: message ?? this.message,
      code: code ?? this.code,
    );
  }
}
