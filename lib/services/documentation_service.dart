import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Servicio para gestionar direcciones de documentación
class DocumentationService {
  static const String _documentationKey = 'documentation_sources';
  
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
  
  /// Guarda una nueva fuente de documentación
  static Future<bool> addDocumentationSource(DocumentationSource source) async {
    final sources = await getDocumentationSources();
    
    // Verificar que no exista ya
    if (sources.any((s) => s.url == source.url)) {
      return false; // Ya existe
    }
    
    sources.add(source);
    return await _saveDocumentationSources(sources);
  }
  
  /// Elimina una fuente de documentación
  static Future<bool> removeDocumentationSource(String url) async {
    final sources = await getDocumentationSources();
    sources.removeWhere((s) => s.url == url);
    return await _saveDocumentationSources(sources);
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
      return await prefs.setString(_documentationKey, jsonString);
    } catch (e) {
      print('❌ Error al guardar documentación: $e');
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
