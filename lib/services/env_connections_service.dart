import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Lee / escribe `.env` del proyecto abierto de forma segura.
///
/// En [workspace_state] y prompts al agente **solo** se exponen nombres de
/// claves (nunca valores secretos).
class EnvConnectionsService {
  EnvConnectionsService._();

  static const List<String> _envFileNames = [
    '.env',
    '.env.local',
    '.env.development',
  ];

  /// Nombres de variables definidas en `.env*` (sin valores).
  static Future<List<String>> listEnvKeyNames(String projectPath) async {
    final keys = <String>{};
    final root = projectPath.replaceAll('\\', '/');
    for (final name in _envFileNames) {
      final file = File('$root/$name');
      if (!await file.exists()) continue;
      try {
        final content = await file.readAsString();
        for (final line in content.split('\n')) {
          final key = _parseKeyName(line);
          if (key != null) keys.add(key);
        }
      } catch (_) {}
    }
    final sorted = keys.toList()..sort();
    return sorted;
  }

  /// Bloque seguro para `<workspace_state>` (solo nombres).
  static Future<String> toWorkspaceBlock(String? projectPath) async {
    if (projectPath == null || projectPath.trim().isEmpty) {
      return 'env_keys: (no project)\n';
    }
    try {
      final keys = await listEnvKeyNames(projectPath);
      if (keys.isEmpty) {
        return 'env_keys: (none — no .env or empty)\n'
            'env_hint: Si el usuario pide Supabase/Firebase/API, crea .env '
            'con las claves reales y NUNCA hardcodees secretos.\n';
      }
      final buf = StringBuffer();
      buf.writeln('env_keys: ${keys.length} (names only, values hidden)');
      buf.writeln('<env_key_names>');
      for (final k in keys) {
        buf.writeln('- $k');
      }
      buf.writeln('</env_key_names>');
      final firebaseKeys =
          keys.where((k) => k.startsWith('FIREBASE_')).toList();
      if (firebaseKeys.isNotEmpty) {
        buf.writeln(
          'firebase_web_config: saved (.env FIREBASE_* + '
          '.voryxel/firebase_web_config.json). '
          'Al integrar Firebase, LEE esos valores — no inventes apiKey.',
        );
      }
      return buf.toString();
    } catch (e) {
      return 'env_keys: (error: $e)\n';
    }
  }

  /// Lee un valor concreto (solo para UI del IDE; no enviar al LLM).
  static Future<String?> readEnvValue(
    String projectPath,
    String key, {
    String preferredFile = '.env',
  }) async {
    final root = projectPath.replaceAll('\\', '/');
    for (final name in [preferredFile, ..._envFileNames]) {
      final file = File('$root/$name');
      if (!await file.exists()) continue;
      try {
        final map = _parseEnvMap(await file.readAsString());
        final v = map[key];
        if (v != null && v.isNotEmpty) return v;
      } catch (_) {}
    }
    return null;
  }

  /// Crea/actualiza claves en `.env` (merge; no borra otras).
  static Future<String> upsertEnvKeys(
    String projectPath,
    Map<String, String> updates, {
    String fileName = '.env',
  }) async {
    final root = projectPath.replaceAll('\\', '/');
    final file = File('$root/$fileName');
    final existing = <String, String>{};
    final order = <String>[];
    final comments = <String>[];

    if (await file.exists()) {
      final raw = await file.readAsString();
      for (final line in raw.split('\n')) {
        final trimmed = line.trimRight();
        if (trimmed.trim().isEmpty || trimmed.trim().startsWith('#')) {
          comments.add(trimmed);
          continue;
        }
        final eq = trimmed.indexOf('=');
        if (eq <= 0) {
          comments.add(trimmed);
          continue;
        }
        final k = trimmed.substring(0, eq).trim();
        var v = trimmed.substring(eq + 1).trim();
        if ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'"))) {
          v = v.substring(1, v.length - 1);
        }
        existing[k] = v;
        if (!order.contains(k)) order.add(k);
      }
    }

    for (final entry in updates.entries) {
      final k = entry.key.trim();
      if (k.isEmpty) continue;
      existing[k] = entry.value.trim();
      if (!order.contains(k)) order.add(k);
    }

    final buf = StringBuffer();
    if (comments.isNotEmpty &&
        comments.every((c) => c.trim().isEmpty || c.trim().startsWith('#'))) {
      for (final c in comments) {
        if (c.trim().isNotEmpty) buf.writeln(c);
      }
      if (buf.isNotEmpty) buf.writeln();
    } else {
      buf.writeln('# Credenciales locales — no subir a git');
      buf.writeln();
    }

    for (final k in order) {
      final v = existing[k] ?? '';
      final needsQuote = v.contains(' ') || v.contains('#') || v.contains('=');
      buf.writeln(needsQuote ? '$k="$v"' : '$k=$v');
    }

    await file.writeAsString(buf.toString());
    return file.path;
  }

  /// Asegura que `.env` (y variantes) estén en `.gitignore`.
  static Future<bool> ensureEnvInGitignore(String projectPath) async {
    final root = projectPath.replaceAll('\\', '/');
    final file = File('$root/.gitignore');
    const patterns = ['.env', '.env.*', '!.env.example'];
    String content = '';
    if (await file.exists()) {
      content = await file.readAsString();
    }
    final lower = content.toLowerCase();
    final missing = <String>[];
    for (final p in patterns) {
      if (!lower.contains(p.toLowerCase())) missing.add(p);
    }
    if (missing.isEmpty) return false;

    final buf = StringBuffer(content.trimRight());
    if (buf.isNotEmpty) buf.writeln();
    buf.writeln();
    buf.writeln('# Secrets / local env (Voryxel Code)');
    for (final p in missing) {
      buf.writeln(p);
    }
    await file.writeAsString('$buf\n');
    return true;
  }

  /// Prueba real: `GET $url/rest/v1/` con header `apikey`.
  static Future<SupabaseConnectionTestResult> testSupabaseConnection({
    required String url,
    required String anonKey,
  }) async {
    final cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleaned.isEmpty || anonKey.trim().isEmpty) {
      return const SupabaseConnectionTestResult(
        ok: false,
        statusCode: null,
        message: 'Faltan SUPABASE_URL o SUPABASE_ANON_KEY',
      );
    }
    if (!cleaned.startsWith('http://') && !cleaned.startsWith('https://')) {
      return const SupabaseConnectionTestResult(
        ok: false,
        statusCode: null,
        message: 'La URL debe empezar por https://',
      );
    }

    final uri = Uri.parse('$cleaned/rest/v1/');
    try {
      final response = await http
          .get(
            uri,
            headers: {
              'apikey': anonKey.trim(),
              'Authorization': 'Bearer ${anonKey.trim()}',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 12));

      // PostgREST responde 200 (lista) o 401/403 si la key es inválida.
      final code = response.statusCode;
      if (code >= 200 && code < 300) {
        return SupabaseConnectionTestResult(
          ok: true,
          statusCode: code,
          message: 'Conexión OK (HTTP $code) → ${uri.host}',
        );
      }
      if (code == 401 || code == 403) {
        return SupabaseConnectionTestResult(
          ok: false,
          statusCode: code,
          message: 'HTTP $code: anon key rechazada o sin permisos',
        );
      }
      // Algunos proyectos responden 404 en /rest/v1/ vacío pero el host vive.
      if (code == 404) {
        return SupabaseConnectionTestResult(
          ok: true,
          statusCode: code,
          message:
              'Host alcanzable (HTTP 404 en /rest/v1/). Revisa tablas/API; la URL responde.',
        );
      }
      return SupabaseConnectionTestResult(
        ok: false,
        statusCode: code,
        message: 'HTTP $code: ${response.body.length > 120 ? '${response.body.substring(0, 120)}…' : response.body}',
      );
    } on SocketException catch (e) {
      return SupabaseConnectionTestResult(
        ok: false,
        statusCode: null,
        message: 'Sin red / DNS: $e',
      );
    } on TimeoutException {
      return const SupabaseConnectionTestResult(
        ok: false,
        statusCode: null,
        message: 'Timeout (12s) al contactar Supabase',
      );
    } catch (e) {
      return SupabaseConnectionTestResult(
        ok: false,
        statusCode: null,
        message: 'Error: $e',
      );
    }
  }

  static String? _parseKeyName(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    final eq = trimmed.indexOf('=');
    if (eq <= 0) return null;
    final key = trimmed.substring(0, eq).trim();
    if (key.isEmpty || !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
      return null;
    }
    return key;
  }

  static Map<String, String> _parseEnvMap(String content) {
    final map = <String, String>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final k = trimmed.substring(0, eq).trim();
      var v = trimmed.substring(eq + 1).trim();
      if ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1);
      }
      map[k] = v;
    }
    return map;
  }

  /// Campos típicos del firebaseConfig Web.
  static const List<String> firebaseWebFields = [
    'apiKey',
    'authDomain',
    'projectId',
    'storageBucket',
    'messagingSenderId',
    'appId',
    'measurementId',
  ];

  static String firebaseEnvKey(String field) {
    // apiKey → FIREBASE_API_KEY
    final snake = field
        .replaceAllMapped(
          RegExp(r'([A-Z])'),
          (m) => '_${m.group(1)}',
        )
        .toUpperCase();
    return 'FIREBASE_$snake';
  }

  /// Extrae pares del bloque pegado (JS/JSON).
  static Map<String, String> parseFirebaseWebConfig(String paste) {
    final out = <String, String>{};
    for (final field in firebaseWebFields) {
      final re = RegExp(
        '''['"]?$field['"]?\\s*:\\s*['"]([^'"]+)['"]''',
        caseSensitive: false,
      );
      final m = re.firstMatch(paste);
      final v = m?.group(1)?.trim();
      if (v != null && v.isNotEmpty && v != '...') {
        out[field] = v;
      }
    }
    return out;
  }

  /// Guarda config Web en `.env` + `.voryxel/firebase_web_config.json`
  /// (gitignore). El agente ve los nombres FIREBASE_* en workspace_state.
  static Future<FirebaseSaveResult> saveFirebaseWebConfig(
    String projectPath,
    String pastedText,
  ) async {
    final parsed = parseFirebaseWebConfig(pastedText);
    if (parsed.isEmpty) {
      return const FirebaseSaveResult(
        ok: false,
        message:
            'No se detectó firebaseConfig. Pega el objeto completo '
            '(apiKey, authDomain, projectId, …).',
        keys: [],
      );
    }
    if (!parsed.containsKey('apiKey') || !parsed.containsKey('projectId')) {
      return FirebaseSaveResult(
        ok: false,
        message:
            'Faltan campos clave. Pegaste solo un fragmento. '
            'Copia TODO el bloque (incluye apiKey y projectId). '
            'Detectado: ${parsed.keys.join(", ")}',
        keys: parsed.keys.toList(),
      );
    }

    final root = projectPath.replaceAll('\\', '/');
    final envUpdates = <String, String>{};
    for (final e in parsed.entries) {
      envUpdates[firebaseEnvKey(e.key)] = e.value;
    }
    await upsertEnvKeys(root, envUpdates);
    await ensureEnvInGitignore(root);

    final voryxelDir = Directory('$root/.voryxel');
    if (!await voryxelDir.exists()) {
      await voryxelDir.create(recursive: true);
    }
    final jsonFile = File('$root/.voryxel/firebase_web_config.json');
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        ...parsed,
        '_savedAt': DateTime.now().toIso8601String(),
        '_note':
            'Credenciales Web Firebase. No subir a git. '
            'El agente debe leer FIREBASE_* de .env o este archivo.',
      }),
    );

    // Asegurar .voryxel/ en gitignore
    final gi = File('$root/.gitignore');
    var giContent = await gi.exists() ? await gi.readAsString() : '';
    if (!giContent.toLowerCase().contains('.voryxel')) {
      final buf = StringBuffer(giContent.trimRight());
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln();
      buf.writeln('# Voryxel local secrets');
      buf.writeln('.voryxel/');
      await gi.writeAsString('$buf\n');
    }

    return FirebaseSaveResult(
      ok: true,
      message:
          'Guardado en .env (${envUpdates.keys.join(", ")}) '
          'y .voryxel/firebase_web_config.json. '
          'El agente verá las claves FIREBASE_* en el contexto.',
      keys: envUpdates.keys.toList()..sort(),
      projectId: parsed['projectId'],
    );
  }

  /// Carga config guardada (para rellenar el cuadro del conector).
  static Future<String?> loadSavedFirebaseWebConfigSnippet(
    String projectPath,
  ) async {
    final root = projectPath.replaceAll('\\', '/');
    final jsonFile = File('$root/.voryxel/firebase_web_config.json');
    if (await jsonFile.exists()) {
      try {
        final map =
            jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
        final buf = StringBuffer('const firebaseConfig = {\n');
        for (final field in firebaseWebFields) {
          final v = map[field]?.toString();
          if (v == null || v.isEmpty) continue;
          buf.writeln('  $field: "$v",');
        }
        buf.writeln('};');
        return buf.toString();
      } catch (_) {}
    }
    // Fallback desde .env
    final envMap = <String, String>{};
    for (final field in firebaseWebFields) {
      final v = await readEnvValue(root, firebaseEnvKey(field));
      if (v != null && v.isNotEmpty) envMap[field] = v;
    }
    if (envMap.isEmpty) return null;
    final buf = StringBuffer('const firebaseConfig = {\n');
    for (final e in envMap.entries) {
      buf.writeln('  ${e.key}: "${e.value}",');
    }
    buf.writeln('};');
    return buf.toString();
  }
}

class FirebaseSaveResult {
  final bool ok;
  final String message;
  final List<String> keys;
  final String? projectId;

  const FirebaseSaveResult({
    required this.ok,
    required this.message,
    required this.keys,
    this.projectId,
  });
}

class SupabaseConnectionTestResult {
  final bool ok;
  final int? statusCode;
  final String message;

  const SupabaseConnectionTestResult({
    required this.ok,
    required this.statusCode,
    required this.message,
  });
}
