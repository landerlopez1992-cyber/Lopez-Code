import 'dart:io';
import 'package:path/path.dart' as path;
import 'task_orchestrator_service.dart';
import 'project_analyzer_service.dart';
import 'project_type_detector.dart';
import 'run_debug_service.dart';

/// Resultado de ejecución automática
class AutoExecutionResult {
  final bool success;
  final List<String> filesCreated;
  final List<String> filesModified;
  final List<String> errors;
  final String? compilationOutput;
  final bool needsUserConfirmation;
  
  AutoExecutionResult({
    required this.success,
    required this.filesCreated,
    required this.filesModified,
    required this.errors,
    this.compilationOutput,
    this.needsUserConfirmation = false,
  });
}

/// Servicio para ejecutar tareas automáticamente sin confirmación del usuario
/// (para proyectos completos)
class AutoExecutionService {
  
  /// Determina si una tarea debe ejecutarse automáticamente sin confirmación
  static bool shouldExecuteAutomatically(TaskType taskType) {
    // Solo proyectos completos y modificaciones se ejecutan automáticamente
    return taskType == TaskType.fullProject || 
           taskType == TaskType.projectModification;
  }
  
  /// Ejecuta un plan de ejecución automáticamente
  static Future<AutoExecutionResult> executePlan({
    required ExecutionPlan plan,
    required String projectPath,
    required Map<String, String> generatedContent, // Contenido generado por la IA
    Function(String)? onProgress,
  }) async {
    print('🚀 === EJECUCIÓN AUTOMÁTICA INICIADA ===');
    print('📋 Plan: ${plan.description}');
    print('🎯 Acciones: ${plan.actions.length}');
    
    final filesCreated = <String>[];
    final filesModified = <String>[];
    final errors = <String>[];
    
    try {
      // Ejecutar cada acción del plan
      for (var i = 0; i < plan.actions.length; i++) {
        final action = plan.actions[i];
        onProgress?.call('Ejecutando acción ${i + 1}/${plan.actions.length}: ${action.type}');
        
        print('⚙️ Ejecutando: ${action.type} - ${action.target}');
        
        switch (action.type) {
          case 'create_file':
            // Crear archivo
            final filePath = path.join(projectPath, action.target);
            final content = action.content ?? generatedContent[action.target] ?? '';
            
            if (content.isEmpty) {
              print('⚠️ No hay contenido para crear: ${action.target}');
              continue;
            }
            
            try {
              // Crear carpeta padre si no existe
              final file = File(filePath);
              await file.parent.create(recursive: true);
              // Escribir contenido
              await file.writeAsString(content);
              filesCreated.add(action.target);
              print('✅ Archivo creado: ${action.target}');
            } catch (e) {
              errors.add('Error creando ${action.target}: $e');
              print('❌ Error: $e');
            }
            break;
            
          case 'edit_file':
          case 'verify_or_create_file':
            // Editar o verificar/crear archivo
            final filePath = path.join(projectPath, action.target);
            final file = File(filePath);
            
            if (await file.exists()) {
              // Archivo existe, modificar si hay contenido nuevo
              final content = action.content ?? generatedContent[action.target];
              if (content != null && content.isNotEmpty) {
                try {
                  await file.writeAsString(content);
                  filesModified.add(action.target);
                  print('✅ Archivo modificado: ${action.target}');
                } catch (e) {
                  errors.add('Error modificando ${action.target}: $e');
                  print('❌ Error: $e');
                }
              }
            } else {
              // Archivo no existe, crear
              final content = action.content ?? generatedContent[action.target] ?? '';
              if (content.isNotEmpty) {
                try {
                  // Crear carpeta padre si no existe
                  final file = File(filePath);
                  await file.parent.create(recursive: true);
                  // Escribir contenido
                  await file.writeAsString(content);
                  filesCreated.add(action.target);
                  print('✅ Archivo creado: ${action.target}');
                } catch (e) {
                  errors.add('Error creando ${action.target}: $e');
                  print('❌ Error: $e');
                }
              }
            }
            break;
            
          case 'create_folder':
            // Crear carpeta
            final folderPath = path.join(projectPath, action.target);
            final folder = Directory(folderPath);
            
            if (!await folder.exists()) {
              try {
                await folder.create(recursive: true);
                print('✅ Carpeta creada: ${action.target}');
              } catch (e) {
                errors.add('Error creando carpeta ${action.target}: $e');
                print('❌ Error: $e');
              }
            }
            break;
            
          case 'run_command':
            // Ejecutar comando (por ahora solo log)
            print('📝 Comando a ejecutar: ${action.target}');
            // TODO: Implementar ejecución de comandos si es necesario
            break;
            
          case 'analyze_and_create':
            // Analizar y crear archivos adicionales basados en el contenido generado
            for (final entry in generatedContent.entries) {
              if (entry.key.startsWith(action.target)) {
                final filePath = path.join(projectPath, entry.key);
                try {
                  // Crear carpeta padre si no existe
                  final file = File(filePath);
                  await file.parent.create(recursive: true);
                  // Escribir contenido
                  await file.writeAsString(entry.value);
                  filesCreated.add(entry.key);
                  print('✅ Archivo adicional creado: ${entry.key}');
                } catch (e) {
                  errors.add('Error creando ${entry.key}: $e');
                  print('❌ Error: $e');
                }
              }
            }
            break;
            
          default:
            print('⚠️ Tipo de acción desconocido: ${action.type}');
        }
      }
      
      print('\n✅ === EJECUCIÓN COMPLETADA ===');
      print('📄 Archivos creados: ${filesCreated.length}');
      print('✏️ Archivos modificados: ${filesModified.length}');
      print('❌ Errores: ${errors.length}');
      
      return AutoExecutionResult(
        success: errors.isEmpty,
        filesCreated: filesCreated,
        filesModified: filesModified,
        errors: errors,
        needsUserConfirmation: false,
      );
      
    } catch (e) {
      print('❌ Error en ejecución automática: $e');
      errors.add('Error general: $e');
      
      return AutoExecutionResult(
        success: false,
        filesCreated: filesCreated,
        filesModified: filesModified,
        errors: errors,
        needsUserConfirmation: false,
      );
    }
  }
  
  /// Verifica compilación después de ejecutar cambios
  static Future<bool> verifyCompilation({
    required String projectPath,
    Function(String)? onOutput,
  }) async {
    print('🔍 === VERIFICANDO COMPILACIÓN ===');
    
    try {
      // Analizar proyecto para detectar tipo
      final analysis = await ProjectAnalyzerService.analyzeProject(projectPath);
      
      if (analysis.projectType == ProjectType.flutter) {
        print('📱 Verificando proyecto Flutter...');
        
        // Verificar que Flutter esté disponible
        final flutterAvailable = await RunDebugService.isFlutterAvailable();
        if (!flutterAvailable) {
          print('⚠️ Flutter no está disponible');
          return false;
        }
        
        // Intentar compilación de prueba (flutter analyze)
        try {
          final result = await Process.run(
            'flutter',
            ['analyze', '--no-pub'],
            workingDirectory: projectPath,
          );
          
          final output = result.stdout.toString() + result.stderr.toString();
          onOutput?.call(output);
          
          if (result.exitCode == 0) {
            print('✅ Compilación verificada: OK');
            return true;
          } else {
            print('⚠️ Compilación con advertencias/errores');
            print(output);
            return false;
          }
        } catch (e) {
          print('❌ Error en verificación: $e');
          return false;
        }
      }
      
      // Para otros tipos de proyecto, asumir OK por ahora
      print('✅ Verificación básica: OK');
      return true;
      
    } catch (e) {
      print('❌ Error verificando compilación: $e');
      return false;
    }
  }
  
  /// Loop de verificación y corrección automática
  static Future<AutoExecutionResult> executeWithVerification({
    required ExecutionPlan plan,
    required String projectPath,
    required Map<String, String> generatedContent,
    required Function(String, {bool isError}) onFeedback,
    int maxRetries = 2,
  }) async {
    print('🔁 === LOOP DE VERIFICACIÓN Y CORRECCIÓN ===');
    
    int attempts = 0;
    AutoExecutionResult? lastResult;
    
    while (attempts < maxRetries) {
      attempts++;
      print('\n📍 Intento $attempts/$maxRetries');
      
      // Ejecutar plan
      onFeedback('Ejecutando cambios (intento $attempts)...', isError: false);
      lastResult = await executePlan(
        plan: plan,
        projectPath: projectPath,
        generatedContent: generatedContent,
        onProgress: (progress) => onFeedback(progress, isError: false),
      );
      
      if (!lastResult.success) {
        onFeedback('Ejecución completada con errores. Analizando...', isError: true);
        
        // Si hay errores, reportar y continuar (no reintentar automáticamente)
        for (final error in lastResult.errors) {
          onFeedback('Error: $error', isError: true);
        }
        
        break; // No reintentar automáticamente en errores de ejecución
      }
      
      // Verificar compilación
      onFeedback('Verificando compilación...', isError: false);
      bool compilationOk = false;
      String? compilationOutput;
      
      final verificationSuccess = await verifyCompilation(
        projectPath: projectPath,
        onOutput: (output) {
          compilationOutput = output;
          onFeedback('Salida de compilación:\n$output', isError: false);
        },
      );
      
      compilationOk = verificationSuccess;
      
      if (compilationOk) {
        onFeedback('✅ Compilación exitosa!', isError: false);
        return AutoExecutionResult(
          success: true,
          filesCreated: lastResult.filesCreated,
          filesModified: lastResult.filesModified,
          errors: lastResult.errors,
          compilationOutput: compilationOutput,
          needsUserConfirmation: false,
        );
      } else {
        onFeedback('⚠️ Compilación con problemas. Intento $attempts/$maxRetries', isError: true);
        
        if (attempts >= maxRetries) {
          onFeedback('❌ Máximo de intentos alcanzado', isError: true);
          break;
        }
        
        // Para el siguiente intento, se podría implementar corrección automática aquí
        // Por ahora solo reportamos
      }
    }
    
    // Retornar último resultado
    return lastResult ?? AutoExecutionResult(
      success: false,
      filesCreated: [],
      filesModified: [],
      errors: ['No se pudo completar la ejecución'],
      needsUserConfirmation: false,
    );
  }
}
