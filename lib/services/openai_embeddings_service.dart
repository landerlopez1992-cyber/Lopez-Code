import 'dart:convert';
import 'package:http/http.dart' as http;
import 'settings_service.dart';

/// Servicio para generar embeddings usando OpenAI Embeddings API
/// 
/// Basado en documentación de OpenAI:
/// "Embeddings are a numerical representation of text that can be used 
/// to measure the relatedness between two pieces of text."
/// https://platform.openai.com/docs/guides/embeddings
/// 
/// Modelo recomendado: text-embedding-3-small (más económico y rápido)
/// Dimensiones: 1536 (default)
class OpenAIEmbeddingsService {
  static const String _baseUrl = 'https://api.openai.com/v1';
  static const String _embeddingsEndpoint = '/embeddings';
  
  // Modelos disponibles según documentación de OpenAI
  static const String modelSmall = 'text-embedding-3-small';  // Recomendado (económico)
  static const String modelLarge = 'text-embedding-3-large';  // Mayor precisión
  static const String modelAda = 'text-embedding-ada-002';    // Modelo anterior
  
  // Límites según documentación
  static const int maxTokensPerRequest = 8191;  // Límite de tokens por request
  static const int maxBatchSize = 2048;         // Máximo de inputs en batch
  
  /// Genera un embedding para un texto
  static Future<List<double>?> generateEmbedding({
    required String text,
    String model = modelSmall,
  }) async {
    try {
      final apiKey = await SettingsService.getApiKey();
      
      if (apiKey == null || apiKey.isEmpty) {
        print('❌ No hay API key de OpenAI configurada');
        return null;
      }
      
      // Truncar texto si es muy largo (aproximadamente 8000 tokens = 32000 chars)
      final truncatedText = text.length > 32000 
          ? '${text.substring(0, 32000)}...'
          : text;
      
      final response = await http.post(
        Uri.parse('$_baseUrl$_embeddingsEndpoint'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'input': truncatedText,
        }),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final embedding = List<double>.from(data['data'][0]['embedding']);
        
        // Información de uso (para debugging)
        final usage = data['usage'];
        print('✅ Embedding generado: ${usage['total_tokens']} tokens');
        
        return embedding;
      } else {
        final error = jsonDecode(response.body);
        print('❌ Error de OpenAI: ${error['error']['message']}');
        return null;
      }
    } catch (e, stackTrace) {
      print('❌ Error al generar embedding: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }
  
  /// Genera embeddings para múltiples textos en batch (más eficiente)
  /// Según la documentación de OpenAI, batch es más rápido y económico
  static Future<List<List<double>>> generateEmbeddingsBatch({
    required List<String> texts,
    String model = modelSmall,
  }) async {
    try {
      final apiKey = await SettingsService.getApiKey();
      
      if (apiKey == null || apiKey.isEmpty) {
        print('❌ No hay API key de OpenAI configurada');
        return [];
      }
      
      // Limitar batch size según documentación
      if (texts.length > maxBatchSize) {
        print('⚠️ Batch muy grande, procesando en chunks...');
        return await _processBatchInChunks(texts, model);
      }
      
      // Truncar textos si son muy largos
      final truncatedTexts = texts.map((text) {
        return text.length > 32000 ? '${text.substring(0, 32000)}...' : text;
      }).toList();
      
      print('📤 Enviando batch de ${texts.length} textos a OpenAI...');
      
      final response = await http.post(
        Uri.parse('$_baseUrl$_embeddingsEndpoint'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'input': truncatedTexts,
        }),
      ).timeout(const Duration(seconds: 60));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final embeddings = <List<double>>[];
        
        for (final item in data['data']) {
          embeddings.add(List<double>.from(item['embedding']));
        }
        
        // Información de uso
        final usage = data['usage'];
        print('✅ Batch completado: ${embeddings.length} embeddings, ${usage['total_tokens']} tokens');
        
        return embeddings;
      } else {
        final error = jsonDecode(response.body);
        print('❌ Error de OpenAI: ${error['error']['message']}');
        return [];
      }
    } catch (e, stackTrace) {
      print('❌ Error al generar embeddings en batch: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }
  
  /// Procesa batch grande en chunks más pequeños
  static Future<List<List<double>>> _processBatchInChunks(
    List<String> texts,
    String model,
  ) async {
    final allEmbeddings = <List<double>>[];
    final chunkSize = 100; // Procesar 100 a la vez
    
    for (var i = 0; i < texts.length; i += chunkSize) {
      final end = (i + chunkSize < texts.length) ? i + chunkSize : texts.length;
      final chunk = texts.sublist(i, end);
      
      print('📦 Procesando chunk ${i ~/ chunkSize + 1}/${(texts.length / chunkSize).ceil()}');
      
      final embeddings = await generateEmbeddingsBatch(
        texts: chunk,
        model: model,
      );
      
      allEmbeddings.addAll(embeddings);
      
      // Pequeña pausa para no saturar la API
      if (end < texts.length) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    
    return allEmbeddings;
  }
  
  /// Estima el costo de generar embeddings
  /// Según pricing de OpenAI (2024):
  /// - text-embedding-3-small: $0.00002 / 1K tokens
  /// - text-embedding-3-large: $0.00013 / 1K tokens
  static double estimateCost({
    required int tokenCount,
    String model = modelSmall,
  }) {
    final pricePerThousandTokens = model == modelSmall ? 0.00002 : 0.00013;
    return (tokenCount / 1000) * pricePerThousandTokens;
  }
  
  /// Estima tokens de un texto (aproximación)
  static int estimateTokens(String text) {
    // Regla aproximada: 1 token ≈ 4 caracteres
    return (text.length / 4).ceil();
  }
  
  /// Verifica que la API key sea válida
  static Future<bool> verifyApiKey() async {
    try {
      final apiKey = await SettingsService.getApiKey();
      
      if (apiKey == null || apiKey.isEmpty) {
        return false;
      }
      
      // Hacer una petición simple para verificar
      final response = await http.get(
        Uri.parse('$_baseUrl/models'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Error al verificar API key: $e');
      return false;
    }
  }
  
  /// Obtiene información sobre el uso de embeddings
  /// (para mostrar al usuario cuánto ha usado)
  static Future<EmbeddingsUsageInfo> getUsageInfo() async {
    // Esto es una implementación placeholder
    // En producción, deberías trackear esto localmente
    // o usar la API de usage de OpenAI (requiere organización)
    
    return EmbeddingsUsageInfo(
      totalEmbeddingsGenerated: 0,
      totalTokensUsed: 0,
      estimatedCost: 0.0,
    );
  }
}

/// Información de uso de embeddings
class EmbeddingsUsageInfo {
  final int totalEmbeddingsGenerated;
  final int totalTokensUsed;
  final double estimatedCost;
  
  EmbeddingsUsageInfo({
    required this.totalEmbeddingsGenerated,
    required this.totalTokensUsed,
    required this.estimatedCost,
  });
  
  @override
  String toString() {
    return '''
📊 Uso de Embeddings:
- Total generados: $totalEmbeddingsGenerated
- Tokens usados: $totalTokensUsed
- Costo estimado: \$${estimatedCost.toStringAsFixed(4)}
''';
  }
}
