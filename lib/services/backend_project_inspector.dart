import 'dart:io';

/// Resultado de inspeccionar integración Firebase / Supabase en un proyecto.
class BackendInspectionResult {
  final String kind; // 'firebase' | 'supabase'
  final bool configured;
  final String statusLabel;
  final String? projectId;
  final List<String> evidence;
  final List<String> missingHints;

  const BackendInspectionResult({
    required this.kind,
    required this.configured,
    required this.statusLabel,
    this.projectId,
    this.evidence = const [],
    this.missingHints = const [],
  });
}

/// Detecta archivos/config reales de Firebase y Supabase en [projectPath].
class BackendProjectInspector {
  BackendProjectInspector._();

  static Future<BackendInspectionResult> inspectFirebase(
    String projectPath,
  ) async {
    final root = projectPath.replaceAll('\\', '/');
    final evidence = <String>[];
    final missing = <String>[];
    String? projectId;

    Future<bool> exists(String relative) async {
      final f = File('$root/$relative');
      final d = Directory('$root/$relative');
      return await f.exists() || await d.exists();
    }

    if (await exists('firebase.json')) {
      evidence.add('firebase.json');
    } else {
      missing.add('firebase.json');
    }

    if (await exists('.firebaserc')) {
      evidence.add('.firebaserc');
      try {
        final content = await File('$root/.firebaserc').readAsString();
        final match = RegExp(r'"default"\s*:\s*"([^"]+)"').firstMatch(content);
        projectId ??= match?.group(1);
      } catch (_) {}
    } else {
      missing.add('.firebaserc');
    }

    if (await exists('android/app/google-services.json')) {
      evidence.add('android/app/google-services.json');
      try {
        final content =
            await File('$root/android/app/google-services.json').readAsString();
        final match =
            RegExp(r'"project_id"\s*:\s*"([^"]+)"').firstMatch(content);
        projectId ??= match?.group(1);
      } catch (_) {}
    }

    if (await exists('ios/Runner/GoogleService-Info.plist')) {
      evidence.add('ios/Runner/GoogleService-Info.plist');
    }

    final pubspec = File('$root/pubspec.yaml');
    if (await pubspec.exists()) {
      final yaml = await pubspec.readAsString();
      if (yaml.contains('firebase_core')) {
        evidence.add('pubspec.yaml → firebase_core');
      } else {
        missing.add('dependencia firebase_core en pubspec.yaml');
      }
    }

    final configured = evidence.any(
      (e) =>
          e.contains('firebase.json') ||
          e.contains('.firebaserc') ||
          e.contains('google-services') ||
          e.contains('GoogleService-Info') ||
          e.contains('firebase_core'),
    );

    return BackendInspectionResult(
      kind: 'firebase',
      configured: configured,
      statusLabel: configured ? 'Configurado / detectado' : 'No configurado',
      projectId: projectId,
      evidence: evidence,
      missingHints: missing,
    );
  }

  static Future<BackendInspectionResult> inspectSupabase(
    String projectPath,
  ) async {
    final root = projectPath.replaceAll('\\', '/');
    final evidence = <String>[];
    final missing = <String>[];
    String? projectId;

    Future<bool> exists(String relative) async {
      final f = File('$root/$relative');
      final d = Directory('$root/$relative');
      return await f.exists() || await d.exists();
    }

    if (await exists('supabase/config.toml')) {
      evidence.add('supabase/config.toml');
      try {
        final content =
            await File('$root/supabase/config.toml').readAsString();
        final match = RegExp(r'project_id\s*=\s*"([^"]+)"').firstMatch(content);
        projectId ??= match?.group(1);
      } catch (_) {}
    } else {
      missing.add('supabase/config.toml');
    }

    for (final envName in ['.env', '.env.local', '.env.development']) {
      final envFile = File('$root/$envName');
      if (!await envFile.exists()) continue;
      try {
        final content = await envFile.readAsString();
        if (content.contains('SUPABASE_URL') ||
            content.contains('SUPABASE_ANON_KEY') ||
            content.contains('SUPABASE_KEY')) {
          evidence.add('$envName (SUPABASE_*)');
          final urlMatch =
              RegExp(r'SUPABASE_URL\s*=\s*(.+)').firstMatch(content);
          final url = urlMatch?.group(1)?.trim();
          if (url != null && url.isNotEmpty) {
            projectId ??= url;
          }
        }
      } catch (_) {}
    }
    if (!evidence.any((e) => e.contains('SUPABASE'))) {
      missing.add('.env con SUPABASE_URL / SUPABASE_ANON_KEY');
    }

    final pubspec = File('$root/pubspec.yaml');
    if (await pubspec.exists()) {
      final yaml = await pubspec.readAsString();
      if (yaml.contains('supabase_flutter') || yaml.contains('supabase:')) {
        evidence.add('pubspec.yaml → supabase_flutter');
      } else {
        missing.add('dependencia supabase_flutter en pubspec.yaml');
      }
    }

    final configured = evidence.isNotEmpty;

    return BackendInspectionResult(
      kind: 'supabase',
      configured: configured,
      statusLabel: configured ? 'Configurado / detectado' : 'No configurado',
      projectId: projectId,
      evidence: evidence,
      missingHints: missing,
    );
  }
}
