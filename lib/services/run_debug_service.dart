import 'dart:async';
import 'package:flutter/services.dart';

class RunDebugService {
  static const MethodChannel _channel = MethodChannel('run_debug_service');

  Future<void> runFlutterProject(String projectPath) async {
    try {
      await _channel.invokeMethod('runFlutterProject', {'path': projectPath});
    } on PlatformException catch (e) {
      print('Error al ejecutar el proyecto: ${e.message}');
    }
  }

  void onOutput(String output) {
    print('Salida: $output');
  }

  void onError(String error) {
    print('Error: $error');
  }
}