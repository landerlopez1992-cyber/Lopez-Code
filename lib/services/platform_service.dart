import 'package:flutter/foundation.dart';

/// Servicio compartido para la plataforma seleccionada
class PlatformService extends ChangeNotifier {
  static final PlatformService _instance = PlatformService._internal();
  factory PlatformService() => _instance;
  PlatformService._internal();

  String _selectedPlatform = 'macos'; // Valor por defecto

  String get selectedPlatform => _selectedPlatform;
  bool get isMobile => _selectedPlatform == 'android' || _selectedPlatform == 'ios';

  void setPlatform(String platform) {
    if (_selectedPlatform != platform) {
      _selectedPlatform = platform;
      notifyListeners();
    }
  }
}
