import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Estado de un archivo en el working tree / index de Git.
enum GitChangeKind { modified, added, deleted, renamed, copied, untracked, unmerged, ignored, unknown }

/// Dónde aparece el cambio.
enum GitChangeArea { staged, unstaged, both }

class GitFileChange {
  final String path;
  final String? oldPath; // renames
  final GitChangeKind kind;
  final bool staged;
  final bool unstaged;

  /// Códigos porcelain XY (p. ej. "M ", " M", "A ", "??").
  final String xy;

  const GitFileChange({
    required this.path,
    this.oldPath,
    required this.kind,
    required this.staged,
    required this.unstaged,
    required this.xy,
  });

  String get badge {
    switch (kind) {
      case GitChangeKind.modified:
        return 'M';
      case GitChangeKind.added:
        return 'A';
      case GitChangeKind.deleted:
        return 'D';
      case GitChangeKind.renamed:
        return 'R';
      case GitChangeKind.copied:
        return 'C';
      case GitChangeKind.untracked:
        return 'U';
      case GitChangeKind.unmerged:
        return 'U';
      case GitChangeKind.ignored:
        return 'I';
      case GitChangeKind.unknown:
        return '?';
    }
  }

  GitChangeArea get area {
    if (staged && unstaged) return GitChangeArea.both;
    if (staged) return GitChangeArea.staged;
    return GitChangeArea.unstaged;
  }
}

class GitRepoStatus {
  final String branch;
  final List<GitFileChange> changes;
  final bool isRepo;
  final String? error;

  const GitRepoStatus({
    required this.branch,
    required this.changes,
    this.isRepo = true,
    this.error,
  });

  List<GitFileChange> get staged =>
      changes.where((c) => c.staged).toList(growable: false);

  List<GitFileChange> get unstaged =>
      changes.where((c) => c.unstaged || c.kind == GitChangeKind.untracked).toList(growable: false);

  bool get hasChanges => changes.isNotEmpty;

  int get stagedCount => staged.length;
  int get unstagedCount => unstaged.length;
}

class GitService {
  static const String _repoUrlKey = 'git_repo_url_';
  static const String _repoBranchKey = 'git_repo_branch_';

  // ── Config (prefs) ──────────────────────────────────────────────

  static Future<void> saveGitConfig({
    required String projectPath,
    required String repoUrl,
    String branch = 'main',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final projectKey = _getProjectKey(projectPath);

    await prefs.setString('$_repoUrlKey$projectKey', repoUrl);
    await prefs.setString('$_repoBranchKey$projectKey', branch);
  }

  static Future<Map<String, String>?> getGitConfig(String projectPath) async {
    final prefs = await SharedPreferences.getInstance();
    final projectKey = _getProjectKey(projectPath);

    final repoUrl = prefs.getString('$_repoUrlKey$projectKey');
    final branch = prefs.getString('$_repoBranchKey$projectKey') ?? 'main';

    if (repoUrl == null || repoUrl.isEmpty) {
      return null;
    }

    return {
      'repoUrl': repoUrl,
      'branch': branch,
    };
  }

  static Future<bool> hasGitConfig(String projectPath) async {
    final config = await getGitConfig(projectPath);
    return config != null;
  }

  static Future<bool> isGitRepository(String projectPath) async {
    final gitDir = Directory('$projectPath/.git');
    return await gitDir.exists();
  }

  static Future<String> initGitRepository(String projectPath) async {
    try {
      final result = await Process.run(
        'git',
        ['init'],
        workingDirectory: projectPath,
      );

      if (result.exitCode == 0) {
        return 'Repositorio Git inicializado correctamente';
      } else {
        throw Exception(result.stderr);
      }
    } catch (e) {
      throw Exception('Error al inicializar Git: $e');
    }
  }

  static Future<String> addRemote({
    required String projectPath,
    required String remoteName,
    required String remoteUrl,
  }) async {
    try {
      final result = await Process.run(
        'git',
        ['remote', 'add', remoteName, remoteUrl],
        workingDirectory: projectPath,
      );

      if (result.exitCode == 0) {
        return 'Remoto agregado correctamente';
      } else {
        throw Exception(result.stderr);
      }
    } catch (e) {
      throw Exception('Error al agregar remoto: $e');
    }
  }

  // ── SCM API (Cursor-style) ──────────────────────────────────────

  /// Estado estructurado: staged / unstaged / untracked.
  static Future<GitRepoStatus> getStatus(String projectPath) async {
    if (!await isGitRepository(projectPath)) {
      return const GitRepoStatus(
        branch: '',
        changes: [],
        isRepo: false,
        error: 'No es un repositorio Git',
      );
    }

    try {
      final statusResult = await Process.run(
        'git',
        ['status', '--porcelain', '-uall'],
        workingDirectory: projectPath,
      );
      final branch = await getCurrentBranch(projectPath);

      if (statusResult.exitCode != 0) {
        return GitRepoStatus(
          branch: branch,
          changes: const [],
          error: statusResult.stderr.toString().trim(),
        );
      }

      final changes = _parsePorcelain(statusResult.stdout.toString());
      return GitRepoStatus(branch: branch, changes: changes);
    } catch (e) {
      return GitRepoStatus(
        branch: '',
        changes: const [],
        error: e.toString(),
      );
    }
  }

  /// Diff de un archivo. [staged]=true → `git diff --cached`.
  static Future<String> getFileDiff(
    String projectPath,
    String filePath, {
    bool staged = false,
  }) async {
    final args = <String>['diff'];
    if (staged) {
      args.add('--cached');
    }
    args.addAll(['--', filePath]);

    // Untracked: no hay diff vs index → mostrar contenido como altas.
    if (!staged) {
      final status = await getStatus(projectPath);
      final match = status.changes.where((c) => c.path == filePath).toList();
      if (match.isNotEmpty && match.first.kind == GitChangeKind.untracked) {
        final file = File('$projectPath/$filePath');
        if (await file.exists()) {
          final content = await file.readAsString();
          final lines = content.split('\n');
          final buffer = StringBuffer();
          buffer.writeln('diff --git a/$filePath b/$filePath');
          buffer.writeln('new file mode 100644');
          buffer.writeln('--- /dev/null');
          buffer.writeln('+++ b/$filePath');
          for (final line in lines) {
            buffer.writeln('+$line');
          }
          return buffer.toString();
        }
      }
    }

    final result = await Process.run(
      'git',
      args,
      workingDirectory: projectPath,
    );

    if (result.exitCode != 0 && result.stdout.toString().trim().isEmpty) {
      throw Exception(
        result.stderr.toString().trim().isEmpty
            ? 'Error al obtener diff de $filePath'
            : result.stderr.toString().trim(),
      );
    }

    final out = result.stdout.toString();
    if (out.trim().isEmpty) {
      return '(sin diferencias)';
    }
    return out;
  }

  /// Diff agregado de todos los cambios (staged + unstaged) para IA / resumen.
  static Future<String> getFullDiff(String projectPath, {bool stagedOnly = false}) async {
    final args = stagedOnly
        ? <String>['diff', '--cached']
        : <String>['diff', 'HEAD'];
    final result = await Process.run(
      'git',
      args,
      workingDirectory: projectPath,
    );
    final out = result.stdout.toString();
    if (out.trim().isNotEmpty) return out;

    // Incluir untracked resumidos
    final status = await getStatus(projectPath);
    final untracked = status.changes
        .where((c) => c.kind == GitChangeKind.untracked)
        .map((c) => 'new file: ${c.path}')
        .toList();
    if (untracked.isEmpty) return '(sin cambios)';
    return untracked.join('\n');
  }

  static Future<void> stageFile(String projectPath, String filePath) async {
    final result = await Process.run(
      'git',
      ['add', '--', filePath],
      workingDirectory: projectPath,
    );
    if (result.exitCode != 0) {
      throw Exception('Error al hacer stage de $filePath: ${result.stderr}');
    }
  }

  static Future<void> stageAll(String projectPath) async {
    final result = await Process.run(
      'git',
      ['add', '-A'],
      workingDirectory: projectPath,
    );
    if (result.exitCode != 0) {
      throw Exception('Error al hacer stage de todos: ${result.stderr}');
    }
  }

  static Future<void> unstageFile(String projectPath, String filePath) async {
    // `git restore --staged` (moderno) con fallback a `reset HEAD`
    var result = await Process.run(
      'git',
      ['restore', '--staged', '--', filePath],
      workingDirectory: projectPath,
    );
    if (result.exitCode != 0) {
      result = await Process.run(
        'git',
        ['reset', 'HEAD', '--', filePath],
        workingDirectory: projectPath,
      );
    }
    if (result.exitCode != 0) {
      throw Exception('Error al unstage de $filePath: ${result.stderr}');
    }
  }

  /// Descarta cambios del working tree (`git checkout --` / `git restore`).
  static Future<void> discardChanges(String projectPath, String filePath) async {
    final status = await getStatus(projectPath);
    GitFileChange? change;
    for (final c in status.changes) {
      if (c.path == filePath) {
        change = c;
        break;
      }
    }

    if (change?.kind == GitChangeKind.untracked) {
      final file = File('$projectPath/$filePath');
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }

    var result = await Process.run(
      'git',
      ['restore', '--', filePath],
      workingDirectory: projectPath,
    );
    if (result.exitCode != 0) {
      result = await Process.run(
        'git',
        ['checkout', '--', filePath],
        workingDirectory: projectPath,
      );
    }
    if (result.exitCode != 0) {
      throw Exception('Error al descartar $filePath: ${result.stderr}');
    }
  }

  /// Commit de lo que ya está en staging (no hace `git add .` automático).
  static Future<String> commitStaged(String projectPath, String message) async {
    final msg = message.trim();
    if (msg.isEmpty) {
      throw Exception('El mensaje de commit no puede estar vacío');
    }

    final result = await Process.run(
      'git',
      ['commit', '-m', msg],
      workingDirectory: projectPath,
    );

    if (result.exitCode == 0) {
      return result.stdout.toString().trim().isEmpty
          ? 'Commit realizado correctamente'
          : result.stdout.toString().trim();
    }
    throw Exception(
      result.stderr.toString().trim().isEmpty
          ? 'Error al hacer commit'
          : result.stderr.toString().trim(),
    );
  }

  /// Compatibilidad con GitSettingsScreen: stage (+files o `.`) y commit.
  static Future<String> commit({
    required String projectPath,
    required String message,
    List<String>? files,
  }) async {
    try {
      if (files != null && files.isNotEmpty) {
        for (final file in files) {
          await stageFile(projectPath, file);
        }
      } else {
        final result = await Process.run(
          'git',
          ['add', '.'],
          workingDirectory: projectPath,
        );
        if (result.exitCode != 0) {
          throw Exception('Error al agregar archivos: ${result.stderr}');
        }
      }

      return await commitStaged(projectPath, message);
    } catch (e) {
      throw Exception('Error al hacer commit: $e');
    }
  }

  static Future<String> pull(String projectPath, {String? remote, String? branch}) async {
    final remoteName = remote ?? 'origin';
    final branchName = branch ?? await getCurrentBranch(projectPath);

    final result = await Process.run(
      'git',
      ['pull', remoteName, branchName],
      workingDirectory: projectPath,
    );

    if (result.exitCode == 0) {
      final out = result.stdout.toString().trim();
      return out.isEmpty ? 'Pull realizado correctamente' : out;
    }
    throw Exception(
      result.stderr.toString().trim().isEmpty
          ? 'Error al hacer pull'
          : result.stderr.toString().trim(),
    );
  }

  static Future<String> push({
    required String projectPath,
    String? remote,
    String? branch,
  }) async {
    try {
      final config = await getGitConfig(projectPath);
      final remoteName = remote ?? 'origin';
      final branchName =
          branch ?? await getCurrentBranch(projectPath);
      final fallbackBranch =
          branchName.isEmpty ? (config?['branch'] ?? 'main') : branchName;

      final result = await Process.run(
        'git',
        ['push', remoteName, fallbackBranch],
        workingDirectory: projectPath,
      );

      if (result.exitCode == 0) {
        return 'Push realizado correctamente';
      } else {
        throw Exception(result.stderr);
      }
    } catch (e) {
      throw Exception('Error al hacer push: $e');
    }
  }

  /// Alias posicional pedido por la API SCM.
  static Future<String> pushRepo(String projectPath) =>
      push(projectPath: projectPath);

  static Future<String> getCurrentBranch(String projectPath) async {
    try {
      final result = await Process.run(
        'git',
        ['branch', '--show-current'],
        workingDirectory: projectPath,
      );
      if (result.exitCode == 0) {
        final name = result.stdout.toString().trim();
        if (name.isNotEmpty) return name;
      }
      // Detached HEAD u otros
      final rev = await Process.run(
        'git',
        ['rev-parse', '--abbrev-ref', 'HEAD'],
        workingDirectory: projectPath,
      );
      return rev.stdout.toString().trim();
    } catch (_) {
      return '';
    }
  }

  /// Compatibilidad legacy (mapa suelto).
  static Future<Map<String, dynamic>> getGitStatus(String projectPath) async {
    final status = await getStatus(projectPath);
    return {
      'hasChanges': status.hasChanges,
      'status': status.changes.map((c) => '${c.xy} ${c.path}').join('\n'),
      'branch': status.branch,
      if (status.error != null) 'error': status.error,
    };
  }

  /// Genera un mensaje convencional local a partir del diff/status (sin OpenAI).
  /// El panel puede sustituirlo con IA vía callback.
  static Future<String> suggestConventionalCommitMessage(String projectPath) async {
    final status = await getStatus(projectPath);
    if (!status.hasChanges) {
      return 'chore: update project files';
    }

    final paths = status.changes.map((c) => c.path).toList();
    final hasDelete = status.changes.any((c) => c.kind == GitChangeKind.deleted);
    final hasAdd = status.changes.any(
      (c) =>
          c.kind == GitChangeKind.added || c.kind == GitChangeKind.untracked,
    );
    final onlyDocs = paths.every(
      (p) =>
          p.endsWith('.md') ||
          p.contains('/docs/') ||
          p.startsWith('docs/'),
    );
    final onlyTests = paths.every(
      (p) => p.contains('test/') || p.endsWith('_test.dart'),
    );
    final onlyCi = paths.every(
      (p) =>
          p.contains('.github/') ||
          p.contains('codemagic') ||
          p.contains('fastlane'),
    );

    String type = 'chore';
    if (onlyDocs) {
      type = 'docs';
    } else if (onlyTests) {
      type = 'test';
    } else if (onlyCi) {
      type = 'ci';
    } else if (hasDelete && !hasAdd) {
      type = 'refactor';
    } else if (hasAdd) {
      type = 'feat';
    } else {
      type = 'fix';
    }

    final names = paths
        .map((p) => p.split('/').last)
        .toSet()
        .take(3)
        .join(', ');
    final extra = paths.length > 3 ? ' (+${paths.length - 3})' : '';
    return '$type: update $names$extra';
  }

  // ── Porcelain parsing ───────────────────────────────────────────

  static List<GitFileChange> _parsePorcelain(String raw) {
    final changes = <GitFileChange>[];
    for (final line in raw.split('\n')) {
      if (line.trim().isEmpty) continue;
      if (line.length < 3) continue;

      final xy = line.substring(0, 2);
      var rest = line.substring(2).trimLeft();

      String path;
      String? oldPath;
      if (rest.contains(' -> ')) {
        final parts = rest.split(' -> ');
        oldPath = parts.first.trim();
        path = parts.last.trim();
      } else {
        path = rest;
      }

      final x = xy[0];
      final y = xy[1];

      final isUntracked = xy == '??';
      final staged = !isUntracked && x != ' ' && x != '?';
      final unstaged = isUntracked || (y != ' ' && y != '?');

      final kind = isUntracked
          ? GitChangeKind.untracked
          : _kindFromCode(staged ? x : (y != ' ' ? y : x));

      changes.add(
        GitFileChange(
          path: path,
          oldPath: oldPath,
          kind: kind,
          staged: staged,
          unstaged: unstaged,
          xy: xy,
        ),
      );
    }
    return changes;
  }

  static GitChangeKind _kindFromCode(String code) {
    switch (code) {
      case 'M':
        return GitChangeKind.modified;
      case 'A':
        return GitChangeKind.added;
      case 'D':
        return GitChangeKind.deleted;
      case 'R':
        return GitChangeKind.renamed;
      case 'C':
        return GitChangeKind.copied;
      case 'U':
        return GitChangeKind.unmerged;
      case '!':
        return GitChangeKind.ignored;
      case '?':
        return GitChangeKind.untracked;
      default:
        return GitChangeKind.unknown;
    }
  }

  static String _getProjectKey(String projectPath) {
    return projectPath.hashCode.toString();
  }
}
