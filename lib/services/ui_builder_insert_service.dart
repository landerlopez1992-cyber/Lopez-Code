import 'dart:io';

import 'ui_builder_edit_service.dart';

/// Inserta snippets HTML del UI Builder en un archivo del proyecto.
class UiBuilderInsertService {
  UiBuilderInsertService._();

  /// Elige el mejor archivo HTML destino.
  static Future<String?> resolveTargetHtmlPath({
    required String projectPath,
    String? selectedFilePath,
  }) async {
    final selected = selectedFilePath;
    if (selected != null &&
        selected.toLowerCase().endsWith('.html') &&
        await File(selected).exists()) {
      return selected;
    }

    final candidates = [
      '$projectPath/index.html',
      '$projectPath/login.html',
      '$projectPath/home.html',
    ];
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }

    // Primer .html en la raíz del proyecto.
    try {
      final dir = Directory(projectPath);
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.html')) {
          return entity.path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Inserta [snippet] antes de `</body>` (o al final si no hay body).
  /// Devuelve `(html, blockId)`.
  static Future<({String html, String blockId})> insertSnippet({
    required String filePath,
    required String snippet,
  }) async {
    return insertAtAnchor(
      filePath: filePath,
      snippet: snippet,
    );
  }

  /// Inserta según ancla del drop: parent / before / after / final del body.
  static Future<({String html, String blockId})> insertAtAnchor({
    required String filePath,
    required String snippet,
    String? parentId,
    String? beforeId,
    String? afterId,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Archivo HTML no encontrado', filePath);
    }

    if (parentId != null && parentId.isNotEmpty) {
      final nested = await UiBuilderEditService.insertInsideBlock(
        filePath: filePath,
        parentBlockId: parentId,
        snippet: snippet,
      );
      return (html: nested.html, blockId: nested.newBlockId);
    }

    final original = await file.readAsString();
    final blockId = UiBuilderEditService.newBlockId();
    final stamped = UiBuilderEditService.wrapSnippet(snippet, blockId);

    String next;
    if (beforeId != null && beforeId.isNotEmpty) {
      next = UiBuilderEditService.insertRelativeToBlock(
        html: original,
        targetId: beforeId,
        stampedBlock: stamped,
        before: true,
      );
    } else if (afterId != null && afterId.isNotEmpty) {
      next = UiBuilderEditService.insertRelativeToBlock(
        html: original,
        targetId: afterId,
        stampedBlock: stamped,
        before: false,
      );
    } else {
      final bodyClose = RegExp(r'</body\s*>', caseSensitive: false);
      final match = bodyClose.firstMatch(original);
      if (match != null) {
        next = original.replaceRange(match.start, match.start, stamped);
      } else {
        next = '$original$stamped';
      }
    }

    await file.writeAsString(next);
    return (html: next, blockId: blockId);
  }
}
