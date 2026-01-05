import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class GitService {
  static const String _repoUrlKey = 'git_repo_url_';
  static const String _repoBranchKey = 'git_repo_branch_';

  // Guardar configuración de Git para un proyecto
  static Future<void> saveGitConfig({
    required String projectPath,
    required String repoUrl,
    String branch = 'main',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final projectKey = _getProjectKey(projectPath);
    
    await prefs.setString('$_repoUrlKey$projectKey', repoUrl);
    await prefs.setString('$_repoBranchKey$projectKey', branch);
  }

  // Obtener configuración de Git para un proyecto
  static Future<Map<String, String>?> getGitConfig(String projectPath) async {
    final prefs = await SharedPreferences.getInstance();
    final projectKey = _getProjectKey(projectPath);
    
    final repoUrl = prefs.getString('$_repoUrlKey$projectKey');
    final branch = prefs.getString('$_repoBranchKey$projectKey') ?? 'main';
    
    if (repoUrl == null || repoUrl.isEmpty) {
      return null;
    }
    
    return {
      'repoUrl': repoUrl,
      'branch': branch,
    };
  }

  // Verificar si un proyecto tiene Git configurado
  static Future<bool> hasGitConfig(String projectPath) async {
    final config = await getGitConfig(projectPath);
    return config != null;
  }

  // Verificar si un directorio es un repositorio Git
  static Future<bool> isGitRepository(String projectPath) async {
    final gitDir = Directory('$projectPath/.git');
    return await gitDir.exists();
  }

  // Inicializar repositorio Git
  static Future<String> initGitRepository(String projectPath) async {
    try {
      final result = await Process.run(
        'git',
        ['init'],
        workingDirectory: projectPath,
      );
      
      if (result.exitCode == 0) {
        return 'Repositorio Git inicializado correctamente';
      } else {
        throw Exception(result.stderr);
      }
    } catch (e) {
      throw Exception('Error al inicializar Git: $e');
    }
  }

  // Agregar remoto
  static Future<String> addRemote({
    required String projectPath,
    required String remoteName,
    required String remoteUrl,
  }) async {
    try {
      final result = await Process.run(
        'git',
        ['remote', 'add', remoteName, remoteUrl],
        workingDirectory: projectPath,
      );
      
      if (result.exitCode == 0) {
        return 'Remoto agregado correctamente';
      } else {
        throw Exception(result.stderr);
      }
    } catch (e) {
      throw Exception('Error al agregar remoto: $e');
    }
  }

  // Hacer commit
  static Future<String> commit({
    required String projectPath,
    required String message,
    List<String>? files,
  }) async {
    try {
      // Agregar archivos al staging
      if (files != null && files.isNotEmpty) {
        for (var file in files) {
          final result = await Process.run(
            'git',
            ['add', file],
            workingDirectory: projectPath,
          );
          if (result.exitCode != 0) {
            throw Exception('Error al agregar $file: ${result.stderr}');
          }
        }
      } else {
        // Agregar todos los archivos
        final result = await Process.run(
          'git',
          ['add', '.'],
          workingDirectory: projectPath,
        );
        if (result.exitCode != 0) {
          throw Exception('Error al agregar archivos: ${result.stderr}');
        }
      }

      // Hacer commit
      final commitResult = await Process.run(
        'git',
        ['commit', '-m', message],
        workingDirectory: projectPath,
      );
      
      if (commitResult.exitCode == 0) {
        return 'Commit realizado correctamente';
      } else {
        throw Exception(commitResult.stderr);
      }
    } catch (e) {
      throw Exception('Error al hacer commit: $e');
    }
  }

  // Hacer push
  static Future<String> push({
    required String projectPath,
    String? remote,
    String? branch,
  }) async {
    try {
      final config = await getGitConfig(projectPath);
      final remoteName = remote ?? 'origin';
      final branchName = branch ?? config?['branch'] ?? 'main';

      final result = await Process.run(
        'git',
        ['push', remoteName, branchName],
        workingDirectory: projectPath,
      );
      
      if (result.exitCode == 0) {
        return 'Push realizado correctamente';
      } else {
        throw Exception(result.stderr);
      }
    } catch (e) {
      throw Exception('Error al hacer push: $e');
    }
  }

  // Obtener estado de Git
  static Future<Map<String, dynamic>> getGitStatus(String projectPath) async {
    try {
      final statusResult = await Process.run(
        'git',
        ['status', '--porcelain'],
        workingDirectory: projectPath,
      );

      final branchResult = await Process.run(
        'git',
        ['branch', '--show-current'],
        workingDirectory: projectPath,
      );

      return {
        'hasChanges': statusResult.stdout.toString().trim().isNotEmpty,
        'status': statusResult.stdout.toString(),
        'branch': branchResult.stdout.toString().trim(),
      };
    } catch (e) {
      return {
        'hasChanges': false,
        'status': '',
        'branch': '',
        'error': e.toString(),
      };
    }
  }

  // Obtener clave única para el proyecto
  static String _getProjectKey(String projectPath) {
    // Usar el hash del path como clave
    return projectPath.hashCode.toString();
  }
}

