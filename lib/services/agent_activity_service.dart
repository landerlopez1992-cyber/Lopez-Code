import 'package:flutter/foundation.dart';

/// Estado en vivo de lo que el agente está haciendo AHORA.
///
/// Lo escuchan: explorador (pulso en archivo), editor (línea + banner) y
/// MultiChatScreen (barra “Agente trabajando…”).
class AgentActivityService extends ChangeNotifier {
  static final AgentActivityService _instance = AgentActivityService._();
  factory AgentActivityService() => _instance;
  AgentActivityService._();

  String? _activePath;
  int? _focusLine;
  String? _operation;
  String? _status;
  int _revision = 0;

  String? get activePath => _activePath;
  int? get focusLine => _focusLine;
  String? get operation => _operation;
  String? get status => _status;
  int get revision => _revision;

  /// Hay trabajo en curso (archivo, comando o compilación).
  bool get isBusy =>
      (_status != null && _status!.isNotEmpty) ||
      (_activePath != null && _activePath!.isNotEmpty);

  /// basename del archivo activo (para UI / matching débil).
  String? get activeBasename {
    final p = _activePath;
    if (p == null || p.isEmpty) return null;
    final norm = p.replaceAll('\\', '/');
    final parts = norm.split('/');
    return parts.isEmpty ? null : parts.last;
  }

  /// Texto corto para banners: "Editando pubspec.yaml · línea 18".
  String get bannerText {
    if (_status != null && _status!.trim().isNotEmpty) return _status!.trim();
    final name = activeBasename;
    if (name != null) {
      if (_focusLine != null) {
        return 'Agente trabajando en $name  ·  línea $_focusLine';
      }
      return 'Agente trabajando en $name';
    }
    return 'Agente trabajando…';
  }

  /// Archivo real (no "proyecto" / comandos).
  bool get hasFileTarget {
    final p = _activePath;
    if (p == null || p.isEmpty) return false;
    final lower = p.toLowerCase();
    if (lower == 'proyecto' ||
        lower == 'console' ||
        lower == 'flutter devices' ||
        lower.startsWith('http')) {
      return false;
    }
    return true;
  }

  void setActive(String? path, {int? line, String? operation, String? status}) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      if (status != null && status.trim().isNotEmpty) {
        setBusy(status, operation: operation);
        return;
      }
      clear();
      return;
    }
    _activePath = trimmed;
    _focusLine = line;
    _operation = operation ?? _operation;
    _status = status ?? _defaultStatusFor(operation, trimmed, line);
    _revision++;
    notifyListeners();
  }

  /// Trabajo sin archivo (compile, pub get, devices…).
  void setBusy(String status, {String? operation, String? detail}) {
    _operation = operation ?? _operation;
    _status = detail != null && detail.isNotEmpty
        ? '$status · $detail'
        : status;
    // No borrar el último archivo si solo estamos compilando: el usuario
    // aún puede ver dónde se editó; pero el banner muestra el status actual.
    if (operation == 'compilando' ||
        operation == 'ejecutando' ||
        operation == 'dispositivos' ||
        operation == 'listando' ||
        operation == 'logs' ||
        operation == 'ide') {
      _activePath = null;
      _focusLine = null;
    }
    _revision++;
    notifyListeners();
  }

  void clear() {
    if (_activePath == null &&
        _focusLine == null &&
        _status == null &&
        _operation == null) {
      return;
    }
    _activePath = null;
    _focusLine = null;
    _status = null;
    _operation = null;
    _revision++;
    notifyListeners();
  }

  String _defaultStatusFor(String? operation, String path, int? line) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final op = (operation ?? 'trabajando').toLowerCase();
    final lineBit = line != null ? '  ·  línea $line' : '';
    switch (op) {
      case 'editando':
      case 'archivo_actualizado':
        return 'Editando $name$lineBit';
      case 'creando':
        return 'Creando $name$lineBit';
      case 'leyendo':
        return 'Leyendo $name$lineBit';
      case 'inspeccionando imagen':
        return 'Inspeccionando $name';
      default:
        return 'Agente en $name$lineBit';
    }
  }
}
