import 'dart:io';

import 'ui_builder_edit_service.dart';

/// Persiste en el HTML del proyecto cambios del panel «Editar elemento»
/// (texto, estilos, src, href) aunque el nodo no tenga `data-voryxel-id`.
class HtmlElementPatchService {
  HtmlElementPatchService._();

  static Future<String> apply({
    required String filePath,
    String? blockId,
    String? tagName,
    String? elementId,
    String? className,
    String? oldText,
    String? newText,
    String? oldSrc,
    String? src,
    String? href,
    String? width,
    String? height,
    String? color,
    String? backgroundColor,
    String? fontSize,
    String? borderRadius,
    String? opacity,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('HTML no encontrado', filePath);
    }

    var html = await file.readAsString();
    html = _repairDollarGroupCorruption(html);

    // Solo usar bloques UI Builder si REALMENTE existen en el archivo.
    // El Preview a veces inventa data-voryxel-id (vb_…) solo en el DOM;
    // eso no debe romper el guardado ni forzar errores en cada slider.
    if (blockId != null &&
        blockId.isNotEmpty &&
        UiBuilderEditService.extractBlock(html, blockId) != null) {
      return UiBuilderEditService.updateBlock(
        filePath: filePath,
        blockId: blockId,
        text: newText,
        color: color,
        backgroundColor: backgroundColor,
        width: width,
        height: height,
        fontSize: fontSize,
        borderRadius: borderRadius,
        opacity: opacity,
        href: href,
        src: src,
      );
    }

    final tag = (tagName ?? '').trim().toLowerCase();
    if (tag.isEmpty || !RegExp(r'^[a-z][a-z0-9]*$').hasMatch(tag)) {
      throw StateError('Etiqueta HTML inválida para guardar');
    }

    final match = _findElement(
      html: html,
      tag: tag,
      elementId: elementId,
      className: className,
      oldText: oldText,
      oldSrc: oldSrc,
    );
    if (match == null) {
      throw StateError(
        'No se encontró el elemento <$tag> en el archivo para guardar',
      );
    }

    var openTag = match.openTag;
    var inner = match.inner;
    final isVoid = _voidTags.contains(tag);

    // Atributos src / href
    if (src != null && src.trim().isNotEmpty) {
      openTag = _setAttr(openTag, 'src', src.trim());
    }
    if (href != null && href.trim().isNotEmpty) {
      openTag = _setAttr(openTag, 'href', href.trim());
    }

    // Estilos inline
    openTag = _patchStyle(
      openTag,
      width: width,
      height: height,
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      borderRadius: borderRadius,
      opacity: opacity,
    );

    // Texto (no void)
    if (!isVoid && newText != null) {
      final nextText = _escapeHtml(newText.trim());
      // Si el inner solo era texto (sin hijos), reemplazar entero.
      if (!RegExp(r'<[a-zA-Z]').hasMatch(inner)) {
        inner = nextText;
      } else {
        // Reemplazar primer nodo de texto significativo.
        final textOnly = RegExp(
          r'^(\s*)([^<]+)',
        ).firstMatch(inner);
        if (textOnly != null && (textOnly.group(2) ?? '').trim().isNotEmpty) {
          inner = inner.replaceFirst(
            textOnly.group(0)!,
            '${textOnly.group(1)}$nextText',
          );
        } else {
          // Prefijar texto si no había.
          inner = '$nextText$inner';
        }
      }
    }

    final rebuilt = isVoid
        ? openTag
        : '$openTag$inner</$tag>';

    html = html.replaceRange(match.start, match.end, rebuilt);
    await file.writeAsString(html);
    return html;
  }

  static const _voidTags = {
    'img',
    'hr',
    'br',
    'input',
    'meta',
    'link',
    'source',
    'area',
    'col',
    'embed',
    'wbr',
  };

  static _ElementMatch? _findElement({
    required String html,
    required String tag,
    String? elementId,
    String? className,
    String? oldText,
    String? oldSrc,
  }) {
    final openRe = RegExp(
      '<$tag\\b([^>]*)>',
      caseSensitive: false,
    );

    for (final m in openRe.allMatches(html)) {
      final attrs = m.group(1) ?? '';
      final openTag = m.group(0)!;
      final openEnd = m.end;

      if (elementId != null && elementId.isNotEmpty) {
        final idAttr = RegExp(
          r'\bid\s*=\s*"([^"]*)"',
          caseSensitive: false,
        ).firstMatch(attrs);
        if (idAttr == null || idAttr.group(1) != elementId) continue;
      }

      if (className != null && className.trim().isNotEmpty) {
        final classAttr = RegExp(
          r'\bclass\s*=\s*"([^"]*)"',
          caseSensitive: false,
        ).firstMatch(attrs);
        final classes = (classAttr?.group(1) ?? '').split(RegExp(r'\s+'));
        final needed = className.trim().split(RegExp(r'\s+'));
        // Al menos 1 clase en común (Tailwind cambia, pero suele compartir).
        final overlap = needed.where(classes.contains).length;
        if (overlap == 0 && needed.length > 1) {
          // Si hay muchas clases, exigir al menos 2 coincidencias.
          continue;
        }
        if (overlap == 0) continue;
      }

      if (_voidTags.contains(tag)) {
        if (oldSrc != null && oldSrc.isNotEmpty) {
          final srcAttr = RegExp(
            r'\bsrc\s*=\s*"([^"]*)"',
            caseSensitive: false,
          ).firstMatch(attrs);
          if (srcAttr?.group(1) != oldSrc) continue;
        }
        // Self-closing or trailing
        var end = openEnd;
        if (openTag.endsWith('/>')) {
          end = m.end;
        }
        return _ElementMatch(
          start: m.start,
          end: end,
          openTag: openTag.endsWith('/>')
              ? openTag
              : (html.substring(m.start, openEnd).endsWith('>')
                  ? openTag.replaceFirst(RegExp(r'>$'), ' />')
                  : openTag),
          inner: '',
        );
      }

      // Buscar cierre de la etiqueta (simple, no anidado del mismo tag).
      final closeRe = RegExp('</$tag\\s*>', caseSensitive: false);
      final close = closeRe.firstMatch(html.substring(openEnd));
      if (close == null) continue;
      final inner = html.substring(openEnd, openEnd + close.start);
      final end = openEnd + close.end;

      if (oldText != null && oldText.trim().isNotEmpty) {
        final plain = inner.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(
              RegExp(r'\s+'),
              ' ',
            ).trim();
        final want = oldText.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (!plain.contains(want) && plain != want) {
          // También aceptar si el texto está truncado en el inspector.
          final short = want.length > 40 ? want.substring(0, 40) : want;
          if (!plain.contains(short)) continue;
        }
      }

      return _ElementMatch(
        start: m.start,
        end: end,
        openTag: openTag,
        inner: inner,
      );
    }

    // Fallback: solo tag + texto, sin class.
    if (className != null && className.isNotEmpty) {
      return _findElement(
        html: html,
        tag: tag,
        elementId: elementId,
        className: null,
        oldText: oldText,
        oldSrc: oldSrc,
      );
    }
    return null;
  }

  static String _setAttr(String openTag, String name, String value) {
    final escaped = value.replaceAll('"', '&quot;');
    final re = RegExp('$name\\s*=\\s*"[^"]*"', caseSensitive: false);
    if (re.hasMatch(openTag)) {
      return openTag.replaceFirst(re, '$name="$escaped"');
    }
    return openTag.replaceFirstMapped(RegExp(r'(\s*)(/?>)$'), (m) {
      return ' $name="$escaped"${m.group(1)}${m.group(2)}';
    });
  }

  static String _patchStyle(
    String openTag, {
    String? width,
    String? height,
    String? color,
    String? backgroundColor,
    String? fontSize,
    String? borderRadius,
    String? opacity,
  }) {
    final styleRe = RegExp(r'style\s*=\s*"([^"]*)"', caseSensitive: false);
    var style = styleRe.firstMatch(openTag)?.group(1) ?? '';
    style = _setCss(style, 'width', width);
    style = _setCss(style, 'height', height);
    style = _setCss(style, 'color', color);
    style = _setCss(style, 'background', backgroundColor);
    if (backgroundColor != null) {
      style = _setCss(style, 'background-color', backgroundColor);
    }
    style = _setCss(style, 'font-size', fontSize);
    style = _setCss(style, 'border-radius', borderRadius);
    style = _setCss(style, 'opacity', opacity);

    if (styleRe.hasMatch(openTag)) {
      return openTag.replaceFirst(styleRe, 'style="$style"');
    }
    return openTag.replaceFirstMapped(RegExp(r'(\s*)(/?>)$'), (m) {
      return ' style="$style"${m.group(1)}${m.group(2)}';
    });
  }

  static String _setCss(String style, String prop, String? value) {
    if (value == null || value.trim().isEmpty) return style;
    final re = RegExp(
      '${RegExp.escape(prop)}\\s*:\\s*[^;]*;?',
      caseSensitive: false,
    );
    final cleaned = style.replaceAll(re, '').trim();
    final base = cleaned.isEmpty
        ? ''
        : (cleaned.endsWith(';') ? cleaned : '$cleaned;');
    return '$base$prop:${value.trim()};';
  }

  static String _repairDollarGroupCorruption(String html) {
    if (!html.contains(r'$1') && !html.contains(r'$2')) return html;
    var out = html.replaceAllMapped(
      RegExp(r'\$1([\s\S]*?)\$2'),
      (m) => m.group(1) ?? '',
    );
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

class _ElementMatch {
  final int start;
  final int end;
  final String openTag;
  final String inner;

  const _ElementMatch({
    required this.start,
    required this.end,
    required this.openTag,
    required this.inner,
  });
}
