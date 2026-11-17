import 'dart:io';

/// Una pantalla del proyecto (HTML page o Flutter screen), estilo FlutterFlow.
class ProjectScreen {
  final String path;
  final String displayName;
  final ProjectScreenKind kind;

  const ProjectScreen({
    required this.path,
    required this.displayName,
    required this.kind,
  });
}

enum ProjectScreenKind { html, flutter }

/// Detecta pantallas/páginas a partir del árbol o del disco.
class ScreenDiscoveryService {
  ScreenDiscoveryService._();

  static const _skipDirParts = {
    'node_modules',
    '.git',
    'build',
    '.dart_tool',
    'dist',
    'coverage',
    'vendor',
    'assets',
    'images',
    'img',
    'fonts',
    'components',
    'includes',
    'partials',
    'widgets',
    'services',
    'models',
    'utils',
    'helpers',
    'test',
    'tests',
  };

  /// Desde el árbol del explorador (rápido, sin I/O extra).
  static List<ProjectScreen> fromTree(
    Map<String, dynamic>? tree, {
    String? projectPath,
  }) {
    if (tree == null) return const [];
    final found = <ProjectScreen>[];
    final root = (projectPath ?? tree['path'] as String? ?? '')
        .replaceAll('\\', '/');

    void walk(Map<String, dynamic> node) {
      final path = (node['path'] as String? ?? '').replaceAll('\\', '/');
      final type = node['type'] as String? ?? 'file';
      final name = node['name'] as String? ?? '';

      if (type == 'directory') {
        final base = name.toLowerCase();
        if (_skipDirParts.contains(base) || base.startsWith('.')) {
          return;
        }
        final children = node['children'] as List<dynamic>?;
        if (children == null) return;
        for (final child in children) {
          walk(child as Map<String, dynamic>);
        }
        return;
      }

      if (path.isEmpty || name.startsWith('_') || name.startsWith('.')) {
        return;
      }

      final screen = _classifyFile(path, name, root);
      if (screen != null) found.add(screen);
    }

    walk(tree);
    found.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return found;
  }

  /// Escaneo directo (p.ej. tras crear archivo).
  static Future<List<ProjectScreen>> fromDisk(String projectPath) async {
    final root = projectPath.replaceAll('\\', '/');
    final dir = Directory(root);
    if (!await dir.exists()) return const [];

    final found = <ProjectScreen>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll('\\', '/');
      final parts = path.split('/');
      if (parts.any((p) => _skipDirParts.contains(p.toLowerCase()) || p.startsWith('.'))) {
        continue;
      }
      final name = parts.last;
      if (name.startsWith('_') || name.startsWith('.')) continue;
      final screen = _classifyFile(path, name, root);
      if (screen != null) found.add(screen);
    }

    found.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return found;
  }

  static ProjectScreen? _classifyFile(String path, String name, String root) {
    final lower = name.toLowerCase();
    final rel = root.isNotEmpty && path.startsWith('$root/')
        ? path.substring(root.length + 1)
        : path;
    final relLower = rel.toLowerCase();

    if (lower.endsWith('.html')) {
      // Partials / includes sueltos.
      if (relLower.contains('/components/') ||
          relLower.contains('/includes/') ||
          relLower.contains('/partials/') ||
          relLower.contains('/widgets/')) {
        return null;
      }
      return ProjectScreen(
        path: path,
        displayName: prettyName(name, stripExt: '.html'),
        kind: ProjectScreenKind.html,
      );
    }

    if (!lower.endsWith('.dart')) return null;
    if (lower.endsWith('_test.dart') ||
        lower.endsWith('.g.dart') ||
        lower.endsWith('.freezed.dart') ||
        lower == 'main.dart') {
      return null;
    }

    final inScreensFolder = relLower.contains('/screens/') ||
        relLower.contains('/pages/') ||
        relLower.startsWith('lib/screens/') ||
        relLower.startsWith('lib/pages/') ||
        relLower.startsWith('screens/') ||
        relLower.startsWith('pages/');

    final looksLikeScreen = lower.endsWith('_screen.dart') ||
        lower.endsWith('_page.dart') ||
        lower.endsWith('screen.dart') ||
        lower.endsWith('page.dart');

    if (!inScreensFolder && !looksLikeScreen) return null;

    return ProjectScreen(
      path: path,
      displayName: prettyName(
        name,
        stripExt: '.dart',
        stripSuffixes: const ['_screen', '_page', 'Screen', 'Page'],
      ),
      kind: ProjectScreenKind.flutter,
    );
  }

  /// `forgot_password.html` → `Forgot Password`
  static String prettyName(
    String fileName, {
    required String stripExt,
    List<String> stripSuffixes = const [],
  }) {
    var base = fileName;
    if (base.toLowerCase().endsWith(stripExt.toLowerCase())) {
      base = base.substring(0, base.length - stripExt.length);
    }
    for (final suffix in stripSuffixes) {
      if (base.endsWith(suffix)) {
        base = base.substring(0, base.length - suffix.length);
        break;
      }
    }
    base = base.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    if (base.isEmpty) return fileName;
    // camelCase / PascalCase → espacios
    base = base.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]}',
    );
    return base
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))
        .join(' ');
  }

  /// Nombre de archivo seguro a partir del título de pantalla.
  static String fileSlug(String displayName, {required String extension}) {
    final slug = displayName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final safe = slug.isEmpty ? 'nueva_pantalla' : slug;
    return '$safe.$extension';
  }
}
