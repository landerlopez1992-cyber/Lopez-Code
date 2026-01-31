import 'package:flutter/foundation.dart';

/// Servicio compartido para el Debug Console Panel
/// Permite que ChatScreen actualice el panel en MultiChatScreen
class DebugConsoleService extends ChangeNotifier {
  static final DebugConsoleService _instance = DebugConsoleService._internal();
  factory DebugConsoleService() => _instance;
  DebugConsoleService._internal();

  double _panelHeight = 250.0; // Visible por defecto con altura 250
  List<String> _output = [];
  List<String> _debugConsole = [];
  List<String> _problems = [];
  bool _isVisible = true; // Visible por defecto
  bool _isRunning = false;
  String? _appUrl; // URL de la app ejecutándose (para web)
  double _compilationProgress = 0.0; // Progreso de compilación (0.0 - 1.0)
  String _compilationStatus = ''; // Estado actual de compilación

  double get panelHeight => _panelHeight;
  List<String> get output => List.unmodifiable(_output);
  List<String> get debugConsole => List.unmodifiable(_debugConsole);
  List<String> get problems => List.unmodifiable(_problems);
  bool get isVisible => _isVisible;
  bool get isRunning => _isRunning;
  String? get appUrl => _appUrl;
  double get compilationProgress => _compilationProgress;
  String get compilationStatus => _compilationStatus;

  void setPanelHeight(double height) {
    _panelHeight = height;
    _isVisible = height > 0;
    notifyListeners();
  }

  void addOutput(String line) {
    _output.add(line);
    notifyListeners();
  }

  void addDebugConsole(String line) {
    _debugConsole.add(line);
    notifyListeners();
  }

  void addProblem(String problem) {
    _problems.add(problem);
    notifyListeners();
  }

  void clearOutput() {
    _output.clear();
    notifyListeners();
  }

  void clearDebugConsole() {
    _debugConsole.clear();
    notifyListeners();
  }

  void clearProblems() {
    _problems.clear();
    notifyListeners();
  }

  void clearAll() {
    _output.clear();
    _debugConsole.clear();
    _problems.clear();
    notifyListeners();
  }

  void openPanel() {
    if (_panelHeight == 0) {
      _panelHeight = 200.0;
      _isVisible = true;
      notifyListeners();
    }
  }

  void closePanel() {
    _panelHeight = 0.0;
    _isVisible = false;
    notifyListeners();
  }

  void togglePanel() {
    if (_panelHeight > 0) {
      closePanel();
    } else {
      openPanel();
    }
  }

  void setRunning(bool running) {
    if (_isRunning != running) {
      _isRunning = running;
      notifyListeners();
    }
  }

  void setAppUrl(String? url) {
    if (_appUrl != url) {
      print('🌐 DebugConsoleService.setAppUrl: "$_appUrl" -> "$url"');
      _appUrl = url;
      notifyListeners();
      print('✅ URL actualizada, notificando listeners...');
    }
  }

  void setCompilationProgress(double progress, String status) {
    if (_compilationProgress != progress || _compilationStatus != status) {
      _compilationProgress = progress.clamp(0.0, 1.0);
      _compilationStatus = status;
      notifyListeners();
    }
  }

  void resetCompilationProgress() {
    _compilationProgress = 0.0;
    _compilationStatus = '';
    notifyListeners();
  }
}
