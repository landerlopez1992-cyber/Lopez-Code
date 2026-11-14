import 'package:flutter/material.dart';

import 'code_language.dart';
import 'cursor_theme.dart';
import 'editor_symbols.dart';

/// Barra de ruta bajo las pestañas: `lib › models › message.dart › Message ›
/// canContinueTask`.
class EditorBreadcrumbs extends StatelessWidget {
  const EditorBreadcrumbs({
    super.key,
    required this.filePath,
    required this.projectRoot,
    required this.symbols,
  });

  final String? filePath;
  final String? projectRoot;
  final List<EditorSymbol> symbols;

  static const double height = 24;
  static const Color _textColor = Color(0xFFA9A9A9);
  static const Color _separatorColor = Color(0xFF6E6E6E);

  List<String> _pathSegments() {
    final path = filePath;
    if (path == null || path.isEmpty) return const ['Untitled'];
    final root = projectRoot;
    if (root != null && root.isNotEmpty) {
      final normalizedRoot = root.endsWith('/') ? root : '$root/';
      if (path.startsWith(normalizedRoot)) {
        return path.substring(normalizedRoot.length).split('/');
      }
    }
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.length <= 3 ? parts : parts.sublist(parts.length - 3);
  }

  static (IconData, Color) _symbolIcon(EditorSymbolKind kind) {
    switch (kind) {
      case EditorSymbolKind.classLike:
        return (Icons.category_outlined, const Color(0xFFEE9D28));
      case EditorSymbolKind.method:
        return (Icons.view_in_ar_outlined, const Color(0xFFB180D7));
      case EditorSymbolKind.field:
        return (Icons.label_outline, const Color(0xFF75BEFF));
      case EditorSymbolKind.block:
        return (Icons.data_object, const Color(0xFF75BEFF));
      case EditorSymbolKind.heading:
        return (Icons.tag, const Color(0xFF75BEFF));
    }
  }

  @override
  Widget build(BuildContext context) {
    final segments = _pathSegments();
    final fileIcon = FileTypeIcon.forPath(filePath);
    final items = <Widget>[];

    void addSeparator() {
      items.add(const Padding(
        padding: EdgeInsets.symmetric(horizontal: 2),
        child: Icon(Icons.chevron_right, size: 14, color: _separatorColor),
      ));
    }

    for (var i = 0; i < segments.length; i++) {
      if (i > 0) addSeparator();
      final isFile = i == segments.length - 1;
      if (isFile) {
        items.add(Icon(fileIcon.icon, size: 13, color: fileIcon.color));
        items.add(const SizedBox(width: 4));
      }
      items.add(_label(segments[i]));
    }
    for (final symbol in symbols) {
      addSeparator();
      final (icon, color) = _symbolIcon(symbol.kind);
      items.add(Icon(icon, size: 13, color: color));
      items.add(const SizedBox(width: 4));
      items.add(_label(symbol.name));
    }

    return Container(
      height: height,
      color: CursorTheme.editorBackground,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(mainAxisSize: MainAxisSize.min, children: items),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        maxLines: 1,
        style: const TextStyle(color: _textColor, fontSize: 12, height: 1.2),
      );
}
