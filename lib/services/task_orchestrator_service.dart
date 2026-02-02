import 'dart:io';
import 'package:path/path.dart' as path;
import 'project_type_detector.dart';

/// Tipos de tareas que puede ejecutar el orquestador
enum TaskType {
  singleFile,           // Crear/editar un solo archivo
  multiFile,            // Crear/editar múltiples archivos
  fullProject,          // Crear proyecto completo desde cero
  projectModification,  // Modificar proyecto existente
  bugFix,              // Corregir errores
  refactor,            // Refactorizar código
}

/// Representa una acción individual a ejecutar
class TaskAction {
  final String type; // 'create_file', 'edit_file', 'create_folder', 'run_command'
  final String target; // Ruta del archivo o comando
  final String? content; // Contenido del archivo (si aplica)
  final Map<String, dynamic>? metadata; // Metadata adicional
  
  TaskAction({
    required this.type,
    required this.target,
    this.content,
    this.metadata,
  });
  
  Map<String, dynamic> toJson() => {
    'type': type,
    'target': target,
    'content': content,
    'metadata': metadata,
  };
}

/// Representa un plan de ejecución completo
class ExecutionPlan {
  final TaskType taskType;
  final String description;
  final List<TaskAction> actions;
  final List<String> contextFiles; // Archivos a analizar antes de ejecutar
  final bool requiresConfirmation; // Si requiere confirmación del usuario
  
  ExecutionPlan({
    required this.taskType,
    required this.description,
    required this.actions,
    required this.contextFiles,
    this.requiresConfirmation = false,
  });
  
  Map<String, dynamic> toJson() => {
    'taskType': taskType.toString(),
    'description': description,
    'actions': actions.map((a) => a.toJson()).toList(),
    'contextFiles': contextFiles,
    'requiresConfirmation': requiresConfirmation,
  };
}

/// Orquestador de tareas - El cerebro que planifica y ejecuta
class TaskOrchestratorService {
  
  /// Detecta el tipo de tarea basándose en la pregunta del usuario
  static TaskType detectTaskType(String userMessage) {
    final lowerMessage = userMessage.toLowerCase().trim();
    
    // ✅ FILTRO: Mensajes simples que NO requieren acciones
    final simpleGreetings = [
      'hola',
      'hi',
      'hello',
      'hey',
      'buenos días',
      'buenas tardes',
      'buenas noches',
      'gracias',
      'thanks',
      'ok',
      'okay',
      'sí',
      'si',
      'no',
      'perfecto',
      'perfect',
      'bien',
      'good',
    ];
    
    // Si es un saludo simple, retornar singleFile pero marcar como "no action"
    if (simpleGreetings.contains(lowerMessage) || lowerMessage.length < 3) {
      return TaskType.singleFile; // Retornar singleFile pero será filtrado después
    }
    
    // Patrones para proyecto completo
    final fullProjectPatterns = [
      'crea una app',
      'crea un proyecto',
      'hazme una aplicación',
      'construye una app',
      'necesito un proyecto',
      'para android',
      'para ios',
      'para web',
      'quiero probarlo',
      'para correrlo',
      'ejecutable',
      'app completa',
      'proyecto completo',
    ];
    
    for (final pattern in fullProjectPatterns) {
      if (lowerMessage.contains(pattern)) {
        return TaskType.fullProject;
      }
    }
    
    // Patrones para corrección de errores
    final bugFixPatterns = [
      'error',
      'no funciona',
      'arregla',
      'corrige',
      'bug',
      'falla',
      'problema',
    ];
    
    for (final pattern in bugFixPatterns) {
      if (lowerMessage.contains(pattern)) {
        return TaskType.bugFix;
      }
    }
    
    // Patrones para refactorización
    final refactorPatterns = [
      'refactoriza',
      'mejora',
      'optimiza',
      'reorganiza',
    ];
    
    for (final pattern in refactorPatterns) {
      if (lowerMessage.contains(pattern)) {
        return TaskType.refactor;
      }
    }
    
    // Patrones para múltiples archivos
    final multiFilePatterns = [
      'archivos',
      'carpetas',
      'estructura',
      'componentes',
      'módulos',
    ];
    
    for (final pattern in multiFilePatterns) {
      if (lowerMessage.contains(pattern)) {
        return TaskType.multiFile;
      }
    }
    
    // Por defecto: archivo único
    return TaskType.singleFile;
  }
  
  /// Determina qué archivos deben analizarse ANTES de actuar
  static Future<List<String>> determineContextFiles({
    required String projectPath,
    required String userMessage,
    required TaskType taskType,
  }) async {
    final contextFiles = <String>[];
    
    // SIEMPRE incluir archivos de configuración clave
    final keyFiles = [
      'pubspec.yaml',
      'package.json',
      'requirements.txt',
      'main.dart',
      'lib/main.dart',
      'src/main.dart',
      'index.html',
      'README.md',
    ];
    
    for (final file in keyFiles) {
      final fullPath = path.join(projectPath, file);
      if (await File(fullPath).exists()) {
        contextFiles.add(fullPath);
      }
    }
    
    // Si es proyecto completo, analizar estructura completa
    if (taskType == TaskType.fullProject) {
      // Obtener todos los archivos principales
      final libDir = Directory(path.join(projectPath, 'lib'));
      if (await libDir.exists()) {
        await for (final entity in libDir.list(recursive: false)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            contextFiles.add(entity.path);
          }
        }
      }
    }
    
    // Si menciona archivos específicos, incluirlos
    final lowerMessage = userMessage.toLowerCase();
    if (lowerMessage.contains('calculator')) {
      final calculatorFile = path.join(projectPath, 'lib', 'calculator.dart');
      if (await File(calculatorFile).exists()) {
        contextFiles.add(calculatorFile);
      }
    }
    
    print('🔍 Archivos de contexto determinados: ${contextFiles.length}');
    for (final file in contextFiles) {
      print('   📄 ${path.basename(file)}');
    }
    
    return contextFiles;
  }
  
  /// Genera un plan de ejecución basándose en el tipo de tarea
  static Future<ExecutionPlan> generateExecutionPlan({
    required String projectPath,
    required String userMessage,
    required TaskType taskType,
  }) async {
    print('📋 Generando plan de ejecución...');
    print('   Tipo de tarea: $taskType');
    
    final actions = <TaskAction>[];
    final contextFiles = await determineContextFiles(
      projectPath: projectPath,
      userMessage: userMessage,
      taskType: taskType,
    );
    
    // Determinar si requiere confirmación
    // Solo proyectos completos y refactorizaciones NO requieren confirmación
    final requiresConfirmation = taskType != TaskType.fullProject && 
                                  taskType != TaskType.projectModification;
    
    String description = '';
    
    switch (taskType) {
      case TaskType.fullProject:
        description = 'Crear proyecto completo ejecutable y funcional';
        
        // Detectar tipo de proyecto
        final projectType = await ProjectTypeDetector.detectProjectType(projectPath);
        
        if (projectType == ProjectType.flutter) {
          // Plan para proyecto Flutter completo
          actions.addAll([
            // 1. Verificar/crear pubspec.yaml
            TaskAction(
              type: 'verify_or_create_file',
              target: 'pubspec.yaml',
              metadata: {'priority': 'high'},
            ),
            // 2. Crear estructura de carpetas
            TaskAction(
              type: 'create_folder',
              target: 'lib',
            ),
            // 3. Crear main.dart
            TaskAction(
              type: 'create_file',
              target: 'lib/main.dart',
              metadata: {'priority': 'high'},
            ),
            // 4. Crear archivos adicionales según la necesidad
            TaskAction(
              type: 'analyze_and_create',
              target: 'lib/',
              metadata: {'based_on': 'user_message'},
            ),
            // 5. Ejecutar flutter pub get
            TaskAction(
              type: 'run_command',
              target: 'flutter pub get',
            ),
          ]);
        }
        break;
        
      case TaskType.projectModification:
        description = 'Modificar proyecto existente';
        break;
        
      case TaskType.bugFix:
        description = 'Analizar y corregir errores';
        actions.add(TaskAction(
          type: 'analyze_errors',
          target: projectPath,
        ));
        break;
        
      case TaskType.refactor:
        description = 'Refactorizar y mejorar código';
        break;
        
      case TaskType.multiFile:
        description = 'Crear/modificar múltiples archivos';
        break;
        
      case TaskType.singleFile:
        description = 'Crear/modificar archivo individual';
        break;
    }
    
    final plan = ExecutionPlan(
      taskType: taskType,
      description: description,
      actions: actions,
      contextFiles: contextFiles,
      requiresConfirmation: requiresConfirmation,
    );
    
    print('✅ Plan generado:');
    print('   📝 Descripción: $description');
    print('   🎯 Acciones: ${actions.length}');
    print('   📂 Archivos de contexto: ${contextFiles.length}');
    print('   ❓ Requiere confirmación: $requiresConfirmation');
    
    return plan;
  }
  
  /// Construye un contexto enriquecido leyendo los archivos necesarios
  static Future<String> buildEnrichedContext({
    required String projectPath,
    required List<String> contextFiles,
    required String userMessage,
  }) async {
    print('📖 Construyendo contexto enriquecido...');
    
    final contextParts = <String>[];
    
    // Agregar información del proyecto
    contextParts.add('=== ANÁLISIS PREVIO DEL PROYECTO ===\n');
    contextParts.add('Ruta del proyecto: $projectPath\n');
    
    // Detectar tipo de proyecto
    final projectType = await ProjectTypeDetector.detectProjectType(projectPath);
    final projectTypeName = ProjectTypeDetector.getProjectTypeName(projectType);
    contextParts.add('Tipo de proyecto detectado: $projectTypeName\n\n');
    
    // Leer y agregar contenido de archivos clave
    contextParts.add('=== ARCHIVOS EXISTENTES ===\n');
    
    for (final filePath in contextFiles) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          final content = await file.readAsString();
          final fileName = path.basename(filePath);
          
          contextParts.add('--- Archivo: $fileName ---\n');
          contextParts.add(content);
          contextParts.add('\n\n');
          
          print('   ✅ Leído: $fileName (${content.length} chars)');
        }
      } catch (e) {
        print('   ⚠️ Error leyendo $filePath: $e');
      }
    }
    
    // Agregar estructura de carpetas
    contextParts.add('=== ESTRUCTURA DEL PROYECTO ===\n');
    final structure = await _getProjectStructure(projectPath);
    contextParts.add(structure);
    contextParts.add('\n');
    
    final fullContext = contextParts.join('');
    print('✅ Contexto construido: ${fullContext.length} caracteres');
    
    return fullContext;
  }
  
  /// Obtiene la estructura de carpetas del proyecto
  static Future<String> _getProjectStructure(String projectPath) async {
    final lines = <String>[];
    final dir = Directory(projectPath);
    
    if (!await dir.exists()) {
      return 'Proyecto no encontrado';
    }
    
    await _buildStructureRecursive(dir, lines, '', 0, 2);
    
    return lines.join('\n');
  }
  
  static Future<void> _buildStructureRecursive(
    Directory dir,
    List<String> lines,
    String prefix,
    int level,
    int maxLevel,
  ) async {
    if (level >= maxLevel) return;
    
    try {
      final entities = await dir.list().toList();
      entities.sort((a, b) => a.path.compareTo(b.path));
      
      for (var i = 0; i < entities.length; i++) {
        final entity = entities[i];
        final isLast = i == entities.length - 1;
        final name = path.basename(entity.path);
        
        // Ignorar carpetas ocultas y de sistema
        if (name.startsWith('.')) continue;
        if (name == 'build' || name == 'node_modules') continue;
        
        final connector = isLast ? '└── ' : '├── ';
        
        if (entity is Directory) {
          lines.add('$prefix$connector📁 $name/');
          final newPrefix = prefix + (isLast ? '    ' : '│   ');
          await _buildStructureRecursive(entity, lines, newPrefix, level + 1, maxLevel);
        } else {
          lines.add('$prefix$connector📄 $name');
        }
      }
    } catch (e) {
      print('⚠️ Error leyendo directorio ${dir.path}: $e');
    }
  }
}
