import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/backend_project_inspector.dart';
import '../services/env_connections_service.dart';
import '../services/project_type_detector.dart';
import 'cursor_theme.dart';

Future<void> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Panel funcional de conexión a Supabase (barra superior del IDE).
class SupabaseConnectorDialog extends StatefulWidget {
  final String projectPath;
  final BackendInspectionResult inspection;
  final void Function(String message) onAskAgent;

  const SupabaseConnectorDialog({
    super.key,
    required this.projectPath,
    required this.inspection,
    required this.onAskAgent,
  });

  @override
  State<SupabaseConnectorDialog> createState() =>
      _SupabaseConnectorDialogState();
}

class _SupabaseConnectorDialogState extends State<SupabaseConnectorDialog> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _obscureKey = true;
  bool _testing = false;
  bool _saving = false;
  String? _testMessage;
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final url = await EnvConnectionsService.readEnvValue(
      widget.projectPath,
      'SUPABASE_URL',
    );
    final key = await EnvConnectionsService.readEnvValue(
      widget.projectPath,
      'SUPABASE_ANON_KEY',
    );
    if (!mounted) return;
    setState(() {
      if (url != null) _urlCtrl.text = url;
      if (key != null) _keyCtrl.text = key;
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testMessage = null;
      _testOk = null;
    });
    final result = await EnvConnectionsService.testSupabaseConnection(
      url: _urlCtrl.text,
      anonKey: _keyCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = result.ok;
      _testMessage = result.message;
    });
  }

  Future<void> _saveAndIntegrate() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (url.isEmpty || key.isEmpty) {
      setState(() {
        _testOk = false;
        _testMessage = 'Completa SUPABASE_URL y SUPABASE_ANON_KEY';
      });
      return;
    }

    setState(() => _saving = true);
    try {
      await EnvConnectionsService.upsertEnvKeys(
        widget.projectPath,
        {
          'SUPABASE_URL': url,
          'SUPABASE_ANON_KEY': key,
        },
      );
      await EnvConnectionsService.ensureEnvInGitignore(widget.projectPath);

      final projectType =
          await ProjectTypeDetector.detectProjectType(widget.projectPath);
      final isFlutter = projectType == ProjectType.flutter;
      final isWeb = projectType == ProjectType.html ||
          projectType == ProjectType.react ||
          projectType == ProjectType.vue ||
          projectType == ProjectType.vite ||
          projectType == ProjectType.nextjs;

      final agentMsg = StringBuffer()
        ..writeln(
          'Integra Supabase de verdad en este proyecto (credenciales ya '
          'están en `.env`: SUPABASE_URL y SUPABASE_ANON_KEY).',
        )
        ..writeln('Tipo de proyecto detectado: ${projectType.name}.')
        ..writeln(
          'Estado previo: ${widget.inspection.statusLabel}. '
          'Evidencia: ${widget.inspection.evidence.isEmpty ? "(ninguna)" : widget.inspection.evidence.join(", ")}.',
        )
        ..writeln()
        ..writeln('Haz esto ahora:');
      if (isFlutter) {
        agentMsg.writeln(
          '1) Añade `supabase_flutter` en pubspec.yaml y ejecuta `flutter pub get`.',
        );
        agentMsg.writeln(
          '2) Crea un cliente (p. ej. `lib/services/supabase_service.dart`) '
          'que lea SUPABASE_URL / SUPABASE_ANON_KEY desde .env o '
          'String.fromEnvironment / flutter_dotenv — NUNCA hardcodees las keys.',
        );
        agentMsg.writeln(
          '3) Inicializa Supabase en main.dart y deja un ejemplo de query real.',
        );
      } else if (isWeb) {
        agentMsg.writeln(
          '1) Usa el cliente JS `@supabase/supabase-js` (CDN o npm según el stack).',
        );
        agentMsg.writeln(
          '2) Lee URL/anon key desde .env / import.meta.env / proceso — '
          'NUNCA las pegues en el HTML/JS en claro si puedes evitarlo; '
          'usa el anon key (pública) correctamente.',
        );
        agentMsg.writeln(
          '3) Deja un ejemplo de fetch REST o del cliente JS funcionando.',
        );
      } else {
        agentMsg.writeln(
          '1) Configura el cliente REST/SDK adecuado al stack del proyecto.',
        );
        agentMsg.writeln(
          '2) Lee credenciales desde .env — sin secretos hardcodeados.',
        );
      }
      agentMsg.writeln(
        '4) Si falta algo en el dashboard, usa open_external_url '
        '(https://supabase.com/dashboard) y guíame.',
      );
      agentMsg.writeln(
        'No inventes datos simulados: conexión real con las vars de .env.',
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onAskAgent(agentMsg.toString());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _testOk = false;
        _testMessage = 'Error al guardar .env: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final insp = widget.inspection;
    return AlertDialog(
      backgroundColor: CursorTheme.surface,
      title: const Row(
        children: [
          Icon(Icons.cloud, color: CursorTheme.primary, size: 20),
          SizedBox(width: 8),
          Text(
            'Supabase Connector',
            style: TextStyle(
              color: CursorTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusChip(
                ok: insp.configured,
                label: insp.statusLabel,
              ),
              if (insp.evidence.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Detectado: ${insp.evidence.join(', ')}',
                  style: const TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _LabeledField(
                label: 'SUPABASE_URL',
                controller: _urlCtrl,
                hint: 'https://xxxx.supabase.co',
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'SUPABASE_ANON_KEY',
                controller: _keyCtrl,
                hint: 'eyJhbGciOi…',
                obscure: _obscureKey,
                suffix: IconButton(
                  icon: Icon(
                    _obscureKey ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                    color: CursorTheme.textSecondary,
                  ),
                  onPressed: () =>
                      setState(() => _obscureKey = !_obscureKey),
                ),
              ),
              const SizedBox(height: 12),
              if (_testMessage != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_testOk == true
                            ? const Color(0xFF1B5E20)
                            : const Color(0xFF5D1A1A))
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _testOk == true
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFE57373),
                    ),
                  ),
                  child: Text(
                    _testMessage!,
                    style: TextStyle(
                      color: _testOk == true
                          ? const Color(0xFFA5D6A7)
                          : const Color(0xFFEF9A9A),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => openExternalUrl(
                      'https://supabase.com/dashboard',
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Abrir Dashboard'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CursorTheme.textPrimary,
                      side: const BorderSide(color: CursorTheme.border),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering, size: 16),
                    label: Text(_testing ? 'Probando…' : 'Probar Conexión'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CursorTheme.textPrimary,
                      side: const BorderSide(color: CursorTheme.border),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cerrar',
            style: TextStyle(color: CursorTheme.textSecondary),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _saveAndIntegrate,
          style: ElevatedButton.styleFrom(
            backgroundColor: CursorTheme.primary,
            foregroundColor: Colors.white,
          ),
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.auto_fix_high, size: 16),
          label: Text(
            _saving ? 'Guardando…' : 'Guardar e Integrar en Proyecto',
          ),
        ),
      ],
    );
  }
}

/// Panel funcional de conexión a Firebase (barra superior del IDE).
class FirebaseConnectorDialog extends StatefulWidget {
  final String projectPath;
  final BackendInspectionResult inspection;
  final void Function(String message) onAskAgent;
  final VoidCallback? onDeploy;

  const FirebaseConnectorDialog({
    super.key,
    required this.projectPath,
    required this.inspection,
    required this.onAskAgent,
    this.onDeploy,
  });

  @override
  State<FirebaseConnectorDialog> createState() =>
      _FirebaseConnectorDialogState();
}

class _FirebaseConnectorDialogState extends State<FirebaseConnectorDialog> {
  final _configCtrl = TextEditingController();
  bool _runningCli = false;
  String? _cliMessage;

  @override
  void dispose() {
    _configCtrl.dispose();
    super.dispose();
  }

  Future<void> _runInProject(String command) async {
    setState(() {
      _runningCli = true;
      _cliMessage = 'Ejecutando: $command';
    });
    try {
      final parts = command.split(' ');
      final result = await Process.run(
        parts.first,
        parts.skip(1).toList(),
        workingDirectory: widget.projectPath,
        runInShell: true,
      );
      if (!mounted) return;
      final out =
          '${result.stdout}\n${result.stderr}'.trim().replaceAll('\r', '');
      final snippet = out.length > 400 ? '${out.substring(0, 400)}…' : out;
      setState(() {
        _runningCli = false;
        _cliMessage = result.exitCode == 0
            ? '✅ OK (exit 0)\n$snippet'
            : '❌ exit ${result.exitCode}\n$snippet';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _runningCli = false;
        _cliMessage =
            '❌ No se pudo ejecutar. ¿Firebase CLI instalado?\n$e';
      });
    }
  }

  void _integrateWithAgent() {
    final paste = _configCtrl.text.trim();
    final insp = widget.inspection;
    final buf = StringBuffer()
      ..writeln(
        'Configura Firebase de verdad en este proyecto '
        '(firebase_core / FlutterFire o config Web según el stack).',
      )
      ..writeln('Estado: ${insp.statusLabel}.')
      ..writeln('Project ID detectado: ${insp.projectId ?? "(ninguno)"}.')
      ..writeln(
        'Evidencia: ${insp.evidence.isEmpty ? "(ninguna)" : insp.evidence.join(", ")}.',
      )
      ..writeln(
        'Falta: ${insp.missingHints.isEmpty ? "(nada crítico)" : insp.missingHints.join(", ")}.',
      );
    if (paste.isNotEmpty) {
      buf.writeln();
      buf.writeln(
        'El usuario pegó esta configuración (úsalá; no inventes otras keys):',
      );
      buf.writeln('```');
      buf.writeln(paste);
      buf.writeln('```');
    } else {
      buf.writeln();
      buf.writeln(
        'Si faltan credenciales o login, usa open_external_url '
        '(https://console.firebase.google.com) y/o execute_command '
        '(`firebase login`, `flutterfire configure`) y guíame paso a paso.',
      );
    }
    buf.writeln(
      'Escribe el código real de inicialización. Nunca datos simulados/hardcoded falsos.',
    );
    Navigator.of(context).pop();
    widget.onAskAgent(buf.toString());
  }

  @override
  Widget build(BuildContext context) {
    final insp = widget.inspection;
    final hasFirebaseJson =
        insp.evidence.any((e) => e.contains('firebase.json'));

    return AlertDialog(
      backgroundColor: CursorTheme.surface,
      title: const Row(
        children: [
          Icon(
            Icons.local_fire_department,
            color: CursorTheme.primary,
            size: 20,
          ),
          SizedBox(width: 8),
          Text(
            'Firebase Connector',
            style: TextStyle(
              color: CursorTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusChip(ok: insp.configured, label: insp.statusLabel),
              if (insp.projectId != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Project ID: ${insp.projectId}',
                  style: const TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              if (insp.evidence.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Detectado: ${insp.evidence.join(', ')}',
                  style: const TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                'Pegar configuración Web / Flutter (opcional)',
                style: TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _configCtrl,
                maxLines: 6,
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 12,
                  fontFamily: 'Menlo',
                ),
                decoration: InputDecoration(
                  hintText:
                      'firebaseConfig = { apiKey: "...", projectId: "..." }\n'
                      'o options de FlutterFire',
                  hintStyle: TextStyle(
                    color: CursorTheme.textDisabled.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                  filled: true,
                  fillColor: CursorTheme.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: CursorTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: CursorTheme.border),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => openExternalUrl(
                      'https://console.firebase.google.com',
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Abrir Consola Firebase'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CursorTheme.textPrimary,
                      side: const BorderSide(color: CursorTheme.border),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _runningCli
                        ? null
                        : () => _runInProject('firebase login'),
                    icon: const Icon(Icons.login, size: 16),
                    label: const Text('firebase login'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CursorTheme.textPrimary,
                      side: const BorderSide(color: CursorTheme.border),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _runningCli
                        ? null
                        : () => _runInProject('flutterfire configure'),
                    icon: const Icon(Icons.settings_suggest, size: 16),
                    label: const Text('flutterfire configure'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CursorTheme.textPrimary,
                      side: const BorderSide(color: CursorTheme.border),
                    ),
                  ),
                  if (hasFirebaseJson && widget.onDeploy != null)
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onDeploy!();
                      },
                      icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                      label: const Text('firebase deploy'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CursorTheme.textPrimary,
                        side: const BorderSide(color: CursorTheme.border),
                      ),
                    ),
                ],
              ),
              if (_cliMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: CursorTheme.background,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: CursorTheme.border),
                  ),
                  child: SelectableText(
                    _cliMessage!,
                    style: const TextStyle(
                      color: CursorTheme.textSecondary,
                      fontSize: 11,
                      fontFamily: 'Menlo',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cerrar',
            style: TextStyle(color: CursorTheme.textSecondary),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _integrateWithAgent,
          style: ElevatedButton.styleFrom(
            backgroundColor: CursorTheme.primary,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.auto_fix_high, size: 16),
          label: const Text('Integrar con Agente AI'),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool ok;
  final String label;

  const _StatusChip({required this.ok, required this.label});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (ok ? const Color(0xFF1B5E20) : const Color(0xFF4E342E))
              .withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: ok ? const Color(0xFF66BB6A) : const Color(0xFFFFB74D),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: ok ? const Color(0xFFA5D6A7) : const Color(0xFFFFE0B2),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final Widget? suffix;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: CursorTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(
            color: CursorTheme.textPrimary,
            fontSize: 13,
            fontFamily: 'Menlo',
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: CursorTheme.textDisabled.withValues(alpha: 0.8),
              fontSize: 12,
            ),
            filled: true,
            fillColor: CursorTheme.background,
            suffixIcon: suffix,
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
