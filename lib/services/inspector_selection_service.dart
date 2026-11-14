import 'package:flutter/foundation.dart';

import '../models/inspector_element.dart';

/// Selección del Inspector en Preview (hover + click).
/// El agente la lee vía `<workspace_state>` / `inspector_selection`.
class InspectorSelectionService extends ChangeNotifier {
  static final InspectorSelectionService _instance =
      InspectorSelectionService._();
  factory InspectorSelectionService() => _instance;
  InspectorSelectionService._();

  bool _active = false;
  InspectorElement? _hovered;
  InspectorElement? _selected;

  bool get isActive => _active;
  InspectorElement? get hovered => _hovered;
  InspectorElement? get selected => _selected;

  /// Elemento que el usuario está señalando (selección > hover).
  InspectorElement? get focus => _selected ?? _hovered;

  bool get hasSelection => _selected != null;

  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (!value) {
      _hovered = null;
      _selected = null;
    }
    notifyListeners();
  }

  void setHovered(InspectorElement? element) {
    if (!_active) return;
    final same = _sameElement(_hovered, element);
    if (same) return;
    _hovered = element;
    notifyListeners();
  }

  void setSelected(InspectorElement? element) {
    if (!_active && element != null) {
      _active = true;
    }
    _selected = element;
    if (element != null) {
      _hovered = element;
    }
    notifyListeners();
  }

  void clearSelection() {
    if (_selected == null && _hovered == null) return;
    _selected = null;
    _hovered = null;
    notifyListeners();
  }

  void clear() {
    _active = false;
    _hovered = null;
    _selected = null;
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
    buf.writeln(
      'note: El usuario señala este elemento en Preview. '
      'Si pide cambios de UI, asume que se refiere a ESTE elemento.',
    );
    buf.writeln('</inspector_selection>');
    return buf.toString().trimRight();
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
}
