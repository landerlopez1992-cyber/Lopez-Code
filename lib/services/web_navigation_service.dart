import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'project_service.dart';

/// Servicio para navegación web y descarga de archivos para la IA
class WebNavigationService {
  /// Navegar a una URL y obtener su contenido HTML
  static Future<Map<String, dynamic>> navigateToUrl(String url) async {
    try {
      print('🌐 Navegando a: $url');
      
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Timeout al navegar a $url');
        },
      );

      if (response.statusCode == 200) {
        final html = response.body;
        
        // Extraer título si está disponible
        String title = url;
        final titleMatch = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(html);
        if (titleMatch != null) {
          title = titleMatch.group(1) ?? url;
        }

        // Extraer texto visible (sin tags HTML)
        final textContent = html
            .replaceAll(RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '')
            .replaceAll(RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true), '')
            .replaceAll(RegExp(r'<[^>]+>'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        return {
          'success': true,
          'url': url,
          'title': title,
          'html': html,
          'textContent': textContent.length > 5000 ? textContent.substring(0, 5000) + '...' : textContent,
          'statusCode': response.statusCode,
        };
      } else {
        return {
          'success': false,
          'url': url,
          'error': 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Error al navegar a $url: $e');
      return {
        'success': false,
        'url': url,
        'error': e.toString(),
      };
    }
  }

  /// Descargar un archivo desde una URL
  static Future<Map<String, dynamic>> downloadFile(String url, {String? fileName, String? targetDirectory}) async {
    try {
      print('📥 Descargando archivo desde: $url');
      
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(
        const Duration(minutes: 5), // Timeout más largo para descargas
        onTimeout: () {
          throw Exception('Timeout al descargar $url');
        },
      );

      if (response.statusCode == 200) {
        // Determinar nombre del archivo
        String finalFileName = fileName ?? path.basename(uri.path);
        
        if (finalFileName.isEmpty || !finalFileName.contains('.')) {
          // Intentar obtener del Content-Disposition header
          final contentDisposition = response.headers['content-disposition'];
          if (contentDisposition != null) {
            final filenamePattern = RegExp(r'filename=([^;]+)');
            final filenameMatch = filenamePattern.firstMatch(contentDisposition);
            if (filenameMatch != null) {
              final matchedFileName = filenameMatch.group(1);
              if (matchedFileName != null) {
                finalFileName = matchedFileName.trim().replaceAll('"', '').replaceAll("'", '');
              }
            }
          }
          
          // Si aún no tiene nombre, generar uno
          if (finalFileName.isEmpty || !finalFileName.contains('.')) {
            finalFileName = 'downloaded_file_${DateTime.now().millisecondsSinceEpoch}';
          }
        }

        // Determinar directorio de destino
        Directory targetDir;
        if (targetDirectory != null) {
          targetDir = Directory(targetDirectory);
        } else {
          // Usar el directorio del proyecto actual
          final projectPath = await ProjectService.getProjectPath();
          if (projectPath != null) {
            targetDir = Directory(projectPath);
          } else {
            // Fallback a Downloads
            targetDir = Directory('${Platform.environment['HOME']}/Downloads');
          }
        }

        // Crear directorio si no existe
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        // Guardar archivo
        final filePath = path.join(targetDir.path, finalFileName);
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        print('✅ Archivo descargado: $filePath');

        return {
          'success': true,
          'url': url,
          'filePath': filePath,
          'fileName': finalFileName,
          'size': await file.length(),
        };
      } else {
        return {
          'success': false,
          'url': url,
          'error': 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Error al descargar $url: $e');
      return {
        'success': false,
        'url': url,
        'error': e.toString(),
      };
    }
  }

  /// Extraer enlaces de una página web
  static List<String> extractLinks(String html) {
    final linkPattern = RegExp(r'href="([^"]+)"', caseSensitive: false);
    final linkPattern2 = RegExp(r"href='([^']+)'", caseSensitive: false);
    final matches1 = linkPattern.allMatches(html);
    final matches2 = linkPattern2.allMatches(html);
    final allLinks = <String>[];
    for (var match in matches1) {
      final link = match.group(1);
      if (link != null && link.isNotEmpty) allLinks.add(link);
    }
    for (var match in matches2) {
      final link = match.group(1);
      if (link != null && link.isNotEmpty) allLinks.add(link);
    }
    return allLinks;
  }

  /// Extraer imágenes de una página web
  static List<String> extractImages(String html, String baseUrl) {
    final imagePattern = RegExp(r'<img[^>]+src="([^"]+)"', caseSensitive: false);
    final imagePattern2 = RegExp(r"<img[^>]+src='([^']+)'", caseSensitive: false);
    final matches1 = imagePattern.allMatches(html);
    final matches2 = imagePattern2.allMatches(html);
    final allImages = <String>[];
    
    for (var match in matches1) {
      final src = match.group(1) ?? '';
      if (src.isNotEmpty) {
        if (src.startsWith('http://') || src.startsWith('https://')) {
          allImages.add(src);
        } else if (src.startsWith('/')) {
          final uri = Uri.parse(baseUrl);
          allImages.add('${uri.scheme}://${uri.host}$src');
        } else {
          allImages.add('$baseUrl/$src');
        }
      }
    }
    
    for (var match in matches2) {
      final src = match.group(1) ?? '';
      if (src.isNotEmpty) {
        if (src.startsWith('http://') || src.startsWith('https://')) {
          allImages.add(src);
        } else if (src.startsWith('/')) {
          final uri = Uri.parse(baseUrl);
          allImages.add('${uri.scheme}://${uri.host}$src');
        } else {
          allImages.add('$baseUrl/$src');
        }
      }
    }
    
    return allImages;
  }
}
