import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:process_run/process_run.dart' as pr;

/// Servicio para gestionar repositorios Git vinculados a proyectos
class RepositoryService {
  static const String _repoKeyPrefix = 'project_repo_';

  /// Vincular un repositorio a un proyecto
  static Future<void> linkRepositoryToProject(String projectPath, String repoUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_repoKeyPrefix$projectPath', repoUrl);
    print('✅ Repositorio vinculado: $repoUrl -> $projectPath');
  }

  /// Obtener el repositorio vinculado a un proyecto
  static Future<String?> getRepositoryForProject(String projectPath) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_repoKeyPrefix$projectPath');
  }

  /// Desvincular repositorio de un proyecto
  static Future<void> unlinkRepositoryFromProject(String projectPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_repoKeyPrefix$projectPath');
    print('✅ Repositorio desvinculado de: $projectPath');
  }

  /// Clonar un repositorio y vincularlo a un proyecto
  static Future<Map<String, dynamic>> cloneRepository(String repoUrl, String targetPath) async {
    try {
      print('📥 Clonando repositorio: $repoUrl a $targetPath');
      
      // Verificar si el directorio ya existe
      final targetDir = Directory(targetPath);
      if (await targetDir.exists()) {
        return {
          'success': false,
          'error': 'El directorio ya existe: $targetPath',
        };
      }

      // Clonar repositorio
      final shell = pr.Shell();
      final result = await shell.run(
        'git clone $repoUrl $targetPath',
      );

      if (result.first.exitCode == 0) {
        // Vincular automáticamente
        await linkRepositoryToProject(targetPath, repoUrl);
        
        return {
          'success': true,
          'path': targetPath,
          'message': 'Repositorio clonado exitosamente',
        };
      } else {
        return {
          'success': false,
          'error': result.first.stderr.toString(),
        };
      }
    } catch (e) {
      print('❌ Error al clonar repositorio: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Obtener estado del repositorio
  static Future<Map<String, dynamic>> getRepositoryStatus(String projectPath) async {
    try {
      final shell = pr.Shell(workingDirectory: projectPath);
      final result = await shell.run('git status --porcelain');

      final hasChanges = result.first.stdout.toString().trim().isNotEmpty;
      
      return {
        'success': true,
        'hasChanges': hasChanges,
        'status': result.first.stdout.toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Hacer commit y push
  static Future<Map<String, dynamic>> commitAndPush(
    String projectPath,
    String message,
  ) async {
    try {
      final shell = pr.Shell(workingDirectory: projectPath);
      
      // Agregar todos los cambios
      await shell.run('git add .');
      
      // Commit
      final commitResult = await shell.run('git commit -m "${message.replaceAll('"', '\\"')}"');

      if (commitResult.first.exitCode != 0) {
        return {
          'success': false,
          'error': 'Error al hacer commit: ${commitResult.first.stderr}',
        };
      }

      // Push
      final pushResult = await shell.run('git push');

      if (pushResult.first.exitCode != 0) {
        return {
          'success': false,
          'error': 'Error al hacer push: ${pushResult.first.stderr}',
        };
      }

      return {
        'success': true,
        'message': 'Cambios enviados exitosamente',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}

