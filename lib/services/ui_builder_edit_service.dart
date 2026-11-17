import 'dart:io';

/// Edita / elimina / reordena bloques del UI Builder (marcadores START/END).
class UiBuilderEditService {
  UiBuilderEditService._();

  static final _blockRe = RegExp(
    r'<!--\s*voryxel-ui:START:([a-zA-Z0-9_\-]+)\s*-->'
    r'([\s\S]*?)'
    r'<!--\s*voryxel-ui:END:\1\s*-->',
    multiLine: true,
  );

  static String newBlockId() =>
      'vb_${DateTime.now().millisecondsSinceEpoch}';

  /// Envuelve [snippet] con marcadores y `data-voryxel-id` en la raíz.
  static String wrapSnippet(String snippet, String blockId) {
    final stamped = _ensureVoryxelId(snippet.trim(), blockId);
    return '\n<!-- voryxel-ui:START:$blockId -->\n'
        '$stamped\n'
        '<!-- voryxel-ui:END:$blockId -->\n';
  }

  static String _ensureVoryxelId(String html, String blockId) {
    if (RegExp(r'data-voryxel-id\s*=').hasMatch(html)) {
      return html.replaceFirst(
        RegExp(r'data-voryxel-id\s*=\s*"[^"]*"'),
        'data-voryxel-id="$blockId"',
      );
    }
    return html.replaceFirstMapped(
      RegExp(r'<([a-zA-Z][\w:-]*)(\s|>)'),
      (m) {
        final tag = m.group(1)!;
        final after = m.group(2)!;
        if (after == '>') {
          return '<$tag data-voryxel-id="$blockId">';
        }
        return '<$tag data-voryxel-id="$blockId" ';
      },
    );
  }

  static String? extractBlock(String html, String blockId) {
    for (final m in _blockRe.allMatches(html)) {
      if (m.group(1) == blockId) return m.group(2);
    }
    return null;
  }

  static List<_BlockSpan> _collectBlocks(String html) {
    return _blockRe
        .allMatches(html)
        .map(
          (m) => _BlockSpan(
            id: m.group(1)!,
            start: m.start,
            end: m.end,
            full: m.group(0)!,
            inner: m.group(2) ?? '',
          ),
        )
        .toList();
  }

  static Future<String> deleteBlock({
    required String filePath,
    required String blockId,
  }) async {
    final file = File(filePath);
    final html = await file.readAsString();
    final next = html.replaceAllMapped(_blockRe, (m) {
      if (m.group(1) == blockId) return '';
      return m.group(0)!;
    });
    if (next == html) {
      throw StateError('No se encontró el bloque $blockId');
    }
    await file.writeAsString(next);
    return next;
  }

  /// Duplica el bloque justo debajo del original. Devuelve el nuevo id.
  static Future<({String html, String newBlockId})> duplicateBlock({
    required String filePath,
    required String blockId,
  }) async {
    final file = File(filePath);
    final html = await file.readAsString();
    final blocks = _collectBlocks(html);
    final index = blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) {
      throw StateError('No se encontró el bloque $blockId');
    }

    final source = blocks[index];
    final newId = newBlockId();
    final duplicatedInner = _ensureVoryxelId(source.inner.trim(), newId);
    final duplicatedFull = '\n<!-- voryxel-ui:START:$newId -->\n'
        '$duplicatedInner\n'
        '<!-- voryxel-ui:END:$newId -->\n';

    final next = html.replaceRange(
      source.end,
      source.end,
      duplicatedFull,
    );
    await file.writeAsString(next);
    return (html: next, newBlockId: newId);
  }

  /// Inserta un bloque ya envuelto antes (`before=true`) o después de [targetId].
  static String insertRelativeToBlock({
    required String html,
    required String targetId,
    required String stampedBlock,
    required bool before,
  }) {
    final blocks = _collectBlocks(html);
    final index = blocks.indexWhere((b) => b.id == targetId);
    if (index < 0) {
      final bodyClose = RegExp(r'</body\s*>', caseSensitive: false);
      final match = bodyClose.firstMatch(html);
      if (match != null) {
        return html.replaceRange(match.start, match.start, stampedBlock);
      }
      return '$html$stampedBlock';
    }
    final target = blocks[index];
    if (before) {
      return html.replaceRange(target.start, target.start, stampedBlock);
    }
    return html.replaceRange(target.end, target.end, stampedBlock);
  }

  /// Inserta un snippet NUEVO dentro de un bloque contenedor (antes de su cierre).
  static Future<({String html, String newBlockId})> insertInsideBlock({
    required String filePath,
    required String parentBlockId,
    required String snippet,
  }) async {
    final file = File(filePath);
    final html = await file.readAsString();
    final newId = newBlockId();
    final child = wrapSnippet(snippet, newId).trim();
    var found = false;

    final next = html.replaceAllMapped(_blockRe, (m) {
      if (m.group(1) != parentBlockId) return m.group(0)!;
      found = true;
      var inner = (m.group(2) ?? '').trimRight();
      // Quitar placeholders vacíos al anidar el primer hijo.
      inner = _stripPlaceholders(inner);
      // Insertar antes del cierre del contenedor raíz si es posible.
      inner = _insertBeforeRootClose(inner, '\n$child\n');
      return '<!-- voryxel-ui:START:$parentBlockId -->\n'
          '$inner\n'
          '<!-- voryxel-ui:END:$parentBlockId -->';
    });

    if (!found) {
      throw StateError('No se encontró el contenedor $parentBlockId');
    }
    await file.writeAsString(next);
    return (html: next, newBlockId: newId);
  }

  /// Elimina placeholders de contenedores vacíos (texto "Container", etc.).
  static String _stripPlaceholders(String html) {
    var out = html;
    // Marcados explícitos.
    out = out.replaceAll(
      RegExp(
        r'<[^>]*data-voryxel-placeholder\s*=\s*"1"[^>]*>[\s\S]*?</[^>]+>',
        caseSensitive: false,
      ),
      '',
    );
    out = out.replaceAll(
      RegExp(
        r'<[^>]*data-voryxel-placeholder\s*=\s*"1"[^>]*/\s*>',
        caseSensitive: false,
      ),
      '',
    );
    // Texto suelto típico dentro del root (sin otros bloques voryxel).
    if (!out.contains('voryxel-ui:START:') &&
        !RegExp(r'data-voryxel-id\s*=', caseSensitive: false).hasMatch(out)) {
      out = out.replaceAllMapped(
        RegExp(
          r'(<(div|section|ul|details)([^>]*data-voryxel[^>]*)>)([\s\S]*?)(</\2>)',
          caseSensitive: false,
        ),
        (m) {
          final open = m.group(1)!;
          final close = m.group(5)!;
          var body = m.group(4) ?? '';
          body = body.replaceAll(
            RegExp(
              r'<(p|span)[^>]*>\s*(Container|Column|Row|Wrap|Card|'
              r'Column — suelta elementos aquí|Row — suelta aquí|'
              r'Suelta elementos aquí)\s*</\1>',
              caseSensitive: false,
            ),
            '',
          );
          // Solo texto "Container" directo en el nodo.
          if (RegExp(
            r'^\s*(Container|Column|Row|Wrap)\s*$',
            caseSensitive: false,
          ).hasMatch(body)) {
            body = '';
          }
          return '$open$body$close';
        },
      );
    }
    return out;
  }

  /// Mueve el bloque una posición hacia arriba (`-1`) o abajo (`+1`).
  static Future<String> moveBlock({
    required String filePath,
    required String blockId,
    required int direction,
  }) async {
    if (direction != -1 && direction != 1) {
      throw ArgumentError('direction debe ser -1 o 1');
    }

    final file = File(filePath);
    final html = await file.readAsString();
    final blocks = _collectBlocks(html);
    final index = blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) {
      throw StateError('No se encontró el bloque $blockId');
    }

    final swapWith = index + direction;
    if (swapWith < 0 || swapWith >= blocks.length) {
      // Ya está en el extremo: no-op (devolver igual).
      return html;
    }

    final a = blocks[index];
    final b = blocks[swapWith];
    // Reconstruir: intercambiar los dos spans en el documento.
    // Ordenar por posición para editar de atrás hacia adelante.
    final first = a.start < b.start ? a : b;
    final second = a.start < b.start ? b : a;
    final firstIsA = identical(first, a);

    final swappedFirst = firstIsA ? b.full : a.full;
    final swappedSecond = firstIsA ? a.full : b.full;

    var next = html;
    next = next.replaceRange(second.start, second.end, swappedSecond);
    next = next.replaceRange(first.start, first.end, swappedFirst);

    await file.writeAsString(next);
    return next;
  }

  /// Actualiza texto, attrs (href/src) y estilos inline del bloque.
  static Future<String> updateBlock({
    required String filePath,
    required String blockId,
    String? text,
    String? color,
    String? backgroundColor,
    String? padding,
    String? margin,
    String? width,
    String? height,
    String? fontSize,
    String? borderRadius,
    String? border,
    String? opacity,
    String? textAlign,
    String? href,
    String? src,
    String? placeholder,
    String? left,
    String? top,
    bool? absolute,
  }) async {
    final file = File(filePath);
    final html = await file.readAsString();
    var found = false;

    final hasStyle = color != null ||
        backgroundColor != null ||
        padding != null ||
        margin != null ||
        width != null ||
        height != null ||
        fontSize != null ||
        borderRadius != null ||
        border != null ||
        opacity != null ||
        textAlign != null ||
        left != null ||
        top != null ||
        absolute == true;

    final next = html.replaceAllMapped(_blockRe, (m) {
      if (m.group(1) != blockId) return m.group(0)!;
      found = true;
      var inner = m.group(2) ?? '';
      if (text != null) {
        inner = _replacePrimaryText(inner, text);
      }
      if (src != null) {
        inner = _setAttr(inner, 'src', src);
      }
      if (href != null) {
        // Imagen: envolver en <a> para navegar; botón/enlace: href directo.
        if (RegExp(r'<img\b', caseSensitive: false).hasMatch(inner) &&
            !RegExp(r'<a\b', caseSensitive: false).hasMatch(inner)) {
          inner = _wrapImageWithLink(inner, href);
        } else {
          inner = _setAttr(inner, 'href', href);
        }
      }
      if (placeholder != null) {
        inner = _setAttr(inner, 'placeholder', placeholder);
      }
      if (hasStyle) {
        inner = _patchRootStyle(
          inner,
          color: color,
          backgroundColor: backgroundColor,
          padding: padding,
          margin: margin,
          width: width,
          height: height,
          fontSize: fontSize,
          borderRadius: borderRadius,
          border: border,
          opacity: opacity,
          textAlign: textAlign,
          left: left,
          top: top,
          absolute: absolute,
        );
      }
      return '<!-- voryxel-ui:START:$blockId -->\n'
          '${inner.trim()}\n'
          '<!-- voryxel-ui:END:$blockId -->';
    });

    if (!found) {
      throw StateError('No se encontró el bloque $blockId');
    }
    await file.writeAsString(next);
    return next;
  }

  static String _setAttr(String html, String name, String value) {
    final escaped = value.replaceAll('"', '&quot;');
    final re = RegExp(
      '$name\\s*=\\s*"[^"]*"',
      caseSensitive: false,
    );
    if (re.hasMatch(html)) {
      return html.replaceFirst(re, '$name="$escaped"');
    }
    // Añadir en la primera etiqueta que lo soporte (a/img/input/button/video).
    return html.replaceFirstMapped(
      RegExp(r'<(a|img|input|video|button|source)(\s|>)', caseSensitive: false),
      (m) {
        final tag = m.group(1)!;
        final after = m.group(2)!;
        if (after == '>') return '<$tag $name="$escaped">';
        return '<$tag $name="$escaped" ';
      },
    );
  }

  /// Envuelve un `<img>` suelto en `<a href="...">` para navegación.
  static String _wrapImageWithLink(String html, String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return html;
    final escaped = trimmed.replaceAll('"', '&quot;');
    // Guardar también en data-href del img (el Inspector selecciona el img).
    var withData = _setAttr(html, 'data-href', trimmed);
    final imgRe = RegExp(r'<img\b[^>]*?/?>', caseSensitive: false);
    final m = imgRe.firstMatch(withData);
    if (m == null) return withData;
    final img = m.group(0)!;
    return withData.replaceFirst(
      img,
      '<a href="$escaped" style="display:inline-block;cursor:pointer;text-decoration:none;border:0;">$img</a>',
    );
  }

  /// Inserta [chunk] justo antes de la etiqueta de cierre del elemento raíz.
  static String _insertBeforeRootClose(String html, String chunk) {
    final open = RegExp(r'<([a-zA-Z][\w:-]*)([^>]*)>').firstMatch(html);
    if (open == null) return '$html$chunk';
    final tag = open.group(1)!;
    // Void tags: append.
    const voids = {
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
    if (voids.contains(tag.toLowerCase())) {
      return '$html$chunk';
    }
    final close = RegExp(
      '</$tag\\s*>',
      caseSensitive: false,
    ).firstMatch(html);
    if (close == null) return '$html$chunk';
    return html.replaceRange(close.start, close.start, chunk);
  }

  static String _replacePrimaryText(String html, String newText) {
    final escaped = _escapeHtml(newText);
    final textTag = RegExp(
      r'(<(button|a|h[1-6]|p|span|li|strong|label)([^>]*)>)([^<]*)(</\2>)',
      caseSensitive: false,
    );
    if (textTag.hasMatch(html)) {
      return html.replaceFirstMapped(textTag, (m) {
        return '${m.group(1)}$escaped${m.group(5)}';
      });
    }
    if (RegExp(r'<input\b', caseSensitive: false).hasMatch(html)) {
      if (RegExp(r'placeholder\s*=', caseSensitive: false).hasMatch(html)) {
        return html.replaceFirst(
          RegExp(r'placeholder\s*=\s*"[^"]*"', caseSensitive: false),
          'placeholder="$escaped"',
        );
      }
    }
    return html;
  }

  static String _patchRootStyle(
    String html, {
    String? color,
    String? backgroundColor,
    String? padding,
    String? margin,
    String? width,
    String? height,
    String? fontSize,
    String? borderRadius,
    String? border,
    String? opacity,
    String? textAlign,
    String? left,
    String? top,
    bool? absolute,
  }) {
    final openTag = RegExp(r'<([a-zA-Z][\w:-]*)([^>]*)>');
    final m = openTag.firstMatch(html);
    if (m == null) return html;

    final tag = m.group(1)!;
    var attrs = m.group(2) ?? '';
    final styleMatch = RegExp(
      r'style\s*=\s*"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(attrs);

    var style = styleMatch?.group(1) ?? '';
    style = _setCss(style, 'color', color);
    style = _setCss(style, 'background', backgroundColor);
    if (backgroundColor != null) {
      style = _setCss(style, 'background-color', backgroundColor);
    }
    style = _setCss(style, 'padding', padding);
    style = _setCss(style, 'margin', margin);
    style = _setCss(style, 'width', width);
    style = _setCss(style, 'height', height);
    style = _setCss(style, 'font-size', fontSize);
    style = _setCss(style, 'border-radius', borderRadius);
    style = _setCss(style, 'border', border);
    style = _setCss(style, 'opacity', opacity);
    style = _setCss(style, 'text-align', textAlign);
    if (absolute == true) {
      style = _setCss(style, 'position', 'absolute');
      style = _setCss(style, 'z-index', '30');
    }
    style = _setCss(style, 'left', left);
    style = _setCss(style, 'top', top);

    if (styleMatch != null) {
      attrs = attrs.replaceFirst(
        RegExp(r'style\s*=\s*"[^"]*"', caseSensitive: false),
        'style="$style"',
      );
    } else {
      attrs = '$attrs style="$style"';
    }

    final newOpen = '<$tag$attrs>';
    return html.replaceRange(m.start, m.end, newOpen);
  }

  static String _setCss(String style, String prop, String? value) {
    if (value == null) return style;
    final re = RegExp(
      '${RegExp.escape(prop)}\\s*:\\s*[^;]*;?',
      caseSensitive: false,
    );
    final cleaned = style.replaceAll(re, '').trim();
    final base = cleaned.isEmpty
        ? ''
        : (cleaned.endsWith(';') ? cleaned : '$cleaned;');
    return '$base$prop:$value;';
  }

  static String _escapeHtml(String raw) {
    return raw
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}

class _BlockSpan {
  final String id;
  final int start;
  final int end;
  final String full;
  final String inner;

  const _BlockSpan({
    required this.id,
    required this.start,
    required this.end,
    required this.full,
    required this.inner,
  });
}
