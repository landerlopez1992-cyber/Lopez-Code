import 'package:flutter/foundation.dart';

import 'project_platform_support.dart';

/// Servicio compartido para la plataforma seleccionada
class PlatformService extends ChangeNotifier {
  static final PlatformService _instance = PlatformService._internal();
  factory PlatformService() => _instance;
  PlatformService._internal();

  String _selectedPlatform = 'web'; // Preview interno por defecto
  Set<String> _supportedPlatforms = {
    'macos',
    'ios',
    'android',
    'web',
  };

  String get selectedPlatform => _selectedPlatform;
  bool get isMobile {
    final p = _selectedPlatform.toLowerCase();
    return p.startsWith('android') || p.startsWith('ios');
  }

  /// Android/iOS Preview → web-server en el marco central.
  bool get isEmbeddedMobilePreview =>
      ProjectPlatformSupport.isEmbeddedMobilePreview(_selectedPlatform);

  Set<String> get supportedPlatforms =>
      Set<String>.unmodifiable(_supportedPlatforms);

  bool isPlatformSupported(String platform) =>
      ProjectPlatformSupport.isSupportedVariant(platform, _supportedPlatforms);

  void setPlatform(String platform) {
    if (_selectedPlatform != platform) {
      _selectedPlatform = platform;
      notifyListeners();
    }
  }

  /// Escanea carpetas del proyecto y actualiza plataformas soportadas.
  ///
  /// Respeta la selección del usuario (Android/iOS Preview o Nativo).
  Future<String?> refreshFromProject(String projectPath) async {
    final supported =
        await ProjectPlatformSupport.detectSupportedPlatforms(projectPath);
    _supportedPlatforms = supported.isEmpty
        ? {'android', 'ios', 'web', 'macos'}
        : supported;

    final current = _selectedPlatform.toLowerCase();
    // Mantener Preview/Nativo si la carpeta base existe.
    if (ProjectPlatformSupport.isSupportedVariant(
      current,
      _supportedPlatforms,
    )) {
      notifyListeners();
      return current;
    }

    final preferred = ProjectPlatformSupport.preferPlatform(
      _supportedPlatforms,
      requested: ProjectPlatformSupport.basePlatform(current),
    );
    if (preferred != null) {
      _selectedPlatform = preferred;
    }
    notifyListeners();
    return preferred ?? _selectedPlatform;
  }
}
