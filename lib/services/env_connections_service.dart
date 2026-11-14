import 'dart:async';
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
