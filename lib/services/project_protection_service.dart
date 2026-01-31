/// Servicio de protección de proyecto
/// Implementa reglas de seguridad para prevenir cambios destructivos
/// en archivos y directorios críticos del proyecto.

class ProjectProtectionService {
  /// Archivos críticos que requieren confirmación de alto riesgo
  static const List<String> criticalFiles = [
    'pubspec.yaml',
    'pubspec.lock',
    'main.dart',
    'build.gradle',
    'settings.gradle',
    'Info.plist',
    'Podfile',
    'Podfile.lock',
    '.gitignore',
    '.env',
    '.env.local',
    '.env.production',
    'AndroidManifest.xml',
    'project.pbxproj',
    'Runner.xcodeproj',
    'google-services.json',
    'GoogleService-Info.plist',
  ];

  /// Directorios críticos que no deben ser modificados
  static const List<String> protectedDirectories = [
    '.git',
    '.dart_tool',
    'build',
    'android/build',
    'ios/build',
    'macos/build',
    'web/build',
    'linux/build',
    'windows/build',
    '.idea',
    '.vscode',
    'node_modules',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
  ];

  /// Patrones de archivos que nunca deben ser modificados
  static const List<String> forbiddenPatterns = [
    r'\.git/',
    r'\.dart_tool/',
    r'/build/',
    r'\.lock$',
    r'\.g\.dart$', // Archivos generados
    r'\.freezed\.dart$', // Archivos generados por freezed
  ];

  /// Verifica si un archivo es crítico
  static bool isCriticalFile(String filePath) {
    final fileName = filePath.split('/').last;
    return criticalFiles.any((critical) => 
      fileName == critical || fileName.contains(critical)
    );
  }

  /// Verifica si un directorio está protegido
  static bool isProtectedDirectory(String dirPath) {
    return protectedDirectories.any((protected) => 
      dirPath.contains(protected)
    );
  }

  /// Verifica si un archivo coincide con un patrón prohibido
  static bool matchesForbiddenPattern(String filePath) {
    return forbiddenPatterns.any((pattern) {
      final regex = RegExp(pattern);
      return regex.hasMatch(filePath);
    });
  }

  /// Verifica si una operación es permitida en un archivo
  static ProtectionResult canModifyFile(String filePath, String operation) {
    // Verificar patrones prohibidos
    if (matchesForbiddenPattern(filePath)) {
      return ProtectionResult(
        allowed: false,
        reason: 'Este archivo es generado automáticamente o es parte de la configuración del sistema.',
        riskLevel: 'HIGH',
        requiresExtraConfirmation: true,
      );
    }

    // Verificar directorios protegidos
    if (isProtectedDirectory(filePath)) {
      return ProtectionResult(
        allowed: false,
        reason: 'Este directorio contiene archivos del sistema o generados automáticamente.',
        riskLevel: 'HIGH',
        requiresExtraConfirmation: true,
      );
    }

    // Verificar archivos críticos
    if (isCriticalFile(filePath)) {
      // Eliminar archivos críticos está prohibido
      if (operation == 'delete' || operation == 'delete_file') {
        return ProtectionResult(
          allowed: false,
          reason: 'No se puede eliminar un archivo crítico del proyecto.',
          riskLevel: 'HIGH',
          requiresExtraConfirmation: true,
        );
      }

      // Editar archivos críticos requiere confirmación extra
      if (operation == 'edit' || operation == 'edit_file') {
        return ProtectionResult(
          allowed: true,
          reason: 'Este es un archivo crítico del proyecto. Los cambios pueden afectar la configuración o compilación.',
          riskLevel: 'HIGH',
          requiresExtraConfirmation: true,
          warnings: [
            'Asegúrate de revisar cuidadosamente los cambios',
            'Un error en este archivo puede romper el proyecto',
            'Considera hacer un backup antes de continuar',
          ],
        );
      }
    }

    // Operaciones normales permitidas
    return ProtectionResult(
      allowed: true,
      reason: 'Operación permitida',
      riskLevel: 'LOW',
      requiresExtraConfirmation: false,
    );
  }

  /// Verifica si una operación de eliminación es permitida
  static ProtectionResult canDeleteFile(String filePath) {
    return canModifyFile(filePath, 'delete');
  }

  /// Verifica si una operación de edición es permitida
  static ProtectionResult canEditFile(String filePath) {
    return canModifyFile(filePath, 'edit');
  }

  /// Verifica si una operación de creación es permitida
  static ProtectionResult canCreateFile(String filePath) {
    // Verificar si se intenta crear en directorio protegido
    if (isProtectedDirectory(filePath)) {
      return ProtectionResult(
        allowed: false,
        reason: 'No se pueden crear archivos en directorios del sistema.',
        riskLevel: 'HIGH',
        requiresExtraConfirmation: true,
      );
    }

    return ProtectionResult(
      allowed: true,
      reason: 'Creación de archivo permitida',
      riskLevel: 'LOW',
      requiresExtraConfirmation: false,
    );
  }

  /// Obtiene recomendaciones de seguridad para una operación
  static List<String> getSecurityRecommendations(String operation, String filePath) {
    final recommendations = <String>[];

    if (isCriticalFile(filePath)) {
      recommendations.addAll([
        '🔒 Archivo crítico detectado',
        '📋 Revisa cuidadosamente los cambios antes de aplicar',
        '💾 Considera hacer un commit de Git antes de continuar',
        '🔄 Asegúrate de tener un backup del proyecto',
      ]);
    }

    if (operation == 'delete' || operation == 'delete_file') {
      recommendations.addAll([
        '⚠️ La eliminación es irreversible',
        '🗑️ Asegúrate de que realmente quieres eliminar este archivo',
        '📦 Verifica que no haya referencias a este archivo en el código',
      ]);
    }

    if (operation == 'execute_command') {
      recommendations.addAll([
        '⚡ Los comandos del sistema pueden tener efectos permanentes',
        '🔍 Verifica que el comando sea seguro y correcto',
        '📝 Revisa los argumentos del comando cuidadosamente',
      ]);
    }

    return recommendations;
  }

  /// Obtiene un mensaje de advertencia para archivos críticos
  static String getCriticalFileWarning(String filePath) {
    final fileName = filePath.split('/').last;

    if (fileName.contains('pubspec.yaml')) {
      return '⚠️ pubspec.yaml controla las dependencias del proyecto. Cambios incorrectos pueden romper la compilación.';
    }

    if (fileName.contains('main.dart')) {
      return '⚠️ main.dart es el punto de entrada de la aplicación. Cambios aquí afectan toda la app.';
    }

    if (fileName.contains('build.gradle')) {
      return '⚠️ build.gradle configura la compilación de Android. Errores aquí impiden compilar para Android.';
    }

    if (fileName.contains('Info.plist')) {
      return '⚠️ Info.plist configura la app de iOS. Errores aquí impiden compilar para iOS.';
    }

    if (fileName.contains('.gitignore')) {
      return '⚠️ .gitignore controla qué archivos se suben a Git. Cambios incorrectos pueden exponer información sensible.';
    }

    if (fileName.contains('.env')) {
      return '⚠️ Archivos .env contienen configuración sensible. Maneja con cuidado.';
    }

    return '⚠️ Este es un archivo crítico del proyecto. Procede con precaución.';
  }
}

/// Resultado de una verificación de protección
class ProtectionResult {
  final bool allowed;
  final String reason;
  final String riskLevel; // 'LOW', 'MEDIUM', 'HIGH'
  final bool requiresExtraConfirmation;
  final List<String> warnings;

  ProtectionResult({
    required this.allowed,
    required this.reason,
    required this.riskLevel,
    required this.requiresExtraConfirmation,
    this.warnings = const [],
  });

  /// Convierte el resultado a un mapa JSON
  Map<String, dynamic> toJson() {
    return {
      'allowed': allowed,
      'reason': reason,
      'riskLevel': riskLevel,
      'requiresExtraConfirmation': requiresExtraConfirmation,
      'warnings': warnings,
    };
  }

  /// Crea un resultado desde un mapa JSON
  factory ProtectionResult.fromJson(Map<String, dynamic> json) {
    return ProtectionResult(
      allowed: json['allowed'] as bool,
      reason: json['reason'] as String,
      riskLevel: json['riskLevel'] as String,
      requiresExtraConfirmation: json['requiresExtraConfirmation'] as bool,
      warnings: json['warnings'] != null 
          ? List<String>.from(json['warnings'])
          : [],
    );
  }
}
