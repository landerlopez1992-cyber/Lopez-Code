import '../models/ui_builder_component.dart';

/// Reglas de diseño estilo FlutterFlow: qué puede contener qué.
class UiBuilderDesignRules {
  UiBuilderDesignRules._();

  /// Contenedores: aceptan hijos.
  static const Set<String> containers = {
    'container',
    'column',
    'row',
    'stack',
    'card',
    'wrap',
    'form',
    'hero',
    'listview',
    'gridview',
    'expandable',
    'tabbar',
    'pageview',
    'carousel',
    'drawer',
    'navbar', // solo hijos de nav/links en la práctica
  };

  /// Hojas: deben ir DENTRO de un contenedor (no sueltas en el body).
  static const Set<String> leaves = {
    'text',
    'base_text',
    'richtext',
    'heading',
    'image',
    'base_image',
    'circle_image',
    'button',
    'base_button',
    'icon_button',
    'icon',
    'link',
    'badge',
    'chip',
    'divider',
    'vertical_divider',
    'spacer',
    'list',
    'list_tile',
    'input',
    'textarea',
    'checkbox',
    'switch',
    'dropdown',
    'radio',
    'slider',
    'date_picker',
    'video',
    'youtube',
    'audio',
    'webview',
    'map',
    'lottie_placeholder',
    'pdf',
    'fab',
  };

  /// Pueden ir en la raíz de la página (body).
  static const Set<String> roots = {
    'container',
    'column',
    'row',
    'stack',
    'card',
    'wrap',
    'form',
    'hero',
    'listview',
    'gridview',
    'expandable',
    'tabbar',
    'pageview',
    'carousel',
    'navbar',
    'bottom_nav',
    'drawer',
    'footer',
    'layout_container',
    'layout_row',
    'layout_column',
  };

  /// data-voryxel kind desde el componente del catálogo.
  static String kindOf(UiBuilderComponent c) {
    final m = RegExp(
      r'data-voryxel\s*=\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(c.htmlSnippet);
    if (m != null) return m.group(1)!.toLowerCase();
    // Fallback por id.
    final id = c.id.toLowerCase();
    if (id.startsWith('layout_')) return id.substring(7);
    if (id.startsWith('base_')) return id == 'base_text' ? 'text' : id.substring(5);
    return id;
  }

  static bool acceptsChildren(String kind) =>
      containers.contains(kind.toLowerCase());

  static bool requiresParent(String kind) {
    final k = kind.toLowerCase();
    if (roots.contains(k)) return false;
    return leaves.contains(k) || !acceptsChildren(k);
  }

  static bool canBeRoot(String kind) {
    final k = kind.toLowerCase();
    if (requiresParent(k)) return false;
    return roots.contains(k) || acceptsChildren(k);
  }

  /// ¿Se puede soltar [childKind] dentro de [parentKind]?
  /// [parentKind] null = raíz de la página.
  static bool canDrop({
    required String childKind,
    String? parentKind,
  }) {
    final child = childKind.toLowerCase();
    if (parentKind == null || parentKind.isEmpty) {
      return canBeRoot(child);
    }
    final parent = parentKind.toLowerCase();
    if (!acceptsChildren(parent)) return false;

    // Reglas especiales FlutterFlow-like.
    switch (parent) {
      case 'navbar':
      case 'bottom_nav':
        return child == 'link' ||
            child == 'button' ||
            child == 'text' ||
            child == 'icon' ||
            child == 'image';
      case 'form':
        return child == 'input' ||
            child == 'textarea' ||
            child == 'checkbox' ||
            child == 'switch' ||
            child == 'dropdown' ||
            child == 'radio' ||
            child == 'slider' ||
            child == 'date_picker' ||
            child == 'button' ||
            child == 'text' ||
            child == 'heading' ||
            child == 'container' ||
            child == 'column' ||
            child == 'row';
      case 'listview':
        return child == 'list_tile' ||
            child == 'text' ||
            child == 'image' ||
            child == 'card' ||
            child == 'container' ||
            child == 'row';
      case 'carousel':
      case 'pageview':
        return child == 'image' ||
            child == 'card' ||
            child == 'container' ||
            child == 'hero' ||
            child == 'text';
      default:
        // Column/Row/Stack/Container/Card/Wrap/Grid/Hero: casi todo.
        return true;
    }
  }

  static String rejectMessage({
    required String childKind,
    String? parentKind,
  }) {
    final child = childKind.toLowerCase();
    if (parentKind == null || parentKind.isEmpty) {
      if (requiresParent(child)) {
        return '「$child」debe ir dentro de Container, Column, Row o Card';
      }
      return 'No se puede soltar aquí';
    }
    return '「$child」no puede ir dentro de 「$parentKind」';
  }

  /// Ajusta el snippet hijo para que encaje en el padre (width 100%, etc.).
  static String prepareChildSnippet({
    required String snippet,
    required String childKind,
    required String parentKind,
  }) {
    var html = snippet.trim();
    final parent = parentKind.toLowerCase();
    final child = childKind.toLowerCase();

    // Quitar absolute residual.
    html = html.replaceAllMapped(
      RegExp(r'style\s*=\s*"([^"]*)"', caseSensitive: false),
      (m) {
        var s = m.group(1) ?? '';
        s = s.replaceAll(RegExp(r'position\s*:\s*absolute\s*;?', caseSensitive: false), '');
        s = s.replaceAll(RegExp(r'left\s*:\s*[^;]+;?', caseSensitive: false), '');
        s = s.replaceAll(RegExp(r'top\s*:\s*[^;]+;?', caseSensitive: false), '');
        s = s.replaceAll(RegExp(r'z-index\s*:\s*[^;]+;?', caseSensitive: false), '');
        return 'style="$s"';
      },
    );

    if (child == 'image' || child == 'circle_image') {
      html = _mergeStyle(
        html,
        parent == 'row'
            ? 'max-width:160px;height:auto;margin:0;display:block;border-radius:8px;'
            : 'width:100%;max-width:100%;height:auto;margin:0;display:block;border-radius:8px;',
      );
    }
    if (child == 'button' || child == 'base_button') {
      html = _mergeStyle(
        html,
        parent == 'row'
            ? 'margin:0;align-self:center;'
            : 'margin:8px 0;display:inline-block;',
      );
    }
    if (child == 'text' || child == 'heading' || child == 'richtext') {
      html = _mergeStyle(html, 'margin:0;');
    }
    if (child == 'spacer' && parent == 'row') {
      html = html.replaceFirst(
        RegExp(r'height:\s*\d+px'),
        'width:24px;height:1px;flex:1',
      );
    }
    return html;
  }

  static String _mergeStyle(String html, String extra) {
    final styleRe = RegExp(r'style\s*=\s*"([^"]*)"', caseSensitive: false);
    if (styleRe.hasMatch(html)) {
      return html.replaceFirstMapped(styleRe, (m) {
        final s = (m.group(1) ?? '').trim();
        final sep = s.isEmpty || s.endsWith(';') ? '' : ';';
        return 'style="$s$sep$extra"';
      });
    }
    return html.replaceFirstMapped(
      RegExp(r'<([a-zA-Z][\w:-]*)(\s|/?>)'),
      (m) {
        final tag = m.group(1)!;
        final after = m.group(2)!;
        if (after.startsWith('/') || after == '>') {
          return '<$tag style="$extra"$after';
        }
        return '<$tag style="$extra" ';
      },
    );
  }

  /// Kinds de contenedor para el resolver JS.
  static List<String> get containerKindsForJs => containers.toList()..sort();
}
