import 'package:flutter/foundation.dart';

import '../models/inspector_element.dart';

/// Selección del Inspector en Preview (hover + click + pila de capas).
/// El agente la lee vía `<workspace_state>` / `inspector_selection`.
class InspectorSelectionService extends ChangeNotifier {
  static final InspectorSelectionService _instance =
      InspectorSelectionService._();
  factory InspectorSelectionService() => _instance;
  InspectorSelectionService._();

  bool _active = false;
  InspectorElement? _hovered;
  InspectorElement? _selected;
  List<InspectorElement> _layers = const [];

  bool get isActive => _active;
  InspectorElement? get hovered => _hovered;
  InspectorElement? get selected => _selected;

  /// Capas bajo el cursor (de más interna a más externa).
  List<InspectorElement> get layers => _layers;

  /// Elemento que el usuario está señalando (selección > hover).
  InspectorElement? get focus => _selected ?? _hovered;

  bool get hasSelection => _selected != null;

  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (!value) {
      _hovered = null;
      _selected = null;
      _layers = const [];
    }
    notifyListeners();
  }

  void setHovered(
    InspectorElement? element, {
    List<InspectorElement> layers = const [],
  }) {
    if (!_active) return;
    final same = _sameElement(_hovered, element) && _sameLayers(_layers, layers);
    if (same) return;
    _hovered = element;
    if (layers.isNotEmpty) {
      _layers = List.unmodifiable(layers);
    }
    notifyListeners();
  }

  void setSelected(
    InspectorElement? element, {
    List<InspectorElement> layers = const [],
  }) {
    if (!_active && element != null) {
      _active = true;
    }
    _selected = element;
    if (element != null) {
      _hovered = element;
    }
    if (layers.isNotEmpty) {
      _layers = List.unmodifiable(layers);
    }
    notifyListeners();
  }

  /// Elige una capa de la pila (desde el panel) y la fija como selección.
  void selectLayer(InspectorElement element) {
    if (!_active) _active = true;
    _selected = element;
    _hovered = element;
    notifyListeners();
  }

  void clearSelection() {
    if (_selected == null && _hovered == null && _layers.isEmpty) return;
    _selected = null;
    _hovered = null;
    _layers = const [];
    notifyListeners();
  }

  void clear() {
    _active = false;
    _hovered = null;
    _selected = null;
    _layers = const [];
    notifyListeners();
  }

  /// Bloque compacto para el agente.
  String toWorkspaceBlock() {
    final el = _selected ?? _hovered;
    if (!_active || el == null) {
      return 'inspector: inactive';
    }
    final kind = _selected != null ? 'selected' : 'hovered';
    final buf = StringBuffer();
    buf.writeln('<inspector_selection kind="$kind">');
    buf.writeln('tag: ${el.tagName}');
    if (el.id != null && el.id!.isNotEmpty) buf.writeln('id: ${el.id}');
    if (el.className != null && el.className!.isNotEmpty) {
      buf.writeln('class: ${el.className}');
    }
    buf.writeln('selector: ${el.fullSelector}');
    if (el.textContent != null && el.textContent!.trim().isNotEmpty) {
      final t = el.textContent!.trim();
      buf.writeln(
        'text: ${t.length > 120 ? '${t.substring(0, 120)}…' : t}',
      );
    }
    // Pista explícita para HTML/CSS (Tailwind, etc.).
    if (el.className != null && el.className!.isNotEmpty) {
      buf.writeln(
        'html_hint: Busca en .html/.css/.jsx este tag+class/texto '
        'y edita ESE nodo (ej. bg-pink-600 → bg-green-600).',
      );
    }
    final r = el.boundingRect;
    if (r != null) {
      buf.writeln(
        'bounds: ${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)} '
        'at (${r.x.toStringAsFixed(0)}, ${r.y.toStringAsFixed(0)})',
      );
    }
    final styles = el.computedStyles;
    for (final key in const [
      'color',
      'backgroundColor',
      'fontSize',
      'fontFamily',
      'borderRadius',
      'padding',
      'margin',
      'display',
    ]) {
      final v = styles[key];
      if (v != null && v.isNotEmpty && v != 'none' && v != 'normal') {
        buf.writeln('style.$key: $v');
      }
    }

    // Quién pinta el fondo real (gradientes Tailwind suelen estar en body/html).
    final bgOwner = _findBackgroundPaintOwner(el);
    if (bgOwner != null) {
      buf.writeln(
        'bg_paint_owner: <${bgOwner.tagName.toLowerCase()}> '
        'class="${bgOwner.className ?? ''}"',
      );
      final bgClass = bgOwner.className ?? '';
      if (_looksLikeBackgroundClass(bgClass)) {
        buf.writeln('bg_paint_classes: $bgClass');
      }
      buf.writeln(
        'bg_hint: Si el usuario pide cambiar el COLOR DE FONDO / '
        'background / gradiente, edita bg_paint_owner (a menudo body/html), '
        'NO solo el nodo seleccionado si su background es transparente.',
      );
    }

    if (_layers.length > 1) {
      buf.writeln('layers_under_cursor:');
      for (var i = 0; i < _layers.length && i < 8; i++) {
        final layer = _layers[i];
        final mark = _sameElement(layer, el) ? '▶ ' : '  ';
        final cls = layer.className ?? '';
        final bgMark = _looksLikeBackgroundClass(cls) ? ' [BG]' : '';
        buf.writeln('$mark${i + 1}. ${layer.layerLabel}$bgMark');
      }
    }
    buf.writeln(
      'note: El usuario señala este elemento en Preview. '
      'Si pide cambios de UI, asume que se refiere a ESTE elemento '
      '(salvo color de fondo → ver bg_paint_owner).',
    );
    buf.writeln('</inspector_selection>');
    return buf.toString().trimRight();
  }

  bool _isTransparentBg(String? bg) {
    if (bg == null || bg.isEmpty) return true;
    final s = bg.toLowerCase().replaceAll(' ', '');
    return s == 'transparent' ||
        s == 'rgba(0,0,0,0)' ||
        s == 'rgba(0,0,0,0.0)' ||
        s == 'initial' ||
        s == 'inherit';
  }

  bool _looksLikeBackgroundClass(String className) {
    final c = className.toLowerCase();
    return c.contains('bg-') ||
        c.contains('gradient') ||
        c.contains('from-') ||
        c.contains('via-') ||
        c.contains('to-');
  }

  /// Ancestro (o el propio nodo) que probablemente pinta el fondo visible.
  InspectorElement? _findBackgroundPaintOwner(InspectorElement selected) {
    final candidates = <InspectorElement>[
      selected,
      ..._layers,
    ];
    // Preferir capas con clases de fondo/gradiente (body a menudo al final).
    for (final layer in candidates) {
      final cls = layer.className ?? '';
      if (_looksLikeBackgroundClass(cls)) return layer;
    }
    for (final layer in candidates) {
      final bg = layer.computedStyles['backgroundColor'] ??
          layer.computedStyles['background-color'];
      if (!_isTransparentBg(bg)) return layer;
    }
    // Último recurso: body/html en la pila.
    for (final layer in candidates.reversed) {
      final t = layer.tagName.toLowerCase();
      if (t == 'body' || t == 'html') return layer;
    }
    return selected;
  }

  bool _sameElement(InspectorElement? a, InspectorElement? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.tagName == b.tagName &&
        a.id == b.id &&
        a.className == b.className &&
        a.textContent == b.textContent &&
        a.boundingRect?.x == b.boundingRect?.x &&
        a.boundingRect?.y == b.boundingRect?.y &&
        a.boundingRect?.width == b.boundingRect?.width &&
        a.boundingRect?.height == b.boundingRect?.height;
  }

  bool _sameLayers(List<InspectorElement> a, List<InspectorElement> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameElement(a[i], b[i])) return false;
    }
    return true;
  }
}
