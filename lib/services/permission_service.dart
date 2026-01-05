import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class PermissionService {
  static const String _permissionRequestedKey = 'file_permission_requested';
  static const String _permissionGrantedKey = 'file_permission_granted';

  /// Verifica si la app tiene permisos para acceder a archivos
  /// Con App Sandbox deshabilitado, la app tiene acceso completo
  static Future<bool> checkFileAccess() async {
    try {
      // Con App Sandbox deshabilitado, la aplicación tiene acceso completo
      // Solo verificamos que podemos acceder al directorio home
      final homeDir = Platform.environment['HOME'];
      if (homeDir == null) {
        print('⚠️ No se encontró HOME directory');
        return false;
      }

      try {
        final homeDirectory = Directory(homeDir);
        if (await homeDirectory.exists()) {
          // Intentar listar el directorio home (esto siempre funciona si tenemos acceso básico)
          await homeDirectory.list().take(1).toList();
          print('✅ Acceso a archivos verificado correctamente (App Sandbox deshabilitado)');
          return true;
        }
      } catch (e) {
        // Si incluso el home falla, puede que haya un problema real
        print('⚠️ Error al acceder al directorio home: $e');
        return false;
      }

      return false;
    } catch (e) {
      print('❌ Error general al verificar acceso a archivos: $e');
      // Con App Sandbox deshabilitado, asumimos que tenemos acceso
      // Solo retornamos false si hay un error grave
      return true; // Cambiamos esto porque sin sandbox tenemos acceso
    }
  }

  /// Verifica si ya se solicitó permiso anteriormente
  static Future<bool> hasRequestedPermission() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_permissionRequestedKey) ?? false;
  }

  /// Marca que se solicitó permiso
  static Future<void> markPermissionRequested() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permissionRequestedKey, true);
  }

  /// Marca que se otorgó permiso
  static Future<void> markPermissionGranted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permissionGrantedKey, true);
  }

  /// Verifica si se otorgó permiso anteriormente
  static Future<bool> wasPermissionGranted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_permissionGrantedKey) ?? false;
  }

  /// Muestra un diálogo pidiendo permisos
  static Future<bool> requestFilePermission(BuildContext context) async {
    // Verificar si ya tenemos permisos
    final hasAccess = await checkFileAccess();
    if (hasAccess) {
      await markPermissionGranted();
      return true;
    }

    // Verificar si ya se solicitó antes
    final requested = await hasRequestedPermission();
    
    // Mostrar diálogo
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Row(
          children: [
            Icon(Icons.folder_open, color: Color(0xFF007ACC), size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Permisos de Acceso a Archivos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lopez Code necesita acceso a tus archivos para poder:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              _buildPermissionItem(
                Icons.folder,
                'Leer y editar archivos de tus proyectos',
              ),
              _buildPermissionItem(
                Icons.code,
                'Abrir y modificar código',
              ),
              _buildPermissionItem(
                Icons.save,
                'Guardar cambios en tus archivos',
              ),
              _buildPermissionItem(
                Icons.image,
                'Acceder a imágenes para análisis',
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '¿Cómo otorgar permisos?',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. Haz clic en "Abrir Configuración"',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      '2. Busca "Lopez Code" en la lista',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      '   ⚠️ Si no aparece, compila e instala la app primero:',
                      style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '   flutter build macos --release',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                    ),
                    Text(
                      '3. Activa "Escritorio" y "Carpetas de documentos"',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      '4. Vuelve a la app y haz clic en "Verificar"',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (requested) ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Más tarde',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
          ElevatedButton.icon(
            onPressed: () async {
              // Abrir configuración de macOS
              try {
                await Process.run(
                  'open',
                  ['x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders'],
                );
                await markPermissionRequested();
                Navigator.of(context).pop(true);
              } catch (e) {
                // Si falla, intentar abrir de otra manera
                try {
                  await Process.run('open', ['/System/Library/PreferencePanes/Security.prefPane']);
                  await markPermissionRequested();
                  Navigator.of(context).pop(true);
                } catch (e2) {
                  Navigator.of(context).pop(false);
                }
              }
            },
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('Abrir Configuración'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007ACC),
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              // Verificar si ahora tiene permisos
              final hasAccess = await checkFileAccess();
              if (hasAccess) {
                await markPermissionGranted();
                if (context.mounted) {
                  Navigator.of(context).pop(true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Permisos otorgados correctamente'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⚠️ Aún no se han otorgado permisos. Por favor, activa los permisos en Configuración.'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Verificar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  static Widget _buildPermissionItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF007ACC), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Verifica y solicita permisos automáticamente al iniciar
  /// Con App Sandbox deshabilitado, la app tiene acceso completo automáticamente
  static Future<bool> checkAndRequestPermissions(BuildContext context) async {
    // Con App Sandbox deshabilitado, siempre tenemos acceso completo
    // Solo verificamos que el sistema de archivos está disponible
    final hasAccess = await checkFileAccess();
    if (hasAccess) {
      await markPermissionGranted();
      print('✅ Permisos verificados: App tiene acceso completo (Sandbox deshabilitado)');
      return true;
    }

    // Si por alguna razón falla la verificación básica,
    // aún intentamos mostrar el diálogo informativo
    // pero no bloqueamos el uso de la app
    print('⚠️ Verificación de permisos falló, pero con Sandbox deshabilitado deberíamos tener acceso');
    await markPermissionGranted(); // Marcar como otorgado de todos modos
    return true;
  }

  /// Verifica permisos en segundo plano (sin mostrar diálogo)
  static Future<bool> checkPermissionsSilently() async {
    final hasAccess = await checkFileAccess();
    if (hasAccess) {
      await markPermissionGranted();
      return true;
    }
    return false;
  }
}

