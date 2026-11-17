import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/inspector_element.dart';
import 'cursor_theme.dart';

/// Panel de propiedades completo por tipo de elemento.
class UiBuilderPropertiesPanel extends StatefulWidget {
  final InspectorElement element;
  final String blockId;
  final String? projectPath;
  final Future<void> Function({
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
    String? textAlign,
    String? href,
    String? src,
    String? placeholder,
  }) onApply;
  final Future<void> Function() onDelete;
  final Future<void> Function() onDuplicate;
  final Future<void> Function() onMoveUp;
  final Future<void> Function() onMoveDown;
  final VoidCallback? onClearSelection;

  const UiBuilderPropertiesPanel({
    super.key,
    required this.element,
    required this.blockId,
    required this.onApply,
    required this.onDelete,
    required this.onDuplicate,
    required this.onMoveUp,
    required this.onMoveDown,
    this.projectPath,
    this.onClearSelection,
  });

  @override
  State<UiBuilderPropertiesPanel> createState() =>
      _UiBuilderPropertiesPanelState();
}

class _UiBuilderPropertiesPanelState extends State<UiBuilderPropertiesPanel> {
  late final TextEditingController _textCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _bgCtrl;
  late final TextEditingController _paddingCtrl;
  late final TextEditingController _marginCtrl;
  late final TextEditingController _widthCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _fontSizeCtrl;
  late final TextEditingController _radiusCtrl;
  late final TextEditingController _borderCtrl;
  late final TextEditingController _hrefCtrl;
  late final TextEditingController _srcCtrl;
  late final TextEditingController _placeholderCtrl;
  bool _busy = false;
  String? _align;

  String get _kind =>
      (widget.element.attributes['data-voryxel'] ??
              widget.element.tagName.toLowerCase())
          .toLowerCase();

  bool get _isImage =>
      _kind == 'image' || widget.element.tagName.toLowerCase() == 'img';
  bool get _isVideo =>
      _kind == 'video' || widget.element.tagName.toLowerCase() == 'video';
  bool get _isMedia => _isImage || _isVideo;
  bool get _isLinkOrButton =>
      _kind == 'link' ||
      _kind == 'button' ||
      widget.element.tagName.toLowerCase() == 'a';
  bool get _isInput =>
      _kind == 'input' ||
      _kind == 'textarea' ||
      widget.element.tagName.toLowerCase() == 'input' ||
      widget.element.tagName.toLowerCase() == 'textarea';
  bool get _hasText =>
      !_isMedia &&
      (_kind == 'heading' ||
          _kind == 'paragraph' ||
          _kind == 'list' ||
          _isLinkOrButton ||
          _kind == 'card' ||
          _kind == 'hero' ||
          _kind == 'navbar' ||
          _kind == 'container' ||
          _isInput);

  @override
  void initState() {
    super.initState();
    _initFromElement();
  }

  void _initFromElement() {
    final styles = widget.element.computedStyles;
    final attrs = widget.element.attributes;
    _textCtrl = TextEditingController(
      text: (widget.element.textContent ?? '').trim(),
    );
    _colorCtrl = TextEditingController(text: _toHex(styles['color']) ?? '');
    _bgCtrl = TextEditingController(
      text: _toHex(styles['backgroundColor']) ?? '',
    );
    _paddingCtrl =
        TextEditingController(text: _simplifySpacing(styles['padding']));
    _marginCtrl =
        TextEditingController(text: _simplifySpacing(styles['margin']));
    _widthCtrl = TextEditingController(text: _simplifySize(styles['width']));
    _heightCtrl = TextEditingController(text: _simplifySize(styles['height']));
    _fontSizeCtrl =
        TextEditingController(text: _simplifySize(styles['fontSize']));
    _radiusCtrl =
        TextEditingController(text: _simplifySize(styles['borderRadius']));
    _borderCtrl = TextEditingController(text: (styles['border'] ?? '').trim());
    _hrefCtrl = TextEditingController(
      text: attrs['href'] ?? attrs['data-href'] ?? '',
    );
    _srcCtrl = TextEditingController(text: attrs['src'] ?? '');
    _placeholderCtrl =
        TextEditingController(text: attrs['placeholder'] ?? '');
    _align = styles['textAlign']?.trim();
    if (_align == 'start') _align = 'left';
    if (_align == 'end') _align = 'right';
  }

  @override
  void didUpdateWidget(covariant UiBuilderPropertiesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blockId != widget.blockId) {
      final styles = widget.element.computedStyles;
      final attrs = widget.element.attributes;
      _textCtrl.text = (widget.element.textContent ?? '').trim();
      _colorCtrl.text = _toHex(styles['color']) ?? '';
      _bgCtrl.text = _toHex(styles['backgroundColor']) ?? '';
      _paddingCtrl.text = _simplifySpacing(styles['padding']);
      _marginCtrl.text = _simplifySpacing(styles['margin']);
      _widthCtrl.text = _simplifySize(styles['width']);
      _heightCtrl.text = _simplifySize(styles['height']);
      _fontSizeCtrl.text = _simplifySize(styles['fontSize']);
      _radiusCtrl.text = _simplifySize(styles['borderRadius']);
      _borderCtrl.text = (styles['border'] ?? '').trim();
      _hrefCtrl.text = attrs['href'] ?? attrs['data-href'] ?? '';
      _srcCtrl.text = attrs['src'] ?? '';
      _placeholderCtrl.text = attrs['placeholder'] ?? '';
      _align = styles['textAlign']?.trim();
      if (_align == 'start') _align = 'left';
      if (_align == 'end') _align = 'right';
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _colorCtrl.dispose();
    _bgCtrl.dispose();
    _paddingCtrl.dispose();
    _marginCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _fontSizeCtrl.dispose();
    _radiusCtrl.dispose();
    _borderCtrl.dispose();
    _hrefCtrl.dispose();
    _srcCtrl.dispose();
    _placeholderCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply({String? alignOverride}) {
    return _run(() {
      return widget.onApply(
        text: _hasText && _textCtrl.text.trim().isNotEmpty
            ? _textCtrl.text.trim()
            : null,
        color: _normalizeColor(_colorCtrl.text),
        backgroundColor: _normalizeColor(_bgCtrl.text),
        padding: _emptyToNull(_paddingCtrl.text),
        margin: _emptyToNull(_marginCtrl.text),
        width: _emptyToNull(_widthCtrl.text),
        height: _emptyToNull(_heightCtrl.text),
        fontSize: _emptyToNull(_fontSizeCtrl.text),
        borderRadius: _emptyToNull(_radiusCtrl.text),
        border: _emptyToNull(_borderCtrl.text),
        textAlign: alignOverride ?? _align,
        href: (_isLinkOrButton || _isImage)
            ? _emptyToNull(_hrefCtrl.text)
            : null,
        src: _isMedia ? _emptyToNull(_srcCtrl.text) : null,
        placeholder: _isInput ? _emptyToNull(_placeholderCtrl.text) : null,
      );
    });
  }

  Future<void> _pickImageFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || path.isEmpty) return;

    // Copiar al proyecto /assets si hay projectPath.
    var src = path;
    final project = widget.projectPath;
    if (project != null && project.isNotEmpty) {
      try {
        final name =
            'voryxel_${DateTime.now().millisecondsSinceEpoch}_${path.split('/').last}';
        final destDir = Directory('$project/assets');
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }
        final dest = File('${destDir.path}/$name');
        await File(path).copy(dest.path);
        src = 'assets/$name';
      } catch (_) {
        src = path.startsWith(project) ? path.substring(project.length + 1) : path;
      }
    }
    setState(() => _srcCtrl.text = src);
    await _apply();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CursorTheme.border)),
        color: CursorTheme.explorerBackground,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                const Icon(Icons.tune, size: 14, color: CursorTheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Propiedades · $_kind',
                    style: const TextStyle(
                      color: CursorTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.onClearSelection != null)
                  IconButton(
                    tooltip: 'Quitar selección',
                    icon: const Icon(Icons.close, size: 14),
                    color: CursorTheme.textSecondary,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: widget.onClearSelection,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Text(
              'Arrastra para mover · doble clic texto · clic para seleccionar',
              style: TextStyle(
                color: CursorTheme.textSecondary.withValues(alpha: 0.9),
                fontSize: 10,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              children: [
                _iconBtn(Icons.arrow_upward, 'Subir', widget.onMoveUp),
                const SizedBox(width: 6),
                _iconBtn(Icons.arrow_downward, 'Bajar', widget.onMoveDown),
                const SizedBox(width: 6),
                _iconBtn(Icons.copy_all_outlined, 'Dup', widget.onDuplicate),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                for (final e in const [
                  ('left', Icons.format_align_left),
                  ('center', Icons.format_align_center),
                  ('right', Icons.format_align_right),
                ]) ...[
                  if (e.$1 != 'left') const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _align = e.$1);
                              await _apply(alignOverride: e.$1);
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _align == e.$1
                            ? CursorTheme.primary
                            : CursorTheme.textPrimary,
                        side: BorderSide(
                          color: _align == e.$1
                              ? CursorTheme.primary
                              : CursorTheme.border,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Icon(e.$2, size: 16),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                if (_hasText) ...[
                  _field(_isInput ? 'Etiqueta / texto' : 'Texto', _textCtrl,
                      maxLines: 2),
                  const SizedBox(height: 8),
                ],
                if (_isInput) ...[
                  _field('Placeholder', _placeholderCtrl),
                  const SizedBox(height: 8),
                ],
                if (_isImage) ...[
                  _field('URL de imagen (src)', _srcCtrl),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickImageFile,
                    icon: const Icon(Icons.photo_library_outlined, size: 14),
                    label: const Text(
                      'Cargar foto del Mac',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CursorTheme.textPrimary,
                      side: const BorderSide(color: CursorTheme.border),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _field('Al hacer clic → ir a (href)', _hrefCtrl),
                  const SizedBox(height: 4),
                  Text(
                    'Ej: login.html · montanas.html · #destinos · https://…',
                    style: TextStyle(
                      color: CursorTheme.textSecondary.withValues(alpha: 0.85),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_isVideo) ...[
                  _field('URL de video (src)', _srcCtrl),
                  const SizedBox(height: 4),
                  Text(
                    'Ej: https://…/video.mp4 · assets/clip.mp4',
                    style: TextStyle(
                      color: CursorTheme.textSecondary.withValues(alpha: 0.85),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_isLinkOrButton) ...[
                  _field('URL / navegar a (href)', _hrefCtrl),
                  const SizedBox(height: 4),
                  Text(
                    'Ej: index.html · montanas.html · https://…',
                    style: TextStyle(
                      color: CursorTheme.textSecondary.withValues(alpha: 0.85),
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(child: _field('Color', _colorCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _field('Fondo', _bgCtrl)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _field('Padding', _paddingCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _field('Margin', _marginCtrl)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _field('Ancho', _widthCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _field('Alto', _heightCtrl)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _field('Font size', _fontSizeCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _field('Radius', _radiusCtrl)),
                  ],
                ),
                const SizedBox(height: 8),
                _field('Borde (1px solid #ccc)', _borderCtrl),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : () => _apply(),
                  style: FilledButton.styleFrom(
                    backgroundColor: CursorTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
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
                      : const Text('Aplicar', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(widget.onDelete),
                  icon: const Icon(Icons.delete_outline, size: 14),
                  label: const Text('Eliminar', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String label, Future<void> Function() onTap) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: _busy ? null : () => _run(onTap),
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(
          foregroundColor: CursorTheme.textPrimary,
          side: const BorderSide(color: CursorTheme.border),
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: CursorTheme.textPrimary, fontSize: 12),
      cursorColor: CursorTheme.primary,
      inputFormatters: maxLines == 1
          ? [FilteringTextInputFormatter.deny(RegExp(r'[\n\r]'))]
          : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: CursorTheme.textSecondary,
          fontSize: 11,
        ),
        isDense: true,
        filled: true,
        fillColor: CursorTheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
    );
  }

  static String? _emptyToNull(String raw) {
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }

  static String? _normalizeColor(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('#') || RegExp(r'^[a-zA-Z]+$').hasMatch(t)) return t;
    if (RegExp(r'^[0-9a-fA-F]{3,8}$').hasMatch(t)) return '#$t';
    return t;
  }

  static String? _toHex(String? cssColor) {
    if (cssColor == null || cssColor.isEmpty) return null;
    final m = RegExp(
      r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)',
    ).firstMatch(cssColor);
    if (m != null) {
      int c(String s) => int.parse(s).clamp(0, 255);
      return '#'
          '${c(m.group(1)!).toRadixString(16).padLeft(2, '0')}'
          '${c(m.group(2)!).toRadixString(16).padLeft(2, '0')}'
          '${c(m.group(3)!).toRadixString(16).padLeft(2, '0')}';
    }
    if (cssColor.startsWith('#')) return cssColor;
    return null;
  }

  static String _simplifySpacing(String? value) {
    if (value == null || value.isEmpty) return '';
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.length == 4 &&
        parts[0] == parts[1] &&
        parts[1] == parts[2] &&
        parts[2] == parts[3]) {
      return parts[0];
    }
    return value.trim();
  }

  static String _simplifySize(String? value) {
    if (value == null || value.isEmpty) return '';
    if (value == 'auto' || value == '0px') return '';
    return value.trim();
  }
}
