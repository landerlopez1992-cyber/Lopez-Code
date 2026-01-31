import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'web_scraping_service.dart';

/// Servicio profesional para gestionar documentación con scraping
class DocumentationService {
  static const String _documentationKey = 'documentation_sources';
  static const String _contentKey = 'documentation_content';
  
  /// Obtiene todas las fuentes de documentación almacenadas
  static Future<List<DocumentationSource>> getDocumentationSources() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_documentationKey);
    
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => DocumentationSource.fromJson(json)).toList();
    } catch (e) {
      print('❌ Error al cargar documentación: $e');
      return [];
    }
  }
  
  /// Guarda una nueva fuente de documentación Y extrae su contenido
  static Future<bool> addDocumentationSource(DocumentationSource source) async {
    try {
      final sources = await getDocumentationSources();
      
      // Verificar que no exista ya
      if (sources.any((s) => s.url == source.url)) {
        return false; // Ya existe
      }
      
      // Extraer contenido de la URL
      print('📥 Extrayendo contenido de documentación...');
      final content = await WebScrapingService.extractContent(source.url);
      
      if (content != null) {
        // Guardar contenido extraído
        await _saveDocumentationContent(source.url, content);
        print('✅ Contenido extraído y guardado: ${content.wordCount} palabras');
      } else {
        print('⚠️ No se pudo extraer contenido, pero se guardará la URL');
      }
      
      sources.add(source);
      return await _saveDocumentationSources(sources);
    } catch (e) {
      print('❌ Error en addDocumentationSource: $e');
      return false;
    }
  }
  
  /// Guarda el contenido extraído de una documentación
  static Future<bool> _saveDocumentationContent(
    String url,
    DocumentationContent content,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_contentKey\_${content.contentHash}';
      final jsonString = jsonEncode(content.toJson());
      return await prefs.setString(key, jsonString);
    } catch (e) {
      print('❌ Error al guardar contenido: $e');
      return false;
    }
  }
  
  /// Obtiene el contenido extraído de una URL
  static Future<DocumentationContent?> getDocumentationContent(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Buscar por URL
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith(_contentKey)) {
          final jsonString = prefs.getString(key);
          if (jsonString != null) {
            final content = DocumentationContent.fromJson(jsonDecode(jsonString));
            if (content.url == url) {
              return content;
            }
          }
        }
      }
      
      return null;
    } catch (e) {
      print('❌ Error al obtener contenido: $e');
      return null;
    }
  }
  
  /// Obtiene el contenido formateado de todas las documentaciones activas
  static Future<String> getActiveDocumentationContent() async {
    try {
      final sources = await getDocumentationSources();
      final activeSources = sources.where((s) => s.isActive).toList();
      
      if (activeSources.isEmpty) {
        return '';
      }
      
      final buffer = StringBuffer();
      buffer.writeln('=== DOCUMENTACIÓN DE REFERENCIA ===\n');
      
      for (final source in activeSources) {
        final content = await getDocumentationContent(source.url);
        
        if (content != null) {
          buffer.writeln('📚 ${content.title}');
          buffer.writeln('🔗 ${content.url}');
          if (content.description != null) {
            buffer.writeln('📝 ${content.description}');
          }
          buffer.writeln();
          buffer.writeln(content.content);
          buffer.writeln('\n---\n');
        }
      }
      
      return buffer.toString();
    } catch (e) {
      print('❌ Error al obtener contenido activo: $e');
      return '';
    }
  }
  
  /// Refresca el contenido de una documentación (re-scraping)
  static Future<bool> refreshDocumentation(String url) async {
    try {
      print('🔄 Refrescando contenido de: $url');
      final content = await WebScrapingService.extractContent(url);
      
      if (content != null) {
        await _saveDocumentationContent(url, content);
        print('✅ Contenido refrescado correctamente');
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ Error al refrescar documentación: $e');
      return false;
    }
  }
  
  /// Elimina una fuente de documentación y su contenido
  static Future<bool> removeDocumentationSource(String url) async {
    try {
      // Remover de la lista
      final sources = await getDocumentationSources();
      sources.removeWhere((s) => s.url == url);
      
      // Remover contenido almacenado
      final content = await getDocumentationContent(url);
      if (content != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('$_contentKey\_${content.contentHash}');
      }
      
      return await _saveDocumentationSources(sources);
    } catch (e) {
      print('❌ Error al remover documentación: $e');
      return false;
    }
  }
  
  /// Actualiza una fuente de documentación
  static Future<bool> updateDocumentationSource(DocumentationSource source) async {
    final sources = await getDocumentationSources();
    final index = sources.indexWhere((s) => s.url == source.url);
    
    if (index == -1) {
      return false; // No existe
    }
    
    sources[index] = source;
    return await _saveDocumentationSources(sources);
  }
  
  /// Guarda todas las fuentes de documentación
  static Future<bool> _saveDocumentationSources(List<DocumentationSource> sources) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = sources.map((s) => s.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      final success = await prefs.setString(_documentationKey, jsonString);
      
      if (success) {
        print('✅ Documentación guardada correctamente: ${sources.length} fuentes');
      }
      
      return success;
    } catch (e, stackTrace) {
      print('❌ Error al guardar documentación: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }
  
  /// Obtiene las URLs de documentación activas (para usar como tags en el chat)
  static Future<List<String>> getActiveDocumentationUrls() async {
    final sources = await getDocumentationSources();
    return sources.where((s) => s.isActive).map((s) => s.url).toList();
  }
}

/// Modelo para una fuente de documentación
class DocumentationSource {
  final String name;
  final String url;
  final DateTime indexedAt;
  final bool isActive;
  final String? description;
  
  DocumentationSource({
    required this.name,
    required this.url,
    required this.indexedAt,
    this.isActive = true,
    this.description,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
      'indexedAt': indexedAt.toIso8601String(),
      'isActive': isActive,
      'description': description,
    };
  }
  
  factory DocumentationSource.fromJson(Map<String, dynamic> json) {
    return DocumentationSource(
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      indexedAt: DateTime.parse(json['indexedAt'] ?? DateTime.now().toIso8601String()),
      isActive: json['isActive'] ?? true,
      description: json['description'],
    );
  }
  
  DocumentationSource copyWith({
    String? name,
    String? url,
    DateTime? indexedAt,
    bool? isActive,
    String? description,
  }) {
    return DocumentationSource(
      name: name ?? this.name,
      url: url ?? this.url,
      indexedAt: indexedAt ?? this.indexedAt,
      isActive: isActive ?? this.isActive,
      description: description ?? this.description,
    );
  }
}
