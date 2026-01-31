import 'vector_database_service.dart';
import 'openai_embeddings_service.dart';

/// Servicio de búsqueda semántica de código
/// Implementa RAG (Retrieval Augmented Generation) como Cursor
/// 
/// Según documentación de Cursor:
/// "When you ask a question, Cursor searches through your indexed codebase
/// to find the most relevant files and code snippets."
/// https://docs.cursor.com/context/codebase
class SemanticSearchService {
  /// Busca código relevante para una consulta
  /// Este es el método principal que usa la IA
  static Future<List<CodeSearchResult>> searchRelevantCode({
    required String query,
    int maxResults = 5,
    double minSimilarity = 0.7,
    String? language,
  }) async {
    try {
      print('🔍 Buscando código relevante para: "$query"');
      
      // 1. Generar embedding de la consulta
      final queryEmbedding = await OpenAIEmbeddingsService.generateEmbedding(
        text: query,
      );
      
      if (queryEmbedding == null) {
        print('❌ No se pudo generar embedding para la consulta');
        return [];
      }
      
      print('✅ Embedding de consulta generado (${queryEmbedding.length} dimensiones)');
      
      // 2. Buscar en la base de datos vectorial
      final searchResults = await VectorDatabaseService.searchSimilar(
        queryEmbedding: queryEmbedding,
        limit: maxResults,
        minSimilarity: minSimilarity,
        language: language,
      );
      
      if (searchResults.isEmpty) {
        print('⚠️ No se encontraron resultados similares');
        return [];
      }
      
      print('✅ Encontrados ${searchResults.length} archivos relevantes:');
      
      // 3. Convertir a resultados de búsqueda de código
      final codeResults = searchResults.map((result) {
        print('   📄 ${result.embedding.fileName} (${(result.similarity * 100).toStringAsFixed(1)}% similar)');
        
        return CodeSearchResult(
          filePath: result.embedding.filePath,
          fileName: result.embedding.fileName,
          content: result.embedding.content,
          similarity: result.similarity,
          language: result.embedding.language,
          relevantSnippet: _extractRelevantSnippet(
            result.embedding.content,
            query,
          ),
        );
      }).toList();
      
      return codeResults;
      
    } catch (e, stackTrace) {
      print('❌ Error en búsqueda semántica: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }
  
  /// Busca archivos relacionados con un archivo específico
  /// Útil para encontrar dependencias y código relacionado
  static Future<List<CodeSearchResult>> findRelatedFiles({
    required String filePath,
    int maxResults = 5,
    double minSimilarity = 0.6,
  }) async {
    try {
      print('🔗 Buscando archivos relacionados con: $filePath');
      
      // Obtener embeddings del archivo
      final embeddings = await VectorDatabaseService.getEmbeddingsByFile(filePath);
      
      if (embeddings.isEmpty) {
        print('⚠️ El archivo no está indexado');
        return [];
      }
      
      // Usar el primer embedding para buscar
      final fileEmbedding = embeddings.first;
      
      // Buscar similares
      final searchResults = await VectorDatabaseService.searchSimilar(
        queryEmbedding: fileEmbedding.embedding,
        limit: maxResults + 1, // +1 porque el mismo archivo aparecerá
        minSimilarity: minSimilarity,
      );
      
      // Filtrar el archivo original
      final relatedFiles = searchResults
          .where((result) => result.embedding.filePath != filePath)
          .take(maxResults)
          .map((result) => CodeSearchResult(
                filePath: result.embedding.filePath,
                fileName: result.embedding.fileName,
                content: result.embedding.content,
                similarity: result.similarity,
                language: result.embedding.language,
              ))
          .toList();
      
      print('✅ Encontrados ${relatedFiles.length} archivos relacionados');
      
      return relatedFiles;
      
    } catch (e) {
      print('❌ Error al buscar archivos relacionados: $e');
      return [];
    }
  }
  
  /// Busca definiciones de funciones/clases similares
  static Future<List<CodeSearchResult>> searchSimilarDefinitions({
    required String definitionName,
    String? language,
    int maxResults = 3,
  }) async {
    // Construir consulta optimizada para buscar definiciones
    final query = language == 'dart'
        ? 'class $definitionName { } function $definitionName() { }'
        : 'definition $definitionName implementation';
    
    return await searchRelevantCode(
      query: query,
      maxResults: maxResults,
      minSimilarity: 0.6,
      language: language,
    );
  }
  
  /// Busca ejemplos de uso de una API o librería
  static Future<List<CodeSearchResult>> searchUsageExamples({
    required String apiName,
    int maxResults = 5,
  }) async {
    final query = 'import $apiName usage example implementation';
    
    return await searchRelevantCode(
      query: query,
      maxResults: maxResults,
      minSimilarity: 0.5, // Un poco más flexible
    );
  }
  
  /// Extrae un snippet relevante del contenido
  static String _extractRelevantSnippet(String content, String query) {
    // Dividir en líneas
    final lines = content.split('\n');
    
    if (lines.length <= 10) {
      return content; // Contenido corto, devolver todo
    }
    
    // Buscar líneas que contengan palabras de la consulta
    final queryWords = query.toLowerCase().split(' ');
    final relevantLineIndices = <int>[];
    
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      
      for (final word in queryWords) {
        if (word.length > 3 && line.contains(word)) {
          relevantLineIndices.add(i);
          break;
        }
      }
    }
    
    if (relevantLineIndices.isEmpty) {
      // No se encontraron coincidencias, devolver las primeras líneas
      return lines.take(10).join('\n') + '\n...';
    }
    
    // Obtener contexto alrededor de la primera coincidencia
    final firstMatch = relevantLineIndices.first;
    final start = (firstMatch - 5).clamp(0, lines.length);
    final end = (firstMatch + 15).clamp(0, lines.length);
    
    final snippet = lines.sublist(start, end).join('\n');
    
    return start > 0 ? '...\n$snippet\n...' : '$snippet\n...';
  }
  
  /// Busca toda la información relevante para una pregunta del usuario
  /// Este es el método que se integra con SmartContextManager
  static Future<SemanticSearchContext> buildContextForQuery({
    required String query,
    int maxFiles = 3,
    bool includeRelated = true,
  }) async {
    print('🧠 Construyendo contexto semántico para: "$query"');
    
    final startTime = DateTime.now();
    
    // 1. Buscar archivos directamente relevantes
    final relevantFiles = await searchRelevantCode(
      query: query,
      maxResults: maxFiles,
      minSimilarity: 0.7,
    );
    
    // 2. Si hay resultados y se solicita, buscar archivos relacionados
    final relatedFiles = <CodeSearchResult>[];
    
    if (includeRelated && relevantFiles.isNotEmpty) {
      for (final file in relevantFiles.take(2)) {
        final related = await findRelatedFiles(
          filePath: file.filePath,
          maxResults: 2,
          minSimilarity: 0.6,
        );
        relatedFiles.addAll(related);
      }
    }
    
    final duration = DateTime.now().difference(startTime);
    
    print('✅ Contexto semántico construido en ${duration.inMilliseconds}ms');
    print('   📄 Archivos relevantes: ${relevantFiles.length}');
    print('   🔗 Archivos relacionados: ${relatedFiles.length}');
    
    return SemanticSearchContext(
      query: query,
      relevantFiles: relevantFiles,
      relatedFiles: relatedFiles,
      totalFiles: relevantFiles.length + relatedFiles.length,
      searchDuration: duration,
    );
  }
  
  /// Formatea el contexto para enviar a la IA
  static String formatContextForAI(SemanticSearchContext context) {
    if (context.totalFiles == 0) {
      return '';
    }
    
    final buffer = StringBuffer();
    buffer.writeln('=== CÓDIGO RELEVANTE ENCONTRADO ===\n');
    
    // Archivos directamente relevantes
    if (context.relevantFiles.isNotEmpty) {
      buffer.writeln('📄 Archivos más relevantes:\n');
      
      for (final file in context.relevantFiles) {
        buffer.writeln('**${file.fileName}** (${(file.similarity * 100).toStringAsFixed(1)}% relevante)');
        buffer.writeln('```${file.language ?? ""}');
        buffer.writeln(file.relevantSnippet ?? file.content);
        buffer.writeln('```\n');
      }
    }
    
    // Archivos relacionados (más breve)
    if (context.relatedFiles.isNotEmpty) {
      buffer.writeln('🔗 Archivos relacionados:\n');
      
      for (final file in context.relatedFiles.take(2)) {
        buffer.writeln('- ${file.fileName} (${(file.similarity * 100).toStringAsFixed(1)}% similar)');
      }
      buffer.writeln();
    }
    
    return buffer.toString();
  }
}

/// Resultado de búsqueda de código
class CodeSearchResult {
  final String filePath;
  final String fileName;
  final String content;
  final double similarity;
  final String? language;
  final String? relevantSnippet;
  
  CodeSearchResult({
    required this.filePath,
    required this.fileName,
    required this.content,
    required this.similarity,
    this.language,
    this.relevantSnippet,
  });
  
  @override
  String toString() {
    return 'CodeSearchResult($fileName, ${(similarity * 100).toStringAsFixed(1)}%)';
  }
}

/// Contexto semántico completo
class SemanticSearchContext {
  final String query;
  final List<CodeSearchResult> relevantFiles;
  final List<CodeSearchResult> relatedFiles;
  final int totalFiles;
  final Duration searchDuration;
  
  SemanticSearchContext({
    required this.query,
    required this.relevantFiles,
    required this.relatedFiles,
    required this.totalFiles,
    required this.searchDuration,
  });
  
  bool get hasResults => totalFiles > 0;
  
  @override
  String toString() {
    return '''
SemanticSearchContext:
  Query: $query
  Relevant files: ${relevantFiles.length}
  Related files: ${relatedFiles.length}
  Total: $totalFiles
  Duration: ${searchDuration.inMilliseconds}ms
''';
  }
}
