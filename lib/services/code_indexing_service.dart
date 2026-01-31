import 'dart:io';
import 'package:path/path.dart' as path;
import 'vector_database_service.dart';
import 'openai_embeddings_service.dart';

/// Servicio de indexación de código
/// Implementa el sistema de indexación semántica como Cursor
/// 
/// Según documentación de Cursor:
/// "Cursor automatically indexes your codebase to understand context.
/// This happens in the background and makes suggestions more accurate."
/// https://docs.cursor.com/get-started/codebase-indexing
class CodeIndexingService {
  // Extensiones de archivo soportadas
  static const List<String> _supportedExtensions = [
    '.dart',
    '.yaml',
    '.json',
    '.md',
    '.txt',
    '.xml',
    '.gradle',
    '.properties',
    '.swift',
    '.kt',
    '.java',
  ];
  
  // Directorios a ignorar
  static const List<String> _ignoredDirectories = [
    '.dart_tool',
    'build',
    '.idea',
    '.vscode',
    'node_modules',
    '.git',
    'ios/Pods',
    'android/.gradle',
    'android/build',
    'macos/Pods',
    '.symlinks',
  ];
  
  // Tamaño máximo de archivo (1MB)
  static const int _maxFileSize = 1024 * 1024;
  
  /// Indexa un proyecto completo
  static Future<IndexingResult> indexProject(String projectPath) async {
    print('🚀 Iniciando indexación del proyecto: $projectPath');
    print('⏱️ Esto puede tomar varios minutos dependiendo del tamaño...');
    
    final startTime = DateTime.now();
    int filesProcessed = 0;
    int filesSkipped = 0;
    int embeddingsCreated = 0;
    int errors = 0;
    
    try {
      final projectDir = Directory(projectPath);
      
      if (!await projectDir.exists()) {
        print('❌ El directorio no existe: $projectPath');
        return IndexingResult(
          success: false,
          filesProcessed: 0,
          filesSkipped: 0,
          embeddingsCreated: 0,
          errors: 1,
          duration: Duration.zero,
        );
      }
      
      // Obtener todos los archivos del proyecto
      final files = await _getProjectFiles(projectPath);
      print('📁 Encontrados ${files.length} archivos para indexar');
      
      if (files.isEmpty) {
        print('⚠️ No se encontraron archivos para indexar');
        return IndexingResult(
          success: true,
          filesProcessed: 0,
          filesSkipped: 0,
          embeddingsCreated: 0,
          errors: 0,
          duration: Duration.zero,
        );
      }
      
      // Procesar archivos en batches para eficiencia
      final batchSize = 10; // Procesar 10 archivos a la vez
      
      for (var i = 0; i < files.length; i += batchSize) {
        final end = (i + batchSize < files.length) ? i + batchSize : files.length;
        final batch = files.sublist(i, end);
        
        print('📦 Procesando batch ${i ~/ batchSize + 1}/${(files.length / batchSize).ceil()}...');
        
        final batchResults = await _indexFilesBatch(batch, projectPath);
        
        filesProcessed += batchResults.filesProcessed;
        filesSkipped += batchResults.filesSkipped;
        embeddingsCreated += batchResults.embeddingsCreated;
        errors += batchResults.errors;
        
        // Mostrar progreso
        final progress = ((i + batch.length) / files.length * 100).toStringAsFixed(1);
        print('📊 Progreso: $progress% ($filesProcessed/${{files.length}} archivos)');
      }
      
      final duration = DateTime.now().difference(startTime);
      
      print('\n✅ Indexación completada en ${duration.inSeconds}s');
      print('📊 Resultados:');
      print('   - Archivos procesados: $filesProcessed');
      print('   - Archivos omitidos: $filesSkipped');
      print('   - Embeddings creados: $embeddingsCreated');
      print('   - Errores: $errors');
      
      return IndexingResult(
        success: errors == 0,
        filesProcessed: filesProcessed,
        filesSkipped: filesSkipped,
        embeddingsCreated: embeddingsCreated,
        errors: errors,
        duration: duration,
      );
      
    } catch (e, stackTrace) {
      print('❌ Error durante la indexación: $e');
      print('Stack trace: $stackTrace');
      
      return IndexingResult(
        success: false,
        filesProcessed: filesProcessed,
        filesSkipped: filesSkipped,
        embeddingsCreated: embeddingsCreated,
        errors: errors + 1,
        duration: DateTime.now().difference(startTime),
      );
    }
  }
  
  /// Obtiene todos los archivos del proyecto
  static Future<List<File>> _getProjectFiles(String projectPath) async {
    final files = <File>[];
    final projectDir = Directory(projectPath);
    
    await for (final entity in projectDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        // Verificar que no esté en directorio ignorado
        if (_shouldIgnoreFile(entity.path, projectPath)) {
          continue;
        }
        
        // Verificar extensión soportada
        final ext = path.extension(entity.path).toLowerCase();
        if (!_supportedExtensions.contains(ext)) {
          continue;
        }
        
        // Verificar tamaño
        final stat = await entity.stat();
        if (stat.size > _maxFileSize) {
          print('⚠️ Archivo muy grande, omitiendo: ${path.basename(entity.path)}');
          continue;
        }
        
        files.add(entity);
      }
    }
    
    return files;
  }
  
  /// Verifica si un archivo debe ser ignorado
  static bool _shouldIgnoreFile(String filePath, String projectPath) {
    final relativePath = path.relative(filePath, from: projectPath);
    
    for (final ignored in _ignoredDirectories) {
      if (relativePath.contains(ignored)) {
        return true;
      }
    }
    
    return false;
  }
  
  /// Indexa un batch de archivos
  static Future<IndexingResult> _indexFilesBatch(
    List<File> files,
    String projectPath,
  ) async {
    int filesProcessed = 0;
    int filesSkipped = 0;
    int embeddingsCreated = 0;
    int errors = 0;
    
    // Leer contenido de todos los archivos
    final fileContents = <String>[];
    final fileInfos = <Map<String, dynamic>>[];
    
    for (final file in files) {
      try {
        final content = await file.readAsString();
        
        // Verificar si ya está indexado
        final contentHash = CodeEmbedding.generateContentHash(content);
        final isIndexed = await VectorDatabaseService.isFileIndexed(
          file.path,
          contentHash,
        );
        
        if (isIndexed) {
          filesSkipped++;
          continue;
        }
        
        fileContents.add(content);
        fileInfos.add({
          'file': file,
          'content': content,
          'contentHash': contentHash,
        });
        
      } catch (e) {
        print('❌ Error al leer archivo ${path.basename(file.path)}: $e');
        errors++;
      }
    }
    
    if (fileContents.isEmpty) {
      return IndexingResult(
        success: true,
        filesProcessed: 0,
        filesSkipped: filesSkipped,
        embeddingsCreated: 0,
        errors: errors,
        duration: Duration.zero,
      );
    }
    
    // Generar embeddings en batch
    final embeddings = await OpenAIEmbeddingsService.generateEmbeddingsBatch(
      texts: fileContents,
    );
    
    if (embeddings.length != fileContents.length) {
      print('⚠️ No se pudieron generar todos los embeddings');
      errors += fileContents.length - embeddings.length;
    }
    
    // Guardar en base de datos
    final codeEmbeddings = <CodeEmbedding>[];
    
    for (var i = 0; i < embeddings.length; i++) {
      final fileInfo = fileInfos[i];
      final file = fileInfo['file'] as File;
      final content = fileInfo['content'] as String;
      final contentHash = fileInfo['contentHash'] as String;
      
      final codeEmbedding = CodeEmbedding(
        id: '${file.path}_${DateTime.now().millisecondsSinceEpoch}',
        filePath: file.path,
        fileName: path.basename(file.path),
        content: content,
        embedding: embeddings[i],
        contentHash: contentHash,
        indexedAt: DateTime.now(),
        language: _detectLanguage(file.path),
        tokenCount: OpenAIEmbeddingsService.estimateTokens(content),
      );
      
      codeEmbeddings.add(codeEmbedding);
    }
    
    // Guardar en batch
    final saved = await VectorDatabaseService.saveEmbeddingsBatch(codeEmbeddings);
    
    filesProcessed = saved;
    embeddingsCreated = saved;
    
    return IndexingResult(
      success: true,
      filesProcessed: filesProcessed,
      filesSkipped: filesSkipped,
      embeddingsCreated: embeddingsCreated,
      errors: errors,
      duration: Duration.zero,
    );
  }
  
  /// Detecta el lenguaje de un archivo por su extensión
  static String _detectLanguage(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    
    switch (ext) {
      case '.dart':
        return 'dart';
      case '.yaml':
      case '.yml':
        return 'yaml';
      case '.json':
        return 'json';
      case '.md':
        return 'markdown';
      case '.swift':
        return 'swift';
      case '.kt':
        return 'kotlin';
      case '.java':
        return 'java';
      case '.xml':
        return 'xml';
      default:
        return 'text';
    }
  }
  
  /// Reindexar un archivo específico (cuando cambia)
  static Future<bool> reindexFile(String filePath) async {
    try {
      print('🔄 Reindexando: ${path.basename(filePath)}');
      
      final file = File(filePath);
      
      if (!await file.exists()) {
        print('❌ El archivo no existe');
        return false;
      }
      
      // Eliminar embeddings antiguos
      await VectorDatabaseService.deleteEmbeddingsByFile(filePath);
      
      // Leer contenido
      final content = await file.readAsString();
      
      // Generar embedding
      final embedding = await OpenAIEmbeddingsService.generateEmbedding(
        text: content,
      );
      
      if (embedding == null) {
        print('❌ No se pudo generar embedding');
        return false;
      }
      
      // Guardar
      final codeEmbedding = CodeEmbedding(
        id: '${filePath}_${DateTime.now().millisecondsSinceEpoch}',
        filePath: filePath,
        fileName: path.basename(filePath),
        content: content,
        embedding: embedding,
        contentHash: CodeEmbedding.generateContentHash(content),
        indexedAt: DateTime.now(),
        language: _detectLanguage(filePath),
        tokenCount: OpenAIEmbeddingsService.estimateTokens(content),
      );
      
      await VectorDatabaseService.saveEmbedding(codeEmbedding);
      
      print('✅ Archivo reindexado correctamente');
      return true;
      
    } catch (e) {
      print('❌ Error al reindexar archivo: $e');
      return false;
    }
  }
  
  /// Limpia el índice completo
  static Future<bool> clearIndex() async {
    print('🗑️ Limpiando índice completo...');
    return await VectorDatabaseService.clearDatabase();
  }
}

/// Resultado de indexación
class IndexingResult {
  final bool success;
  final int filesProcessed;
  final int filesSkipped;
  final int embeddingsCreated;
  final int errors;
  final Duration duration;
  
  IndexingResult({
    required this.success,
    required this.filesProcessed,
    required this.filesSkipped,
    required this.embeddingsCreated,
    required this.errors,
    required this.duration,
  });
  
  @override
  String toString() {
    return '''
IndexingResult:
  Success: $success
  Files processed: $filesProcessed
  Files skipped: $filesSkipped
  Embeddings created: $embeddingsCreated
  Errors: $errors
  Duration: ${duration.inSeconds}s
''';
  }
}
