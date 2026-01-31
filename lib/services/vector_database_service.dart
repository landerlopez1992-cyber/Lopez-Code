import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';

/// Servicio de base de datos vectorial local para embeddings
/// Implementa RAG (Retrieval Augmented Generation) como Cursor
/// 
/// Basado en documentación de Cursor:
/// "When you open a project, Cursor starts learning about your code. 
/// This is called 'indexing' and it's what makes the AI suggestions accurate."
/// https://docs.cursor.com/get-started/installation
class VectorDatabaseService {
  static Database? _database;
  static const String _dbName = 'code_embeddings.db';
  static const String _tableEmbeddings = 'embeddings';
  
  /// Inicializa la base de datos
  static Future<Database> get database async {
    if (_database != null) return _database!;
    
    _database = await _initDatabase();
    return _database!;
  }
  
  /// Inicializa la base de datos SQLite
  static Future<Database> _initDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final fullPath = path.join(dbPath, _dbName);
      
      print('📂 Inicializando base de datos vectorial en: $fullPath');
      
      return await openDatabase(
        fullPath,
        version: 1,
        onCreate: _createDatabase,
      );
    } catch (e) {
      print('❌ Error al inicializar base de datos: $e');
      rethrow;
    }
  }
  
  /// Crea las tablas necesarias
  static Future<void> _createDatabase(Database db, int version) async {
    print('🏗️ Creando tablas de embeddings...');
    
    // Tabla principal de embeddings
    await db.execute('''
      CREATE TABLE $_tableEmbeddings (
        id TEXT PRIMARY KEY,
        file_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        content TEXT NOT NULL,
        embedding TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        indexed_at INTEGER NOT NULL,
        language TEXT,
        line_start INTEGER,
        line_end INTEGER,
        token_count INTEGER,
        metadata TEXT
      )
    ''');
    
    // Índices para búsqueda rápida
    await db.execute('''
      CREATE INDEX idx_file_path ON $_tableEmbeddings(file_path)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_content_hash ON $_tableEmbeddings(content_hash)
    ''');
    
    await db.execute('''
      CREATE INDEX idx_language ON $_tableEmbeddings(language)
    ''');
    
    print('✅ Tablas creadas correctamente');
  }
  
  /// Guarda un embedding en la base de datos
  static Future<bool> saveEmbedding(CodeEmbedding embedding) async {
    try {
      final db = await database;
      
      await db.insert(
        _tableEmbeddings,
        embedding.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      return true;
    } catch (e) {
      print('❌ Error al guardar embedding: $e');
      return false;
    }
  }
  
  /// Guarda múltiples embeddings en batch (más eficiente)
  static Future<int> saveEmbeddingsBatch(List<CodeEmbedding> embeddings) async {
    try {
      final db = await database;
      final batch = db.batch();
      
      for (final embedding in embeddings) {
        batch.insert(
          _tableEmbeddings,
          embedding.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      
      await batch.commit(noResult: true);
      print('✅ Guardados ${embeddings.length} embeddings');
      
      return embeddings.length;
    } catch (e) {
      print('❌ Error al guardar embeddings en batch: $e');
      return 0;
    }
  }
  
  /// Obtiene todos los embeddings de un archivo
  static Future<List<CodeEmbedding>> getEmbeddingsByFile(String filePath) async {
    try {
      final db = await database;
      
      final List<Map<String, dynamic>> maps = await db.query(
        _tableEmbeddings,
        where: 'file_path = ?',
        whereArgs: [filePath],
      );
      
      return maps.map((map) => CodeEmbedding.fromMap(map)).toList();
    } catch (e) {
      print('❌ Error al obtener embeddings: $e');
      return [];
    }
  }
  
  /// Busca embeddings similares usando similitud de coseno
  /// Este es el método clave para RAG (como Cursor)
  static Future<List<SearchResult>> searchSimilar({
    required List<double> queryEmbedding,
    int limit = 5,
    double minSimilarity = 0.7,
    String? language,
  }) async {
    try {
      final db = await database;
      
      // Obtener todos los embeddings (con filtro de lenguaje si se especifica)
      String whereClause = language != null ? 'language = ?' : '1=1';
      List<dynamic> whereArgs = language != null ? [language] : [];
      
      final List<Map<String, dynamic>> maps = await db.query(
        _tableEmbeddings,
        where: whereClause,
        whereArgs: whereArgs,
      );
      
      if (maps.isEmpty) {
        print('⚠️ No hay embeddings en la base de datos');
        return [];
      }
      
      print('🔍 Buscando similitudes en ${maps.length} embeddings...');
      
      // Calcular similitud de coseno para cada embedding
      final results = <SearchResult>[];
      
      for (final map in maps) {
        final embedding = CodeEmbedding.fromMap(map);
        final similarity = _cosineSimilarity(queryEmbedding, embedding.embedding);
        
        if (similarity >= minSimilarity) {
          results.add(SearchResult(
            embedding: embedding,
            similarity: similarity,
          ));
        }
      }
      
      // Ordenar por similitud descendente
      results.sort((a, b) => b.similarity.compareTo(a.similarity));
      
      // Limitar resultados
      final limitedResults = results.take(limit).toList();
      
      print('✅ Encontrados ${limitedResults.length} resultados similares');
      
      return limitedResults;
    } catch (e) {
      print('❌ Error en búsqueda semántica: $e');
      return [];
    }
  }
  
  /// Calcula la similitud de coseno entre dos vectores
  /// Fórmula: cos(θ) = (A · B) / (||A|| × ||B||)
  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Los vectores deben tener la misma longitud');
    }
    
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    
    if (normA == 0.0 || normB == 0.0) {
      return 0.0;
    }
    
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
  
  /// Función auxiliar para sqrt
  static double sqrt(double x) {
    return x < 0 ? 0 : x == 0 ? 0 : _sqrtNewtonRaphson(x, 1.0);
  }
  
  /// Implementación de raíz cuadrada usando Newton-Raphson
  static double _sqrtNewtonRaphson(double x, double guess) {
    final epsilon = 0.000001;
    final nextGuess = (guess + x / guess) / 2;
    
    if ((nextGuess - guess).abs() < epsilon) {
      return nextGuess;
    }
    
    return _sqrtNewtonRaphson(x, nextGuess);
  }
  
  /// Verifica si un archivo ya está indexado y actualizado
  static Future<bool> isFileIndexed(String filePath, String contentHash) async {
    try {
      final db = await database;
      
      final List<Map<String, dynamic>> maps = await db.query(
        _tableEmbeddings,
        where: 'file_path = ? AND content_hash = ?',
        whereArgs: [filePath, contentHash],
        limit: 1,
      );
      
      return maps.isNotEmpty;
    } catch (e) {
      print('❌ Error al verificar indexación: $e');
      return false;
    }
  }
  
  /// Elimina embeddings de un archivo
  static Future<bool> deleteEmbeddingsByFile(String filePath) async {
    try {
      final db = await database;
      
      await db.delete(
        _tableEmbeddings,
        where: 'file_path = ?',
        whereArgs: [filePath],
      );
      
      print('🗑️ Eliminados embeddings de: $filePath');
      return true;
    } catch (e) {
      print('❌ Error al eliminar embeddings: $e');
      return false;
    }
  }
  
  /// Obtiene estadísticas de la base de datos
  static Future<DatabaseStats> getStats() async {
    try {
      final db = await database;
      
      // Total de embeddings
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableEmbeddings'
      );
      final totalEmbeddings = countResult.first['count'] as int;
      
      // Archivos únicos
      final filesResult = await db.rawQuery(
        'SELECT COUNT(DISTINCT file_path) as count FROM $_tableEmbeddings'
      );
      final uniqueFiles = filesResult.first['count'] as int;
      
      // Lenguajes
      final languagesResult = await db.rawQuery(
        'SELECT language, COUNT(*) as count FROM $_tableEmbeddings GROUP BY language'
      );
      final languageDistribution = Map<String, int>.fromEntries(
        languagesResult.map((row) => MapEntry(
          row['language'] as String? ?? 'unknown',
          row['count'] as int,
        )),
      );
      
      return DatabaseStats(
        totalEmbeddings: totalEmbeddings,
        uniqueFiles: uniqueFiles,
        languageDistribution: languageDistribution,
      );
    } catch (e) {
      print('❌ Error al obtener estadísticas: $e');
      return DatabaseStats(
        totalEmbeddings: 0,
        uniqueFiles: 0,
        languageDistribution: {},
      );
    }
  }
  
  /// Limpia toda la base de datos
  static Future<bool> clearDatabase() async {
    try {
      final db = await database;
      await db.delete(_tableEmbeddings);
      print('🗑️ Base de datos limpiada');
      return true;
    } catch (e) {
      print('❌ Error al limpiar base de datos: $e');
      return false;
    }
  }
  
  /// Cierra la base de datos
  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      print('✅ Base de datos cerrada');
    }
  }
}

/// Modelo de embedding de código
class CodeEmbedding {
  final String id;
  final String filePath;
  final String fileName;
  final String content;
  final List<double> embedding;
  final String contentHash;
  final DateTime indexedAt;
  final String? language;
  final int? lineStart;
  final int? lineEnd;
  final int? tokenCount;
  final Map<String, dynamic>? metadata;
  
  CodeEmbedding({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.content,
    required this.embedding,
    required this.contentHash,
    required this.indexedAt,
    this.language,
    this.lineStart,
    this.lineEnd,
    this.tokenCount,
    this.metadata,
  });
  
  /// Genera un hash del contenido
  static String generateContentHash(String content) {
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_path': filePath,
      'file_name': fileName,
      'content': content,
      'embedding': jsonEncode(embedding),
      'content_hash': contentHash,
      'indexed_at': indexedAt.millisecondsSinceEpoch,
      'language': language,
      'line_start': lineStart,
      'line_end': lineEnd,
      'token_count': tokenCount,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
    };
  }
  
  factory CodeEmbedding.fromMap(Map<String, dynamic> map) {
    return CodeEmbedding(
      id: map['id'] as String,
      filePath: map['file_path'] as String,
      fileName: map['file_name'] as String,
      content: map['content'] as String,
      embedding: List<double>.from(jsonDecode(map['embedding'] as String)),
      contentHash: map['content_hash'] as String,
      indexedAt: DateTime.fromMillisecondsSinceEpoch(map['indexed_at'] as int),
      language: map['language'] as String?,
      lineStart: map['line_start'] as int?,
      lineEnd: map['line_end'] as int?,
      tokenCount: map['token_count'] as int?,
      metadata: map['metadata'] != null 
          ? jsonDecode(map['metadata'] as String) as Map<String, dynamic>
          : null,
    );
  }
}

/// Resultado de búsqueda semántica
class SearchResult {
  final CodeEmbedding embedding;
  final double similarity;
  
  SearchResult({
    required this.embedding,
    required this.similarity,
  });
  
  @override
  String toString() {
    return 'SearchResult(file: ${embedding.fileName}, similarity: ${(similarity * 100).toStringAsFixed(1)}%)';
  }
}

/// Estadísticas de la base de datos
class DatabaseStats {
  final int totalEmbeddings;
  final int uniqueFiles;
  final Map<String, int> languageDistribution;
  
  DatabaseStats({
    required this.totalEmbeddings,
    required this.uniqueFiles,
    required this.languageDistribution,
  });
  
  @override
  String toString() {
    return '''
📊 Estadísticas de Embeddings:
- Total de embeddings: $totalEmbeddings
- Archivos únicos: $uniqueFiles
- Distribución por lenguaje: $languageDistribution
''';
  }
}
