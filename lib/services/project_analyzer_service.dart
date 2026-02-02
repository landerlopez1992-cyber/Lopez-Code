import 'dart:io';
import 'package:path/path.dart' as path;
import 'project_type_detector.dart';

/// Resultado del análisis del proyecto
class ProjectAnalysis {
  final String projectPath;
  final ProjectType projectType;
  final Map<String, dynamic> structure;
  final List<String> mainFiles;
  final List<String> missingFiles;
  final List<String> errors;
  final bool isComplete;
  
  ProjectAnalysis({
    required this.projectPath,
    required this.projectType,
    required this.structure,
    required this.mainFiles,
    required this.missingFiles,
    required this.errors,
    required this.isComplete,
  });
}

/// Servicio para analizar proyectos ANTES de actuar
class ProjectAnalyzerService {
  
  /// Analiza un proyecto completo y retorna un análisis detallado
  static Future<ProjectAnalysis> analyzeProject(String projectPath) async {
    print('🔍 Analizando proyecto: $projectPath');
    
    final projectType = await ProjectTypeDetector.detectProjectType(projectPath);
    final structure = await _analyzeStructure(projectPath);
    final mainFiles = await _findMainFiles(projectPath, projectType);
    final missingFiles = await _findMissingFiles(projectPath, projectType);
    final errors = await _detectErrors(projectPath, projectType);
    final isComplete = missingFiles.isEmpty && errors.isEmpty;
    
    print('✅ Análisis completado:');
    print('   Tipo: ${ProjectTypeDetector.getProjectTypeName(projectType)}');
    print('   Archivos principales: ${mainFiles.length}');
    print('   Archivos faltantes: ${missingFiles.length}');
    print('   Errores detectados: ${errors.length}');
    print('   Proyecto completo: $isComplete');
    
    return ProjectAnalysis(
      projectPath: projectPath,
      projectType: projectType,
      structure: structure,
      mainFiles: mainFiles,
      missingFiles: missingFiles,
      errors: errors,
      isComplete: isComplete,
    );
  }
  
  /// Analiza la estructura de carpetas y archivos
  static Future<Map<String, dynamic>> _analyzeStructure(String projectPath) async {
    final structure = <String, dynamic>{};
    final dir = Directory(projectPath);
    
    if (!await dir.exists()) {
      return structure;
    }
    
    await for (final entity in dir.list(recursive: false)) {
      final name = path.basename(entity.path);
      
      if (entity is Directory) {
        structure[name] = {
          'type': 'directory',
          'path': entity.path,
        };
      } else if (entity is File) {
        structure[name] = {
          'type': 'file',
          'path': entity.path,
          'size': await entity.length(),
        };
      }
    }
    
    return structure;
  }
  
  /// Encuentra los archivos principales del proyecto
  static Future<List<String>> _findMainFiles(String projectPath, ProjectType projectType) async {
    final mainFiles = <String>[];
    
    switch (projectType) {
      case ProjectType.flutter:
        final candidates = [
          'pubspec.yaml',
          'lib/main.dart',
          'android/app/build.gradle',
          'ios/Podfile',
        ];
        
        for (final candidate in candidates) {
          final file = File(path.join(projectPath, candidate));
          if (await file.exists()) {
            mainFiles.add(candidate);
          }
        }
        break;
        
      case ProjectType.python:
        final candidates = [
          'main.py',
          'app.py',
          'requirements.txt',
          'setup.py',
        ];
        
        for (final candidate in candidates) {
          final file = File(path.join(projectPath, candidate));
          if (await file.exists()) {
            mainFiles.add(candidate);
          }
        }
        break;
        
      case ProjectType.nodejs:
        final candidates = [
          'package.json',
          'index.js',
          'server.js',
          'app.js',
        ];
        
        for (final candidate in candidates) {
          final file = File(path.join(projectPath, candidate));
          if (await file.exists()) {
            mainFiles.add(candidate);
          }
        }
        break;
        
      default:
        break;
    }
    
    return mainFiles;
  }
  
  /// Encuentra archivos faltantes necesarios para que el proyecto compile
  static Future<List<String>> _findMissingFiles(String projectPath, ProjectType projectType) async {
    final missingFiles = <String>[];
    
    switch (projectType) {
      case ProjectType.flutter:
        final requiredFiles = [
          'pubspec.yaml',
          'lib/main.dart',
        ];
        
        for (final requiredFile in requiredFiles) {
          final file = File(path.join(projectPath, requiredFile));
          if (!await file.exists()) {
            missingFiles.add(requiredFile);
          }
        }
        
        // Verificar si existe carpeta lib
        final libDir = Directory(path.join(projectPath, 'lib'));
        if (!await libDir.exists()) {
          missingFiles.add('lib/ (carpeta)');
        }
        break;
        
      case ProjectType.python:
        // Python es menos estricto, solo verificar que exista al menos un .py
        final dir = Directory(projectPath);
        bool hasPythonFile = false;
        
        await for (final entity in dir.list(recursive: false)) {
          if (entity is File && entity.path.endsWith('.py')) {
            hasPythonFile = true;
            break;
          }
        }
        
        if (!hasPythonFile) {
          missingFiles.add('main.py o app.py');
        }
        break;
        
      case ProjectType.nodejs:
        final packageJson = File(path.join(projectPath, 'package.json'));
        if (!await packageJson.exists()) {
          missingFiles.add('package.json');
        }
        break;
        
      default:
        break;
    }
    
    return missingFiles;
  }
  
  /// Detecta errores comunes en el proyecto
  static Future<List<String>> _detectErrors(String projectPath, ProjectType projectType) async {
    final errors = <String>[];
    
    switch (projectType) {
      case ProjectType.flutter:
        // Verificar pubspec.yaml
        final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
        if (await pubspecFile.exists()) {
          try {
            final content = await pubspecFile.readAsString();
            
            // Verificar estructura mínima
            if (!content.contains('name:')) {
              errors.add('pubspec.yaml: falta campo "name"');
            }
            if (!content.contains('dependencies:')) {
              errors.add('pubspec.yaml: falta sección "dependencies"');
            }
            if (!content.contains('flutter:')) {
              errors.add('pubspec.yaml: falta sección "flutter"');
            }
          } catch (e) {
            errors.add('pubspec.yaml: error al leer el archivo');
          }
        }
        
        // Verificar main.dart
        final mainFile = File(path.join(projectPath, 'lib', 'main.dart'));
        if (await mainFile.exists()) {
          try {
            final content = await mainFile.readAsString();
            
            // Verificar estructura mínima
            if (!content.contains('void main()')) {
              errors.add('main.dart: falta función main()');
            }
            if (!content.contains('import ')) {
              errors.add('main.dart: posible falta de imports');
            }
          } catch (e) {
            errors.add('main.dart: error al leer el archivo');
          }
        }
        break;
        
      default:
        break;
    }
    
    return errors;
  }
  
  /// Genera un reporte legible del análisis
  static String generateReport(ProjectAnalysis analysis) {
    final lines = <String>[];
    
    lines.add('=== ANÁLISIS DEL PROYECTO ===\n');
    lines.add('📁 Ruta: ${analysis.projectPath}');
    lines.add('📱 Tipo: ${ProjectTypeDetector.getProjectTypeName(analysis.projectType)}\n');
    
    if (analysis.isComplete) {
      lines.add('✅ El proyecto está COMPLETO y listo para compilar\n');
    } else {
      lines.add('⚠️ El proyecto está INCOMPLETO\n');
    }
    
    if (analysis.mainFiles.isNotEmpty) {
      lines.add('📄 Archivos principales encontrados:');
      for (final file in analysis.mainFiles) {
        lines.add('   ✓ $file');
      }
      lines.add('');
    }
    
    if (analysis.missingFiles.isNotEmpty) {
      lines.add('❌ Archivos faltantes:');
      for (final file in analysis.missingFiles) {
        lines.add('   ✗ $file');
      }
      lines.add('');
    }
    
    if (analysis.errors.isNotEmpty) {
      lines.add('🔴 Errores detectados:');
      for (final error in analysis.errors) {
        lines.add('   ! $error');
      }
      lines.add('');
    }
    
    return lines.join('\n');
  }
}
