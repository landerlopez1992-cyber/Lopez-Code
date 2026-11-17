import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/inspector_element.dart';
import '../services/inspector_selection_service.dart';
import 'cursor_theme.dart';

typedef InspectorApplyProps = Future<void> Function({
  String? text,
  String? width,
  String? height,
  String? color,
  String? backgroundColor,
  String? fontSize,
  String? borderRadius,
  String? opacity,
  String? href,
  String? src,
  String? tagName,
  String? blockId,
  String? oldText,
  bool persist,
  bool announce,
});

/// Panel lateral: editar el elemento seleccionado (no es el catálogo).
class InspectorMonitorPanel extends StatelessWidget {
  final double width;
  final InspectorApplyProps? onApplyProps;
  final VoidCallback? onClearSelection;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onDuplicate;
  final Future<void> Function()? onMoveUp;
  final Future<void> Function()? onMoveDown;

  const InspectorMonitorPanel({
    super.key,
    this.width = 260,
    this.onApplyProps,
    this.onClearSelection,
    this.onDelete,
    this.onDuplicate,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final service = InspectorSelectionService();
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final selected = service.selected;
        final focus = selected;
        final layers = service.layers;
        final isSelected = selected != null;

        return Container(
          width: width,
          margin: const EdgeInsets.only(left: 8, right: 4),
          decoration: BoxDecoration(
            color: CursorTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? CursorTheme.primary.withValues(alpha: 0.7)
                  : CursorTheme.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                isSelected: isSelected,
                hasFocus: focus != null,
                onClear: focus == null
                    ? null
                    : () {
                        service.clearSelection();
                        onClearSelection?.call();
                      },
              ),
              const Divider(height: 1, color: CursorTheme.border),
              Expanded(
                child: focus == null
                    ? const _EmptyState()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                        children: [
                          if (onMoveUp != null ||
                              onMoveDown != null ||
                              onDuplicate != null ||
                              onDelete != null) ...[
                            Row(
                              children: [
                                if (onMoveUp != null)
                                  Expanded(
                                    child: _MiniAction(
                                      icon: Icons.arrow_upward,
                                      label: 'Subir',
                                      onTap: onMoveUp!,
                                    ),
                                  ),
                                if (onMoveUp != null && onMoveDown != null)
                                  const SizedBox(width: 6),
                                if (onMoveDown != null)
                                  Expanded(
                                    child: _MiniAction(
                                      icon: Icons.arrow_downward,
                                      label: 'Bajar',
                                      onTap: onMoveDown!,
                                    ),
                                  ),
                                if (onDuplicate != null) ...[
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: _MiniAction(
                                      icon: Icons.copy_all_outlined,
                                      label: 'Dup',
                                      onTap: onDuplicate!,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (onDelete != null) ...[
                              const SizedBox(height: 6),
                              _MiniAction(
                                icon: Icons.delete_outline,
                                label: 'Eliminar elemento',
                                danger: true,
                                onTap: onDelete!,
                              ),
                            ],
                            const SizedBox(height: 12),
                          ],
                          if (layers.length > 1) ...[
                            _SectionLabel('Capas'),
                            const SizedBox(height: 6),
                            for (var i = 0; i < layers.length; i++)
                              _LayerTile(
                                index: i,
                                element: layers[i],
                                active: _same(layers[i], focus),
                                onTap: () => service.selectLayer(layers[i]),
                              ),
                            const SizedBox(height: 12),
                          ],
                          _PropertyEditor(
                            key: ValueKey(
                              '${focus.tagName}_${focus.id}_'
                              '${focus.className}_'
                              '${focus.attributes['src']}_'
                              '${focus.boundingRect?.x.round()}_'
                              '${focus.boundingRect?.y.round()}',
                            ),
                            element: focus,
                            isSelected: isSelected,
                            onApply: onApplyProps,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static bool _same(InspectorElement a, InspectorElement b) {
    return a.tagName == b.tagName &&
        a.id == b.id &&
        a.className == b.className &&
        a.textContent == b.textContent &&
        a.attributes['src'] == b.attributes['src'] &&
        a.boundingRect?.width == b.boundingRect?.width &&
        a.boundingRect?.height == b.boundingRect?.height;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: CursorTheme.textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  final bool danger;

  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.redAccent : CursorTheme.textPrimary;
    return OutlinedButton.icon(
      onPressed: () => onTap(),
      icon: Icon(icon, size: 13, color: color),
      label: Text(
        label,
        style: TextStyle(fontSize: 10, color: color),
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(
          color: danger ? Colors.redAccent : CursorTheme.border,
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool isSelected;
  final bool hasFocus;
  final VoidCallback? onClear;

  const _Header({
    required this.isSelected,
    required this.hasFocus,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Row(
        children: [
          Icon(
            Icons.tune,
            size: 14,
            color: isSelected ? CursorTheme.primary : CursorTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isSelected
                  ? 'Editar elemento'
                  : hasFocus
                      ? 'Apuntando'
                      : 'Inspector',
              style: const TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              tooltip: 'Limpiar',
              icon: const Icon(Icons.close, size: 14),
              color: CursorTheme.textSecondary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(14),
      child: Text(
        'Clic en un elemento del Preview para editar tamaño, color, texto, imagen o enlace.',
        style: TextStyle(
          color: CursorTheme.textSecondary,
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }
}

class _LayerTile extends StatelessWidget {
  const _LayerTile({
    required this.index,
    required this.element,
    required this.active,
    required this.onTap,
  });

  final int index;
  final InspectorElement element;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active
            ? CursorTheme.primary.withValues(alpha: 0.16)
            : CursorTheme.background,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: active
                    ? CursorTheme.primary.withValues(alpha: 0.5)
                    : CursorTheme.border,
              ),
            ),
            child: Text(
              '${index + 1}. ${element.layerLabel}',
              style: TextStyle(
                color: active
                    ? CursorTheme.textPrimary
                    : CursorTheme.textSecondary,
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

class _PropertyEditor extends StatefulWidget {
  final InspectorElement element;
  final bool isSelected;
  final InspectorApplyProps? onApply;

  const _PropertyEditor({
    super.key,
    required this.element,
    required this.isSelected,
    this.onApply,
  });

  @override
  State<_PropertyEditor> createState() => _PropertyEditorState();
}

class _PropertyEditorState extends State<_PropertyEditor> {
  late final TextEditingController _text;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _color;
  late final TextEditingController _bg;
  late final TextEditingController _fontSize;
  late final TextEditingController _radius;
  late final TextEditingController _opacity;
  late final TextEditingController _href;
  late final TextEditingController _src;
  bool _busy = false;
  Timer? _persistTimer;

  double _widthVal = 100;
  double _heightVal = 48;
  double _fontVal = 16;
  double _radiusVal = 8;
  double _opacityVal = 1;

  String get _tag => widget.element.tagName.toLowerCase();
  bool get _isImg => _tag == 'img' || _tag == 'image' || _tag == 'picture';
  bool get _isLinkish =>
      _tag == 'a' ||
      _tag == 'button' ||
      widget.element.attributes.containsKey('href') ||
      _isImg;

  bool get _canEditText {
    if (_isImg) return false;
    const editable = {
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'p', 'span', 'a', 'button', 'li', 'strong', 'label', 'div', 'td', 'th',
    };
    final t = widget.element.textContent?.trim() ?? '';
    return editable.contains(_tag) || t.isNotEmpty;
  }

  double _parseNum(String? raw, double fallback) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    final m = RegExp(r'([\d.]+)').firstMatch(raw);
    if (m == null) return fallback;
    return double.tryParse(m.group(1)!) ?? fallback;
  }

  String _px(String? raw, double? fallback) {
    if (raw != null && raw.trim().isNotEmpty) {
      final m = RegExp(r'([\d.]+)').firstMatch(raw);
      if (m != null) return m.group(1)!;
    }
    if (fallback != null && fallback > 0) {
      return fallback == fallback.roundToDouble()
          ? fallback.round().toString()
          : fallback.toStringAsFixed(1);
    }
    return '';
  }

  String _rgbToHex(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final s = raw.trim();
    if (s.startsWith('#')) return s;
    final m = RegExp(
      r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)',
    ).firstMatch(s);
    if (m == null) return s;
    int n(String v) => int.parse(v).clamp(0, 255);
    return '#'
        '${n(m.group(1)!).toRadixString(16).padLeft(2, '0')}'
        '${n(m.group(2)!).toRadixString(16).padLeft(2, '0')}'
        '${n(m.group(3)!).toRadixString(16).padLeft(2, '0')}';
  }

  double _parseOpacity(Map<String, String> styles) {
    final o = styles['opacity'];
    if (o != null && o.trim().isNotEmpty) {
      return (double.tryParse(o.trim()) ?? 1.0).clamp(0.0, 1.0);
    }
    // rgba(..., a)
    final bg = styles['backgroundColor'] ?? styles['color'] ?? '';
    final m = RegExp(
      r'rgba\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*,\s*([\d.]+)\s*\)',
    ).firstMatch(bg);
    if (m != null) {
      return (double.tryParse(m.group(1)!) ?? 1.0).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  @override
  void initState() {
    super.initState();
    final el = widget.element;
    final styles = el.computedStyles;
    final rect = el.boundingRect;
    _widthVal = _parseNum(styles['width'], rect?.width ?? 100);
    _heightVal = _parseNum(styles['height'], rect?.height ?? 48);
    _fontVal = _parseNum(styles['fontSize'], 16).clamp(8.0, 96.0);
    _radiusVal = _parseNum(styles['borderRadius'], 8).clamp(0.0, 80.0);
    _opacityVal = _parseOpacity(styles);

    _text = TextEditingController(text: el.textContent?.trim() ?? '');
    _width = TextEditingController(text: _fmt(_widthVal));
    _height = TextEditingController(text: _fmt(_heightVal));
    _color = TextEditingController(text: _rgbToHex(styles['color']));
    _bg = TextEditingController(text: _rgbToHex(styles['backgroundColor']));
    _fontSize = TextEditingController(text: _fmt(_fontVal));
    _radius = TextEditingController(text: _fmt(_radiusVal));
    _opacity = TextEditingController(text: _opacityVal.toStringAsFixed(2));
    _href = TextEditingController(
      text: el.attributes['href'] ?? el.attributes['data-href'] ?? '',
    );
    _src = TextEditingController(
      text: el.attributes['src'] ?? el.attributes['data-src'] ?? '',
    );
  }

  String _fmt(double v) {
    if ((v - v.roundToDouble()).abs() < 0.05) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _text.dispose();
    _width.dispose();
    _height.dispose();
    _color.dispose();
    _bg.dispose();
    _fontSize.dispose();
    _radius.dispose();
    _opacity.dispose();
    _href.dispose();
    _src.dispose();
    super.dispose();
  }

  String? _normSize(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) return '${t}px';
    return t;
  }

  String? _normColor(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return t;
  }

  Future<void> _push({required bool persist, bool announce = false}) async {
    final cb = widget.onApply;
    if (cb == null) return;
    await cb(
      text: _canEditText ? _text.text : null,
      oldText: widget.element.textContent?.trim(),
      width: _normSize(_width.text),
      height: _normSize(_height.text),
      color: _normColor(_color.text),
      backgroundColor: _normColor(_bg.text),
      fontSize: _normSize(_fontSize.text),
      borderRadius: _normSize(_radius.text),
      opacity: _opacityVal.clamp(0.0, 1.0).toStringAsFixed(2),
      href: _isLinkish
          ? (_href.text.trim().isEmpty ? null : _href.text.trim())
          : null,
      src: _isImg
          ? (_src.text.trim().isEmpty ? null : _src.text.trim())
          : null,
      tagName: widget.element.tagName,
      blockId: widget.element.attributes['data-voryxel-id'],
      persist: persist,
      announce: announce,
    );
  }

  void _liveThenPersist() {
    unawaited(_push(persist: false));
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 280), () {
      unawaited(_push(persist: true));
    });
  }

  Future<void> _apply() async {
    final cb = widget.onApply;
    if (cb == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _push(persist: true, announce: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onSlider({
    required double value,
    required void Function(double) setVal,
    required TextEditingController ctrl,
    required double min,
    required double max,
    bool isOpacity = false,
  }) {
    final v = value.clamp(min, max);
    setVal(v);
    ctrl.text = isOpacity ? v.toStringAsFixed(2) : _fmt(v);
    setState(() {});
    _liveThenPersist();
  }

  void _onNumberField({
    required String raw,
    required void Function(double) setVal,
    required TextEditingController ctrl,
    required double min,
    required double max,
    bool isOpacity = false,
  }) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) return;
    final v = parsed.clamp(min, max);
    setVal(v);
    if (isOpacity) {
      ctrl.text = v.toStringAsFixed(2);
    } else {
      ctrl.text = _fmt(v);
    }
    setState(() {});
    _liveThenPersist();
  }

  @override
  Widget build(BuildContext context) {
    final el = widget.element;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: CursorTheme.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isSelected
                  ? const Color(0xFF22C55E).withValues(alpha: 0.5)
                  : CursorTheme.primary.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isImg
                    ? Icons.image_outlined
                    : _tag == 'a'
                        ? Icons.link
                        : Icons.crop_square,
                size: 14,
                color: CursorTheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  el.displayName,
                  style: const TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _tag,
                style: const TextStyle(
                  color: CursorTheme.textDisabled,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_canEditText) ...[
          _SectionLabel('Texto'),
          const SizedBox(height: 6),
          _Field(controller: _text, hint: 'Texto visible', maxLines: 3),
          const SizedBox(height: 12),
        ],
        if (_isImg) ...[
          _SectionLabel('Imagen'),
          const SizedBox(height: 6),
          _Field(controller: _src, hint: 'URL de la foto (https://…)'),
          const SizedBox(height: 12),
        ],
        if (_isLinkish) ...[
          _SectionLabel(_isImg ? 'Al hacer clic → ir a' : 'Enlace / redirect'),
          const SizedBox(height: 6),
          _Field(
            controller: _href,
            hint: _isImg
                ? 'URL o ruta (#/login, /dashboard…)'
                : 'href (#seccion, /ruta, https://…)',
          ),
          const SizedBox(height: 12),
        ],
        _SectionLabel('Tamaño'),
        const SizedBox(height: 4),
        _LiveSlider(
          label: 'Ancho',
          value: _widthVal.clamp(1.0, 900.0),
          min: 1,
          max: 900,
          controller: _width,
          unit: 'px',
          onSlider: (v) => _onSlider(
            value: v,
            setVal: (x) => _widthVal = x,
            ctrl: _width,
            min: 1,
            max: 900,
          ),
          onField: (raw) => _onNumberField(
            raw: raw,
            setVal: (x) => _widthVal = x,
            ctrl: _width,
            min: 1,
            max: 900,
          ),
        ),
        _LiveSlider(
          label: 'Alto',
          value: _heightVal.clamp(1.0, 900.0),
          min: 1,
          max: 900,
          controller: _height,
          unit: 'px',
          onSlider: (v) => _onSlider(
            value: v,
            setVal: (x) => _heightVal = x,
            ctrl: _height,
            min: 1,
            max: 900,
          ),
          onField: (raw) => _onNumberField(
            raw: raw,
            setVal: (x) => _heightVal = x,
            ctrl: _height,
            min: 1,
            max: 900,
          ),
        ),
        const SizedBox(height: 8),
        _SectionLabel('Opacity'),
        const SizedBox(height: 4),
        _LiveSlider(
          label: 'Opacity',
          value: _opacityVal,
          min: 0,
          max: 1,
          divisions: 100,
          controller: _opacity,
          unit: '',
          onSlider: (v) => _onSlider(
            value: v,
            setVal: (x) => _opacityVal = x,
            ctrl: _opacity,
            min: 0,
            max: 1,
            isOpacity: true,
          ),
          onField: (raw) => _onNumberField(
            raw: raw,
            setVal: (x) => _opacityVal = x,
            ctrl: _opacity,
            min: 0,
            max: 1,
            isOpacity: true,
          ),
        ),
        const SizedBox(height: 8),
        _SectionLabel('Color'),
        const SizedBox(height: 6),
        _Field(
          controller: _color,
          label: 'Texto',
          hint: '#ffffff',
          onChanged: (_) => _liveThenPersist(),
        ),
        const SizedBox(height: 6),
        _Field(
          controller: _bg,
          label: 'Fondo',
          hint: '#000000 o transparent',
          onChanged: (_) => _liveThenPersist(),
        ),
        const SizedBox(height: 8),
        _SectionLabel('Tipografía / radio'),
        const SizedBox(height: 4),
        _LiveSlider(
          label: 'Font',
          value: _fontVal.clamp(8.0, 96.0),
          min: 8,
          max: 96,
          controller: _fontSize,
          unit: 'px',
          onSlider: (v) => _onSlider(
            value: v,
            setVal: (x) => _fontVal = x,
            ctrl: _fontSize,
            min: 8,
            max: 96,
          ),
          onField: (raw) => _onNumberField(
            raw: raw,
            setVal: (x) => _fontVal = x,
            ctrl: _fontSize,
            min: 8,
            max: 96,
          ),
        ),
        _LiveSlider(
          label: 'Radius',
          value: _radiusVal.clamp(0.0, 80.0),
          min: 0,
          max: 80,
          controller: _radius,
          unit: 'px',
          onSlider: (v) => _onSlider(
            value: v,
            setVal: (x) => _radiusVal = x,
            ctrl: _radius,
            min: 0,
            max: 80,
          ),
          onField: (raw) => _onNumberField(
            raw: raw,
            setVal: (x) => _radiusVal = x,
            ctrl: _radius,
            min: 0,
            max: 80,
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: widget.onApply == null || _busy ? null : _apply,
          style: FilledButton.styleFrom(
            backgroundColor: CursorTheme.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(34),
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Guardar',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Los sliders aplican en vivo al Preview',
            style: TextStyle(
              color: CursorTheme.textDisabled,
              fontSize: 10,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// Slider + campo numérico sincronizados (estilo FlutterFlow).
class _LiveSlider extends StatelessWidget {
  const _LiveSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.controller,
    required this.onSlider,
    required this.onField,
    this.divisions,
    this.unit = 'px',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final TextEditingController controller;
  final String unit;
  final ValueChanged<double> onSlider;
  final ValueChanged<String> onField;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: CursorTheme.textDisabled,
              fontSize: 10,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                    activeTrackColor: CursorTheme.primary,
                    inactiveTrackColor: CursorTheme.border,
                    thumbColor: Colors.white,
                    overlayColor: CursorTheme.primary.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: onSlider,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 58,
                child: TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 12,
                  ),
                  cursorColor: CursorTheme.primary,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  onChanged: onField,
                  onSubmitted: onField,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: CursorTheme.background,
                    suffixText: unit.isEmpty ? null : unit,
                    suffixStyle: const TextStyle(
                      color: CursorTheme.textDisabled,
                      fontSize: 9,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: CursorTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: CursorTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          const BorderSide(color: CursorTheme.primary),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboard,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: const TextStyle(
              color: CursorTheme.textDisabled,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 3),
        ],
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboard,
          onChanged: onChanged,
          style: const TextStyle(
            color: CursorTheme.textPrimary,
            fontSize: 12,
          ),
          cursorColor: CursorTheme.primary,
          inputFormatters: keyboard == TextInputType.number
              ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
              : null,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: CursorTheme.background,
            hintText: hint,
            hintStyle: TextStyle(
              color: CursorTheme.textDisabled.withValues(alpha: 0.75),
              fontSize: 11,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 9,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: CursorTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: CursorTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: CursorTheme.primary),
            ),
          ),
        ),
      ],
    );
  }
}
