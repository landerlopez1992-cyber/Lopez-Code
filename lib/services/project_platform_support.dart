import 'dart:io';

/// Detecta qué targets Flutter tiene un proyecto (carpetas de plataforma).
class ProjectPlatformSupport {
  ProjectPlatformSupport._();

  static const List<String> knownPlatforms = [
    'macos',
    'web',
    'ios',
    'android',
    'windows',
    'linux',
  ];

  /// Orden de preferencia al auto-seleccionar un target compatible.
  /// Android/iOS antes que Web para no “saltar” a Web sin pedirlo.
  static const List<String> preferenceOrder = [
    'macos',
    'android',
    'ios',
    'web',
    'windows',
    'linux',
  ];

  /// Devuelve el set de plataformas con carpeta presente en el proyecto.
  static Future<Set<String>> detectSupportedPlatforms(String projectPath) async {
    final supported = <String>{};
    final root = projectPath.replaceAll('\\', '/');
    for (final platform in knownPlatforms) {
      final dir = Directory('$root/$platform');
      try {
        if (await dir.exists()) {
          supported.add(platform);
        }
      } catch (_) {}
    }
    return supported;
  }

  /// Elige una plataforma compatible. Prefiere [requested] si está soportada.
  static String? preferPlatform(
    Set<String> supported, {
    String? requested,
  }) {
    if (supported.isEmpty) return null;
    if (requested != null &&
        requested.isNotEmpty &&
        supported.contains(requested.toLowerCase())) {
      return requested.toLowerCase();
    }
    for (final platform in preferenceOrder) {
      if (supported.contains(platform)) return platform;
    }
    return supported.first;
  }

  /// Normaliza variantes Preview/Nativo → carpeta del proyecto.
  /// `android` / `android_native` → android; `ios` / `ios_native` → ios.
  static String basePlatform(String platform) {
    final p = platform.toLowerCase().trim();
    if (p.startsWith('android')) return 'android';
    if (p.startsWith('ios')) return 'ios';
    return p;
  }

  /// Preview embebido (web-server dentro del marco de teléfono).
  static bool isEmbeddedMobilePreview(String platform) {
    final p = platform.toLowerCase().trim();
    return p == 'android' || p == 'ios';
  }

  /// Emulador/simulador nativo externo (Android Studio / Xcode).
  static bool isNativeMobileTarget(String platform) {
    final p = platform.toLowerCase().trim();
    return p == 'android_native' || p == 'ios_native';
  }

  static String humanLabel(String platform) {
    switch (platform.toLowerCase()) {
      case 'macos':
        return 'macOS';
      case 'ios':
        return 'iOS (Preview)';
      case 'ios_native':
        return 'iOS (Simulador)';
      case 'android':
        return 'Android (Preview)';
      case 'android_native':
        return 'Android (Emulador Nativo)';
      case 'web':
        return 'Web';
      case 'windows':
        return 'Windows';
      case 'linux':
        return 'Linux';
      default:
        return platform;
    }
  }

  static String missingFolderHint(String platform, Set<String> supported) {
    final base = basePlatform(platform);
    final label = humanLabel(platform);
    final alternatives = supported.isEmpty
        ? 'ninguna carpeta de plataforma detectada'
        : supported.map(humanLabel).join(', ');
    return 'Este proyecto no tiene carpeta $base/ (requerida para $label).\n'
        'Plataformas disponibles: $alternatives.';
  }

  /// ¿El proyecto tiene la carpeta de esa plataforma (ignorando _native)?
  static bool isSupportedVariant(String platform, Set<String> supported) {
    return supported.contains(basePlatform(platform));
  }
}
