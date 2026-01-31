import 'dart:io';
import 'package:path/path.dart' as path;
import 'project_service.dart';

/// Servicio avanzado de contexto de proyecto
/// Proporciona análisis profundo del proyecto para mejorar la comprensión de la IA

class AdvancedContextService {
  /// Analiza múltiples archivos relacionados y genera un contexto enriquecido
  static Future<ProjectContext> getEnrichedContext(String projectPath, {
    List<String>? specificFiles,
    int maxDepth = 3,
  }) async {
    try {
      final context = ProjectContext(projectPath: projectPath);

      // 1. Analizar estructura del proyecto
      context.structure = await _analyzeProjectStructure(projectPath);

      // 2. Analizar dependencias (pubspec.yaml)
      context.dependencies = await _analyzeDependencies(projectPath);

      // 3. Analizar arquitectura y patrones
      context.architecture = await _detectArchitecture(projectPath);

      // 4. Analizar archivos específicos si se proporcionan
      if (specificFiles != null && specificFiles.isNotEmpty) {
        context.relevantFiles = await _analyzeRelevantFiles(projectPath, specificFiles);
      }

      // 5. Generar mapa de imports/dependencias
      context.importMap = await _generateImportMap(projectPath);

      // 6. Identificar archivos críticos
      context.criticalFiles = await _identifyCriticalFiles(projectPath);

      return context;
    } catch (e) {
      print('❌ Error al obtener contexto enriquecido: $e');
      return ProjectContext(projectPath: projectPath);
    }
  }

  /// Lista contenido de un directorio con resumen de archivos
  static Future<DirectoryListing> listDirectoryWithSummary(
    String dirPath, {
    bool includePreview = true,
    int previewLines = 5,
  }) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        throw Exception('Directorio no existe: $dirPath');
      }

      final listing = DirectoryListing(path: dirPath);
      
      await for (var entity in dir.list()) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          
          // Ignorar archivos binarios y grandes
          if (_shouldSkipFile(fileName)) continue;

          final stat = await entity.stat();
          final fileInfo = FileInfo(
            name: fileName,
            path: entity.path,
            size: stat.size,
            modified: stat.modified,
          );

          // Agregar preview si se solicita
          if (includePreview && stat.size < 100000) { // < 100KB
            try {
              final lines = await entity.readAsLines();
              fileInfo.preview = lines.take(previewLines).join('\n');
              fileInfo.lineCount = lines.length;
              fileInfo.summary = _generateFileSummary(fileName, lines);
            } catch (e) {
              fileInfo.preview = 'No se pudo leer el archivo';
            }
          }

          listing.files.add(fileInfo);
        } else if (entity is Directory) {
          final dirName = path.basename(entity.path);
          if (!_shouldSkipDirectory(dirName)) {
            listing.directories.add(dirName);
          }
        }
      }

      // Ordenar archivos por nombre
      listing.files.sort((a, b) => a.name.compareTo(b.name));
      listing.directories.sort();

      return listing;
    } catch (e) {
      print('❌ Error al listar directorio: $e');
      return DirectoryListing(path: dirPath);
    }
  }

  /// Lee múltiples archivos y retorna su contenido con contexto
  static Future<Map<String, FileContent>> readMultipleFiles(
    List<String> filePaths,
    String projectPath,
  ) async {
    final result = <String, FileContent>{};

    for (var filePath in filePaths) {
      try {
        final fullPath = filePath.startsWith('/')
            ? filePath
            : path.join(projectPath, filePath);

        final file = File(fullPath);
        if (!await file.exists()) {
          result[filePath] = FileContent(
            path: filePath,
            error: 'Archivo no encontrado',
          );
          continue;
        }

        final content = await file.readAsString();
        final lines = content.split('\n');

        result[filePath] = FileContent(
          path: filePath,
          content: content,
          lineCount: lines.length,
          imports: _extractImports(content),
          classes: _extractClasses(content),
          functions: _extractFunctions(content),
          summary: _generateFileSummary(path.basename(filePath), lines),
        );
      } catch (e) {
        result[filePath] = FileContent(
          path: filePath,
          error: 'Error al leer: $e',
        );
      }
    }

    return result;
  }

  /// Analiza la estructura del proyecto
  static Future<ProjectStructure> _analyzeProjectStructure(String projectPath) async {
    final structure = ProjectStructure();

    final libDir = Directory(path.join(projectPath, 'lib'));
    if (await libDir.exists()) {
      structure.libFolders = await _getFolderStructure(libDir.path);
    }

    // Detectar carpetas principales
    structure.hasModels = await Directory(path.join(projectPath, 'lib/models')).exists();
    structure.hasServices = await Directory(path.join(projectPath, 'lib/services')).exists();
    structure.hasWidgets = await Directory(path.join(projectPath, 'lib/widgets')).exists();
    structure.hasScreens = await Directory(path.join(projectPath, 'lib/screens')).exists();
    structure.hasUtils = await Directory(path.join(projectPath, 'lib/utils')).exists();

    return structure;
  }

  /// Analiza dependencias del pubspec.yaml
  static Future<DependencyInfo> _analyzeDependencies(String projectPath) async {
    final info = DependencyInfo();

    try {
      final pubspecFile = File(path.join(projectPath, 'pubspec.yaml'));
      if (!await pubspecFile.exists()) return info;

      final content = await pubspecFile.readAsString();
      final lines = content.split('\n');

      bool inDependencies = false;
      bool inDevDependencies = false;

      for (var line in lines) {
        if (line.trim() == 'dependencies:') {
          inDependencies = true;
          inDevDependencies = false;
          continue;
        } else if (line.trim() == 'dev_dependencies:') {
          inDependencies = false;
          inDevDependencies = true;
          continue;
        } else if (line.trim().isEmpty || !line.startsWith(' ')) {
          inDependencies = false;
          inDevDependencies = false;
        }

        if (inDependencies && line.trim().isNotEmpty && line.contains(':')) {
          final parts = line.trim().split(':');
          if (parts.isNotEmpty) {
            info.dependencies.add(parts[0].trim());
          }
        } else if (inDevDependencies && line.trim().isNotEmpty && line.contains(':')) {
          final parts = line.trim().split(':');
          if (parts.isNotEmpty) {
            info.devDependencies.add(parts[0].trim());
          }
        }
      }

      // Detectar categorías de dependencias
      info.hasStateManagement = info.dependencies.any((dep) =>
          dep.contains('provider') ||
          dep.contains('riverpod') ||
          dep.contains('bloc') ||
          dep.contains('get') ||
          dep.contains('mobx'));

      info.hasHTTP = info.dependencies.any((dep) =>
          dep.contains('http') || dep.contains('dio'));

      info.hasDatabase = info.dependencies.any((dep) =>
          dep.contains('sqflite') ||
          dep.contains('hive') ||
          dep.contains('firebase'));

    } catch (e) {
      print('⚠️ Error al analizar dependencias: $e');
    }

    return info;
  }

  /// Detecta la arquitectura del proyecto
  static Future<ArchitectureInfo> _detectArchitecture(String projectPath) async {
    final info = ArchitectureInfo();

    try {
      final libPath = path.join(projectPath, 'lib');

      // Detectar Clean Architecture
      if (await Directory(path.join(libPath, 'domain')).exists() &&
          await Directory(path.join(libPath, 'data')).exists() &&
          await Directory(path.join(libPath, 'presentation')).exists()) {
        info.type = 'Clean Architecture';
        info.patterns.add('Repository Pattern');
        info.patterns.add('Use Cases');
      }
      // Detectar MVC
      else if (await Directory(path.join(libPath, 'controllers')).exists() &&
          await Directory(path.join(libPath, 'views')).exists()) {
        info.type = 'MVC';
      }
      // Detectar MVVM
      else if (await Directory(path.join(libPath, 'viewmodels')).exists() ||
          await Directory(path.join(libPath, 'view_models')).exists()) {
        info.type = 'MVVM';
      }
      // Detectar BLoC
      else if (await Directory(path.join(libPath, 'blocs')).exists() ||
          await Directory(path.join(libPath, 'bloc')).exists()) {
        info.type = 'BLoC Pattern';
        info.patterns.add('Event-Driven');
      }
      // Estructura básica
      else {
        info.type = 'Basic Structure';
      }

      // Detectar patrones adicionales
      if (await Directory(path.join(libPath, 'services')).exists()) {
        info.patterns.add('Service Layer');
      }
      if (await Directory(path.join(libPath, 'repositories')).exists()) {
        info.patterns.add('Repository Pattern');
      }
      if (await Directory(path.join(libPath, 'providers')).exists()) {
        info.patterns.add('Provider Pattern');
      }

    } catch (e) {
      print('⚠️ Error al detectar arquitectura: $e');
    }

    return info;
  }

  /// Analiza archivos relevantes
  static Future<List<FileAnalysis>> _analyzeRelevantFiles(
    String projectPath,
    List<String> files,
  ) async {
    final analyses = <FileAnalysis>[];

    for (var filePath in files) {
      try {
        final fullPath = path.join(projectPath, filePath);
        final file = File(fullPath);

        if (!await file.exists()) continue;

        final content = await file.readAsString();
        final analysis = FileAnalysis(
          path: filePath,
          imports: _extractImports(content),
          classes: _extractClasses(content),
          functions: _extractFunctions(content),
          widgets: _extractWidgets(content),
        );

        analyses.add(analysis);
      } catch (e) {
        print('⚠️ Error al analizar $filePath: $e');
      }
    }

    return analyses;
  }

  /// Genera mapa de imports
  static Future<Map<String, List<String>>> _generateImportMap(String projectPath) async {
    final importMap = <String, List<String>>{};

    try {
      final libDir = Directory(path.join(projectPath, 'lib'));
      if (!await libDir.exists()) return importMap;

      await for (var entity in libDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          final relativePath = path.relative(entity.path, from: projectPath);
          final content = await entity.readAsString();
          final imports = _extractImports(content);
          importMap[relativePath] = imports;
        }
      }
    } catch (e) {
      print('⚠️ Error al generar mapa de imports: $e');
    }

    return importMap;
  }

  /// Identifica archivos críticos del proyecto
  static Future<List<String>> _identifyCriticalFiles(String projectPath) async {
    final critical = <String>[];

    final criticalNames = [
      'main.dart',
      'pubspec.yaml',
      'app.dart',
      'routes.dart',
      'config.dart',
      'constants.dart',
    ];

    try {
      final libDir = Directory(path.join(projectPath, 'lib'));
      if (await libDir.exists()) {
        await for (var entity in libDir.list(recursive: true)) {
          if (entity is File) {
            final fileName = path.basename(entity.path);
            if (criticalNames.contains(fileName)) {
              critical.add(path.relative(entity.path, from: projectPath));
            }
          }
        }
      }

      // Agregar pubspec.yaml
      if (await File(path.join(projectPath, 'pubspec.yaml')).exists()) {
        critical.add('pubspec.yaml');
      }
    } catch (e) {
      print('⚠️ Error al identificar archivos críticos: $e');
    }

    return critical;
  }

  // Utilidades privadas

  static Future<List<String>> _getFolderStructure(String dirPath) async {
    final folders = <String>[];
    try {
      final dir = Directory(dirPath);
      await for (var entity in dir.list()) {
        if (entity is Directory) {
          final folderName = path.basename(entity.path);
          if (!_shouldSkipDirectory(folderName)) {
            folders.add(folderName);
          }
        }
      }
    } catch (e) {
      print('⚠️ Error al obtener estructura: $e');
    }
    return folders;
  }

  static bool _shouldSkipFile(String fileName) {
    return fileName.startsWith('.') ||
        fileName.endsWith('.g.dart') ||
        fileName.endsWith('.freezed.dart') ||
        fileName.endsWith('.mocks.dart');
  }

  static bool _shouldSkipDirectory(String dirName) {
    return dirName.startsWith('.') ||
        dirName == 'build' ||
        dirName == 'node_modules';
  }

  static List<String> _extractImports(String content) {
    final imports = <String>[];
    final regex = RegExp(r'''import\s+['"]([^'"]+)['"]''');
    for (var match in regex.allMatches(content)) {
      if (match.group(1) != null) {
        imports.add(match.group(1)!);
      }
    }
    return imports;
  }

  static List<String> _extractClasses(String content) {
    final classes = <String>[];
    final regex = RegExp(r'class\s+(\w+)');
    for (var match in regex.allMatches(content)) {
      if (match.group(1) != null) {
        classes.add(match.group(1)!);
      }
    }
    return classes;
  }

  static List<String> _extractFunctions(String content) {
    final functions = <String>[];
    final regex = RegExp(r'(?:Future<\w+>|void|String|int|bool|double)\s+(\w+)\s*\(');
    for (var match in regex.allMatches(content)) {
      if (match.group(1) != null) {
        functions.add(match.group(1)!);
      }
    }
    return functions;
  }

  static List<String> _extractWidgets(String content) {
    final widgets = <String>[];
    final regex = RegExp(r'class\s+(\w+)\s+extends\s+(?:StatelessWidget|StatefulWidget)');
    for (var match in regex.allMatches(content)) {
      if (match.group(1) != null) {
        widgets.add(match.group(1)!);
      }
    }
    return widgets;
  }

  static String _generateFileSummary(String fileName, List<String> lines) {
    if (fileName.endsWith('_screen.dart')) {
      return 'Pantalla de la aplicación';
    } else if (fileName.endsWith('_service.dart')) {
      return 'Servicio de lógica de negocio';
    } else if (fileName.endsWith('_widget.dart')) {
      return 'Widget reutilizable';
    } else if (fileName.endsWith('_model.dart')) {
      return 'Modelo de datos';
    } else if (fileName == 'main.dart') {
      return 'Punto de entrada de la aplicación';
    } else {
      return 'Archivo Dart (${lines.length} líneas)';
    }
  }
}

// Modelos de datos

class ProjectContext {
  final String projectPath;
  ProjectStructure? structure;
  DependencyInfo? dependencies;
  ArchitectureInfo? architecture;
  List<FileAnalysis>? relevantFiles;
  Map<String, List<String>>? importMap;
  List<String>? criticalFiles;

  ProjectContext({required this.projectPath});

  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.writeln('# CONTEXTO DEL PROYECTO');
    buffer.writeln('Ruta: $projectPath');
    buffer.writeln('');

    if (structure != null) {
      buffer.writeln('## ESTRUCTURA');
      buffer.writeln(structure!.toFormattedString());
      buffer.writeln('');
    }

    if (dependencies != null) {
      buffer.writeln('## DEPENDENCIAS');
      buffer.writeln(dependencies!.toFormattedString());
      buffer.writeln('');
    }

    if (architecture != null) {
      buffer.writeln('## ARQUITECTURA');
      buffer.writeln(architecture!.toFormattedString());
      buffer.writeln('');
    }

    if (criticalFiles != null && criticalFiles!.isNotEmpty) {
      buffer.writeln('## ARCHIVOS CRÍTICOS');
      for (var file in criticalFiles!) {
        buffer.writeln('- $file');
      }
    }

    return buffer.toString();
  }
}

class ProjectStructure {
  List<String> libFolders = [];
  bool hasModels = false;
  bool hasServices = false;
  bool hasWidgets = false;
  bool hasScreens = false;
  bool hasUtils = false;

  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.writeln('Carpetas en lib/: ${libFolders.join(", ")}');
    if (hasModels) buffer.writeln('✓ Tiene models/');
    if (hasServices) buffer.writeln('✓ Tiene services/');
    if (hasWidgets) buffer.writeln('✓ Tiene widgets/');
    if (hasScreens) buffer.writeln('✓ Tiene screens/');
    if (hasUtils) buffer.writeln('✓ Tiene utils/');
    return buffer.toString();
  }
}

class DependencyInfo {
  List<String> dependencies = [];
  List<String> devDependencies = [];
  bool hasStateManagement = false;
  bool hasHTTP = false;
  bool hasDatabase = false;

  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.writeln('Dependencias principales: ${dependencies.take(10).join(", ")}');
    if (hasStateManagement) buffer.writeln('✓ Gestión de estado detectada');
    if (hasHTTP) buffer.writeln('✓ Cliente HTTP presente');
    if (hasDatabase) buffer.writeln('✓ Base de datos presente');
    return buffer.toString();
  }
}

class ArchitectureInfo {
  String type = 'Unknown';
  List<String> patterns = [];

  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.writeln('Tipo: $type');
    if (patterns.isNotEmpty) {
      buffer.writeln('Patrones: ${patterns.join(", ")}');
    }
    return buffer.toString();
  }
}

class FileAnalysis {
  final String path;
  final List<String> imports;
  final List<String> classes;
  final List<String> functions;
  final List<String> widgets;

  FileAnalysis({
    required this.path,
    this.imports = const [],
    this.classes = const [],
    this.functions = const [],
    this.widgets = const [],
  });
}

class DirectoryListing {
  final String path;
  List<FileInfo> files = [];
  List<String> directories = [];

  DirectoryListing({required this.path});
}

class FileInfo {
  final String name;
  final String path;
  final int size;
  final DateTime modified;
  String? preview;
  int? lineCount;
  String? summary;

  FileInfo({
    required this.name,
    required this.path,
    required this.size,
    required this.modified,
    this.preview,
    this.lineCount,
    this.summary,
  });
}

class FileContent {
  final String path;
  String? content;
  String? error;
  int? lineCount;
  List<String>? imports;
  List<String>? classes;
  List<String>? functions;
  String? summary;

  FileContent({
    required this.path,
    this.content,
    this.error,
    this.lineCount,
    this.imports,
    this.classes,
    this.functions,
    this.summary,
  });
}
