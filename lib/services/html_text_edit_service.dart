import 'dart:io';

import 'ui_builder_edit_service.dart';

/// Edita texto en HTML del proyecto (bloques UI Builder o texto genérico).
class HtmlTextEditService {
  HtmlTextEditService._();

  static Future<String> applyText({
    required String filePath,
    required String newText,
    String? blockId,
    String? oldText,
    String? tagName,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('HTML no encontrado', filePath);
    }

    var html = await file.readAsString();
    // Reparar corrupción típica de replace con `$1$2` literales.
    html = _repairDollarGroupCorruption(html);

    // Solo bloques UI Builder reales (marcadores en el archivo).
    // Ignorar ids efímeros vb_… inventados solo en el DOM del Preview.
    if (blockId != null &&
        blockId.isNotEmpty &&
        UiBuilderEditService.extractBlock(html, blockId) != null) {
      return UiBuilderEditService.updateBlock(
        filePath: filePath,
        blockId: blockId,
        text: newText,
      );
    }

    final old = (oldText ?? '').trim();
    final next = newText; // no trim agresivo mientras escribe
    final oldCmp = old;
    final nextCmp = next.trim();
    if (oldCmp.isEmpty && nextCmp.isEmpty) return html;
    if (oldCmp == nextCmp) return html;

    final escapedOld = _escapeHtml(oldCmp);
    final escapedNew = _escapeHtml(nextCmp);
    final tag = (tagName ?? '').trim().toLowerCase();

    var replaced = false;

    // Preferir reemplazo dentro de la etiqueta (sin `$1`/`$2` en el String).
    if (tag.isNotEmpty && RegExp(r'^[a-z][a-z0-9]*$').hasMatch(tag)) {
      final tagged = RegExp(
        '(<$tag\\b[^>]*>)(\\s*)${RegExp.escape(escapedOld)}(\\s*)(</$tag\\s*>)',
        caseSensitive: false,
      );
      if (tagged.hasMatch(html)) {
        html = html.replaceFirstMapped(tagged, (m) {
          return '${m.group(1)}${m.group(2)}$escapedNew${m.group(3)}${m.group(4)}';
        });
        replaced = true;
      } else {
        // También probar texto crudo (sin escape HTML) dentro del tag.
        final taggedRaw = RegExp(
          '(<$tag\\b[^>]*>)(\\s*)${RegExp.escape(oldCmp)}(\\s*)(</$tag\\s*>)',
          caseSensitive: false,
        );
        if (taggedRaw.hasMatch(html)) {
          html = html.replaceFirstMapped(taggedRaw, (m) {
            return '${m.group(1)}${m.group(2)}$nextCmp${m.group(3)}${m.group(4)}';
          });
          replaced = true;
        }
      }
    }

    if (!replaced) {
      if (html.contains(escapedOld)) {
        html = html.replaceFirst(escapedOld, escapedNew);
        replaced = true;
      } else if (html.contains(oldCmp)) {
        html = html.replaceFirst(oldCmp, nextCmp);
        replaced = true;
      }
    }

    if (!replaced) {
      throw StateError('No se encontró el texto en el HTML');
    }

    await file.writeAsString(html);
    return html;
  }

  /// Quita basura `$1…$2` insertada por un replace defectuoso.
  static String _repairDollarGroupCorruption(String html) {
    if (!html.contains(r'$1') && !html.contains(r'$2')) return html;
    // `$1texto$2` → `texto`
    var out = html.replaceAllMapped(
      RegExp(r'\$1([\s\S]*?)\$2'),
      (m) => m.group(1) ?? '',
    );
    // Restos sueltos
    out = out.replaceAll(r'$1', '').replaceAll(r'$2', '');
    return out;
  }

  static String _escapeHtml(String raw) {
    return raw
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}
