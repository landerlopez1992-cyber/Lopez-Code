import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopez_code_ai/widgets/code_language.dart';
import 'package:lopez_code_ai/widgets/code_syntax_controller.dart';
import 'package:lopez_code_ai/widgets/editor_symbols.dart';

List<String> _names(List<EditorSymbol> symbols) =>
    symbols.map((s) => s.name).toList();

Map<String, Color?> _colorsByToken(CodeSyntaxController c) {
  final span = c.buildTextSpan(
    context: _FakeContext(),
    withComposing: false,
  );
  final result = <String, Color?>{};
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan && child.text != null) {
      result[child.text!.trim()] = child.style?.color;
    }
  }
  return result;
}

class _FakeContext extends Fake implements BuildContext {}

void main() {
  group('Detección de lenguaje', () {
    test('por extensión', () {
      expect(CodeLanguage.forPath('/p/lib/main.dart').id, 'dart');
      expect(CodeLanguage.forPath('/p/android/build.gradle').id, 'groovy');
      expect(CodeLanguage.forPath('/p/a/build.gradle.kts').id, 'kotlin');
      expect(CodeLanguage.forPath('/p/ios/AppDelegate.swift').id, 'swift');
      expect(CodeLanguage.forPath('/p/pubspec.yaml').id, 'yaml');
      expect(CodeLanguage.forPath('/p/a.json').id, 'json');
      expect(CodeLanguage.forPath('/p/AndroidManifest.xml').id, 'xml');
      expect(CodeLanguage.forPath('/p/run.sh').id, 'shell');
      expect(CodeLanguage.forPath('/p/README.md').id, 'markdown');
    });
  });

  group('Breadcrumb symbols', () {
    test('Dart: clase › campo', () {
      final lines = [
        'class Message {',
        '  final String role;',
        '  final bool canContinueTask;',
        '',
        '  Message({',
        '    required this.role,',
        '  });',
        '',
        '  Message copyWith({',
        '    String? role,',
        '  }) {',
        '    return Message(',
        '      role: role ?? this.role,',
        '    );',
        '  }',
        '}',
      ];
      expect(
        _names(EditorSymbolFinder.symbolsAt(lines, 2, CodeLanguage.dart)),
        ['Message', 'canContinueTask'],
      );
      expect(
        _names(EditorSymbolFinder.symbolsAt(lines, 12, CodeLanguage.dart)),
        ['Message', 'copyWith'],
      );
      expect(
        _names(EditorSymbolFinder.symbolsAt(lines, 5, CodeLanguage.dart)),
        ['Message', 'Message'],
      );
    });

    test('Dart: build con árbol de widgets', () {
      final lines = [
        'class _HomeState extends State<Home> {',
        '  @override',
        '  Widget build(BuildContext context) {',
        '    return Scaffold(',
        '      body: Text(',
        "        'hola',",
        '      ),',
        '    );',
        '  }',
        '}',
      ];
      expect(
        _names(EditorSymbolFinder.symbolsAt(lines, 5, CodeLanguage.dart)),
        ['_HomeState', 'build'],
      );
    });

    test('Gradle: bloques anidados', () {
      final lines = [
        'subprojects {',
        '  afterEvaluate { project ->',
        '    if (project.plugins.hasPlugin("com.android.application") ||',
        '        project.plugins.hasPlugin("com.android.library")) {',
        '      project.android {',
        '        compileSdkVersion 35',
        '      }',
        '    }',
        '  }',
        '}',
      ];
      expect(
        _names(EditorSymbolFinder.symbolsAt(lines, 5, CodeLanguage.groovy)),
        ['subprojects', 'afterEvaluate', 'project.android'],
      );
    });

    test('YAML: dependencies › http', () {
      final lines = [
        'name: demo',
        'dependencies:',
        '  flutter:',
        '    sdk: flutter',
        '  http: ^1.2.0',
      ];
      expect(
        _names(EditorSymbolFinder.symbolsAt(lines, 4, CodeLanguage.yaml)),
        ['dependencies', 'http'],
      );
    });
  });

  group('Coloreado', () {
    test('Gradle: funciones, strings y números', () {
      final c = CodeSyntaxController(
        text: "repositories {\n  google()\n}\nrootProject.buildDir = '../build'\ncompileSdkVersion 35",
        language: CodeLanguage.groovy,
      );
      final colors = _colorsByToken(c);
      expect(colors['google'], SyntaxColors.function);
      expect(colors["'../build'"], SyntaxColors.string);
      expect(colors['35'], SyntaxColors.number);
      expect(colors['compileSdkVersion'], SyntaxColors.variable);
    });

    test('Dart: keywords, tipos y propiedades', () {
      final c = CodeSyntaxController(
        text: 'final String role = this.role;\nreturn Text(x);',
        language: CodeLanguage.dart,
      );
      final colors = _colorsByToken(c);
      expect(colors['final'], SyntaxColors.declKeyword);
      expect(colors['String'], SyntaxColors.type);
      expect(colors['return'], SyntaxColors.controlKeyword);
      expect(colors['Text'], SyntaxColors.type);
    });

    test('YAML: claves y valores', () {
      final c = CodeSyntaxController(
        text: 'dependencies:\n  http: ^1.2.0 # red\n  enabled: true',
        language: CodeLanguage.yaml,
      );
      final colors = _colorsByToken(c);
      expect(colors['http'], SyntaxColors.declKeyword);
      expect(colors['^1.2.0'], SyntaxColors.string);
      expect(colors['# red'], SyntaxColors.comment);
      expect(colors['true'], SyntaxColors.declKeyword);
    });
  });
}
