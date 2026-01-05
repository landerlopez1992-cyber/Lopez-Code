import 'package:flutter/material.dart';
import 'cursor_theme.dart';

class CodeViewer extends StatelessWidget {
  final String code;
  final String language;

  const CodeViewer({
    super.key,
    required this.code,
    this.language = '',
  });

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      code,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: CursorTheme.codeText,
        height: 1.6,
        letterSpacing: 0.2,
      ),
    );
  }
}

