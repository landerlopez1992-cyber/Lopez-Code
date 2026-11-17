// Generado para el proyecto Firebase `voryxel-code` (macOS).
// Auth + billetera (Firestore) usan estas options.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Firebase web aún no configurado en Voryxel Code.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
        return macos;
      case TargetPlatform.android:
        throw UnsupportedError(
          'Firebase Android aún no configurado (carpeta android incompleta).',
        );
      default:
        return macos;
    }
  }

  /// `true` cuando hay keys reales para la plataforma actual.
  static bool get isConfigured {
    try {
      final key = currentPlatform.apiKey;
      return key.isNotEmpty &&
          !key.contains('YOUR_') &&
          key != 'REPLACE_ME';
    } catch (_) {
      return false;
    }
  }

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDpYHLMGrq4yOjNUXBzTCXOAkDKjGb8uYs',
    appId: '1:213137346280:ios:40f5bb85a59ebbd8d5835d',
    messagingSenderId: '213137346280',
    projectId: 'voryxel-code',
    storageBucket: 'voryxel-code.firebasestorage.app',
    iosBundleId: 'com.cubcolexpress.voryxelCode',
  );
}
