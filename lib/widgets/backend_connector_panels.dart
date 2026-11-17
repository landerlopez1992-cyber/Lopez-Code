import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/backend_project_inspector.dart';
import '../services/env_connections_service.dart';
import '../services/project_type_detector.dart';
import 'app_toast.dart';
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
  String? _hintMessage;
  bool _hintOk = true;
  bool _showAdvancedCli = false;
  bool _isFlutterProject = false;
  bool _saving = false;
  bool _savedInProject = false;

  @override
  void initState() {
    super.initState();
    _detectFlutter();
    _loadSavedConfig();
  }

  Future<void> _detectFlutter() async {
    final pubspec = File('${widget.projectPath}/pubspec.yaml');
    final isFlutter = await pubspec.exists();
    if (mounted) setState(() => _isFlutterProject = isFlutter);
  }

  Future<void> _loadSavedConfig() async {
    final snippet =
        await EnvConnectionsService.loadSavedFirebaseWebConfigSnippet(
      widget.projectPath,
    );
    if (!mounted || snippet == null || snippet.isEmpty) return;
    if (_configCtrl.text.trim().isNotEmpty) return;
    setState(() {
      _configCtrl.text = snippet;
      _savedInProject = true;
      _hintOk = true;
      _hintMessage =
          'Config ya guardada en el proyecto (.env + .voryxel/). '
          'El agente la verá cuando la necesite.';
    });
  }

  @override
  void dispose() {
    _configCtrl.dispose();
    super.dispose();
  }

  Future<void> _runInMacTerminal(String shellCommand) async {
    // Importante: usar comillas dobles de Dart para interpolar la ruta.
    final path = widget.projectPath.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final cmd = shellCommand.replaceAll('"', r'\"');
    final script =
        'tell application "Terminal"\n'
        'activate\n'
        'do script "cd \\"$path\\" && $cmd"\n'
        'end tell';
    await Process.start('osascript', ['-e', script]);
  }

  Future<void> _openConsoleAndGuide() async {
    await openExternalUrl('https://console.firebase.google.com');
    if (!mounted) return;
    setState(() {
      _hintOk = true;
      _hintMessage =
          '1) Crea/elige el proyecto en Firebase\n'
          '2) ⚙ Project settings → Your apps → Web </>\n'
          '3) Copia firebaseConfig { apiKey, projectId, … }\n'
          '4) Pégalo abajo → Guardar en el proyecto → Integrar';
    });
  }

  Future<void> _openInteractiveFirebaseLogin() async {
    try {
      await _runInMacTerminal('firebase login --reauth');
      if (!mounted) return;
      setState(() {
        _hintOk = true;
        _hintMessage =
            'Terminal debería ejecutar `firebase login` (login en el navegador).\n'
            'Eso solo autentica la CLI para deploy.\n'
            'Para conectar tu web HTML: pega firebaseConfig abajo.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hintOk = false;
        _hintMessage = 'No se pudo abrir Terminal: $e';
      });
    }
  }

  Future<void> _openFlutterFireInTerminal() async {
    try {
      await _runInMacTerminal('flutterfire configure');
      if (!mounted) return;
      setState(() {
        _hintOk = true;
        _hintMessage =
            'Terminal: `flutterfire configure` (solo Flutter).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hintOk = false;
        _hintMessage = 'No se pudo abrir Terminal: $e';
      });
    }
  }

  Future<bool> _saveToProject({bool closeOnSuccess = true}) async {
    final paste = _configCtrl.text.trim();
    if (paste.isEmpty) {
      setState(() {
        _hintOk = false;
        _hintMessage =
            'Pega el firebaseConfig completo de la Consola '
            '(apiKey, projectId, …).';
      });
      AppToast.warning(context, 'Nada que guardar: pega la config primero');
      return false;
    }

    setState(() => _saving = true);
    final result = await EnvConnectionsService.saveFirebaseWebConfig(
      widget.projectPath,
      paste,
    );
    if (!mounted) return false;
    setState(() {
      _saving = false;
      _hintOk = result.ok;
      _hintMessage = result.message;
      _savedInProject = result.ok;
    });
    if (result.ok) {
      AppToast.success(
        context,
        'Firebase guardado en el proyecto '
        '(${result.projectId ?? "ok"})',
      );
      if (closeOnSuccess && mounted) {
        Navigator.of(context).pop();
      }
    } else {
      AppToast.warning(context, result.message);
    }
    return result.ok;
  }

  Future<void> _integrateWithAgent() async {
    final paste = _configCtrl.text.trim();
    if (paste.isEmpty) {
      setState(() {
        _hintOk = false;
        _hintMessage =
            'Primero pega el firebaseConfig de la Consola.\n'
            'Sin eso el agente no tiene credenciales reales que integrar.';
      });
      AppToast.warning(
        context,
        'Pega firebaseConfig antes de integrar',
      );
      return;
    }

    // Persistir sin cerrar; cerramos nosotros al disparar el agente.
    final saved = await _saveToProject(closeOnSuccess: false);
    if (!saved || !mounted) return;

    final insp = widget.inspection;
    final buf = StringBuffer()
      ..writeln(
        'Verifica e integra Firebase AHORA.',
      )
      ..writeln('Estado previo: ${insp.statusLabel}.')
      ..writeln()
      ..writeln(
        '1) VERIFICA que se guardó bien lo esperado:',
      )
      ..writeln(
        '   - Lee `.env` (FIREBASE_API_KEY, FIREBASE_AUTH_DOMAIN, '
        'FIREBASE_PROJECT_ID, FIREBASE_STORAGE_BUCKET, '
        'FIREBASE_MESSAGING_SENDER_ID, FIREBASE_APP_ID) '
        'y `.voryxel/firebase_web_config.json`.',
      )
      ..writeln(
        '   - Confirma que coinciden con la config pegada '
        '(no inventes valores).',
      )
      ..writeln(
        '   - Si falta algo o no coincide, dilo claro y no sigas '
        'con datos inventados.',
      )
      ..writeln()
      ..writeln(
        '2) Si la verificación OK: conecta el SDK en el código '
        '(HTML: index.html / js; Flutter: firebase_core). '
        'Usa solo lo leído de esos archivos.',
      )
      ..writeln()
      ..writeln('Copia de referencia (la que el usuario pegó):')
      ..writeln('```')
      ..writeln(paste)
      ..writeln('```');
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
          Expanded(
            child: Text(
              'Conectar Firebase al proyecto',
              style: TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusChip(ok: insp.configured, label: insp.statusLabel),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CursorTheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: CursorTheme.primary.withValues(alpha: 0.45)),
                ),
                child: Text(
                  _savedInProject
                      ? 'Config guardada en este proyecto.\n'
                          'Queda en `.env` (FIREBASE_*) y '
                          '`.voryxel/firebase_web_config.json` para que el '
                          'agente la use cuando haga falta.\n\n'
                          'Puedes volver a pegar para actualizarla, o integrar '
                          'en el código con el botón azul.'
                      : '1) Pega el firebaseConfig de la Consola\n'
                          '2) «Guardar en el proyecto» → queda disponible '
                          'siempre para el agente\n'
                          '3) «Integrar en el código» → el agente lo cablea '
                          'en index.html / SDK\n\n'
                          'No es login mágico del IDE. Login CLI solo para deploy.',
                  style: const TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _openConsoleAndGuide,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('1. Abrir Consola Firebase (copiar config)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CursorTheme.textPrimary,
                  side: const BorderSide(color: CursorTheme.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '2. Pega aquí el firebaseConfig',
                style: TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _configCtrl,
                maxLines: 8,
                style: const TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 12,
                  fontFamily: 'Menlo',
                ),
                decoration: InputDecoration(
                  hintText:
                      'const firebaseConfig = {\n'
                      '  apiKey: "...",\n'
                      '  authDomain: "...",\n'
                      '  projectId: "...",\n'
                      '  ...\n'
                      '};',
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
              const SizedBox(height: 8),
              InkWell(
                onTap: () =>
                    setState(() => _showAdvancedCli = !_showAdvancedCli),
                child: Row(
                  children: [
                    Icon(
                      _showAdvancedCli
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: CursorTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Avanzado: CLI / deploy (opcional)',
                      style: TextStyle(
                        color: CursorTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (_showAdvancedCli) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _openInteractiveFirebaseLogin,
                      icon: const Icon(Icons.login, size: 16),
                      label: const Text('Login CLI (Terminal)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CursorTheme.textPrimary,
                        side: const BorderSide(color: CursorTheme.border),
                      ),
                    ),
                    if (_isFlutterProject)
                      OutlinedButton.icon(
                        onPressed: _openFlutterFireInTerminal,
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
              ],
              if (_hintMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: CursorTheme.background,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _hintOk
                          ? CursorTheme.border
                          : const Color(0xFFE57373),
                    ),
                  ),
                  child: SelectableText(
                    _hintMessage!,
                    style: TextStyle(
                      color: _hintOk
                          ? CursorTheme.textSecondary
                          : const Color(0xFFEF9A9A),
                      fontSize: 11.5,
                      height: 1.4,
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Cerrar',
            style: TextStyle(color: CursorTheme.textSecondary),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _saving ? null : _saveToProject,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _savedInProject ? Icons.check : Icons.save_outlined,
                  size: 16,
                ),
          label: Text(
            _savedInProject ? 'Guardado' : 'Guardar en el proyecto',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: CursorTheme.textPrimary,
            side: const BorderSide(color: CursorTheme.border),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _integrateWithAgent,
          style: ElevatedButton.styleFrom(
            backgroundColor: CursorTheme.primary,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.auto_fix_high, size: 16),
          label: const Text('Integrar en el código'),
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
