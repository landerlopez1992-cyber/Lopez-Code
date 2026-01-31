import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:crypto/crypto.dart';

/// Servicio profesional para extraer y procesar contenido de URLs
/// Similar al sistema de Cursor para documentación
class WebScrapingService {
  static const int _maxContentLength = 50000; // Limitar a 50k caracteres
  static const Duration _timeout = Duration(seconds: 30);
  
  /// Extrae contenido limpio de una URL
  static Future<DocumentationContent?> extractContent(String url) async {
    try {
      print('🌐 Extrayendo contenido de: $url');
      
      // Hacer petición HTTP
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        },
      ).timeout(_timeout);
      
      if (response.statusCode != 200) {
        print('❌ Error HTTP ${response.statusCode}');
        return null;
      }
      
      // Parsear HTML
      final document = html_parser.parse(response.body);
      
      // Extraer contenido
      final title = _extractTitle(document);
      final content = _extractMainContent(document);
      final description = _extractDescription(document);
      
      if (content.isEmpty) {
        print('⚠️ No se pudo extraer contenido');
        return null;
      }
      
      // Limpiar y formatear
      final cleanContent = _cleanContent(content);
      final truncatedContent = _truncateContent(cleanContent);
      
      // Generar hash para identificación
      final contentHash = _generateHash(url);
      
      print('✅ Contenido extraído: ${truncatedContent.length} caracteres');
      
      return DocumentationContent(
        url: url,
        title: title,
        description: description,
        content: truncatedContent,
        contentHash: contentHash,
        extractedAt: DateTime.now(),
        wordCount: truncatedContent.split(' ').length,
      );
      
    } catch (e, stackTrace) {
      print('❌ Error al extraer contenido: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }
  
  /// Extrae el título de la página
  static String _extractTitle(Document document) {
    // Intentar varios selectores comunes
    final titleElement = 
        document.querySelector('h1') ??
        document.querySelector('title') ??
        document.querySelector('.page-title') ??
        document.querySelector('.post-title');
    
    return titleElement?.text.trim() ?? 'Sin título';
  }
  
  /// Extrae la descripción de la página
  static String? _extractDescription(Document document) {
    final metaDesc = document.querySelector('meta[name="description"]');
    return metaDesc?.attributes['content']?.trim();
  }
  
  /// Extrae el contenido principal de la página
  static String _extractMainContent(Document document) {
    // Remover elementos no deseados
    _removeUnwantedElements(document);
    
    // Intentar varios selectores para el contenido principal
    final contentElement = 
        document.querySelector('article') ??
        document.querySelector('main') ??
        document.querySelector('.content') ??
        document.querySelector('.post-content') ??
        document.querySelector('.article-content') ??
        document.querySelector('#content') ??
        document.body;
    
    if (contentElement == null) {
      return '';
    }
    
    // Extraer texto preservando estructura
    return _extractTextWithStructure(contentElement);
  }
  
  /// Remueve elementos no deseados (scripts, styles, ads, etc.)
  static void _removeUnwantedElements(Document document) {
    final selectorsToRemove = [
      'script',
      'style',
      'noscript',
      'iframe',
      'nav',
      'header',
      'footer',
      '.ad',
      '.advertisement',
      '.sidebar',
      '.cookie-banner',
      '.popup',
      '#comments',
      '.social-share',
    ];
    
    for (final selector in selectorsToRemove) {
      document.querySelectorAll(selector).forEach((element) {
        element.remove();
      });
    }
  }
  
  /// Extrae texto preservando estructura jerárquica
  static String _extractTextWithStructure(Element element) {
    final buffer = StringBuffer();
    
    void processNode(Element node, int level) {
      // Procesar headings con formato
      if (node.localName?.startsWith('h') == true) {
        final headingLevel = int.tryParse(node.localName!.substring(1)) ?? 1;
        buffer.writeln('\n${'#' * headingLevel} ${node.text.trim()}\n');
        return;
      }
      
      // Procesar párrafos
      if (node.localName == 'p') {
        final text = node.text.trim();
        if (text.isNotEmpty) {
          buffer.writeln('$text\n');
        }
        return;
      }
      
      // Procesar listas
      if (node.localName == 'li') {
        buffer.writeln('• ${node.text.trim()}');
        return;
      }
      
      // Procesar código
      if (node.localName == 'code' || node.localName == 'pre') {
        buffer.writeln('```\n${node.text.trim()}\n```\n');
        return;
      }
      
      // Procesar hijos recursivamente
      for (final child in node.children) {
        processNode(child, level + 1);
      }
      
      // Si no tiene hijos y tiene texto, agregarlo
      if (node.children.isEmpty && node.text.trim().isNotEmpty) {
        buffer.write('${node.text.trim()} ');
      }
    }
    
    processNode(element, 0);
    return buffer.toString();
  }
  
  /// Limpia y normaliza el contenido
  static String _cleanContent(String content) {
    // Eliminar múltiples espacios y líneas vacías
    var cleaned = content
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n')
        .trim();
    
    // Eliminar caracteres especiales problemáticos
    cleaned = cleaned
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
        .replaceAll('​', '') // Zero-width space
        .replaceAll('', ''); // Zero-width non-joiner
    
    return cleaned;
  }
  
  /// Trunca el contenido si es muy largo
  static String _truncateContent(String content) {
    if (content.length <= _maxContentLength) {
      return content;
    }
    
    // Truncar en el último punto o párrafo completo
    final truncated = content.substring(0, _maxContentLength);
    final lastPeriod = truncated.lastIndexOf('.');
    final lastNewline = truncated.lastIndexOf('\n');
    
    final cutPoint = lastPeriod > lastNewline ? lastPeriod : lastNewline;
    
    if (cutPoint > _maxContentLength - 1000) {
      return '${truncated.substring(0, cutPoint + 1)}\n\n[Contenido truncado...]';
    }
    
    return '$truncated...\n\n[Contenido truncado...]';
  }
  
  /// Genera hash único para la URL
  static String _generateHash(String url) {
    final bytes = utf8.encode(url);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

/// Modelo para contenido de documentación extraído
class DocumentationContent {
  final String url;
  final String title;
  final String? description;
  final String content;
  final String contentHash;
  final DateTime extractedAt;
  final int wordCount;
  
  DocumentationContent({
    required this.url,
    required this.title,
    this.description,
    required this.content,
    required this.contentHash,
    required this.extractedAt,
    required this.wordCount,
  });
  
  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'description': description,
    'content': content,
    'contentHash': contentHash,
    'extractedAt': extractedAt.toIso8601String(),
    'wordCount': wordCount,
  };
  
  factory DocumentationContent.fromJson(Map<String, dynamic> json) {
    return DocumentationContent(
      url: json['url'] ?? '',
      title: json['title'] ?? '',
      description: json['description'],
      content: json['content'] ?? '',
      contentHash: json['contentHash'] ?? '',
      extractedAt: DateTime.parse(json['extractedAt'] ?? DateTime.now().toIso8601String()),
      wordCount: json['wordCount'] ?? 0,
    );
  }
}
