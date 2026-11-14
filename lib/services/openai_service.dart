import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';
import '../models/agent_live_step.dart';
import '../models/problem_item.dart';
import 'web_navigation_service.dart';
import 'run_debug_service.dart';
import 'project_protection_service.dart';
import 'backup_service.dart';
import 'codebase_search_service.dart';
import 'project_rules_service.dart';
import 'debug_console_service.dart';
import 'advanced_debugging_service.dart';
import 'platform_service.dart';
import 'settings_service.dart';
import 'agent_activity_service.dart';
import 'agent_diff_review_service.dart';
import 'inspector_selection_service.dart';
import 'project_platform_support.dart';
import 'env_connections_service.dart';

typedef AgentStepProgressCallback = void Function(
  String statusText, {
  String? detail,
  AgentLiveStep? card,
});

class OpenAIService {
  final String apiKey;
  final String baseUrl = 'https://api.openai.com/v1';
  String model; // Modelo configurable

  // Cliente HTTP reutilizable con configuración optimizada
  http.Client? _httpClient;
  bool _isCancelled = false;

  OpenAIService({required this.apiKey, this.model = 'gpt-4.1'}) {
    _httpClient = http.Client();
  }

  // ✅ GETTER: Obtener cliente HTTP, crearlo si no existe
  http.Client get httpClient {
    if (_httpClient == null) {
      _httpClient = http.Client();
    }
    return _httpClient!;
  }

  /// Cancela la petición actual
  void cancelRequest() {
    print('🛑 OpenAIService: Cancelando petición...');
    _isCancelled = true;
    try {
      _httpClient?.close();
    } catch (e) {
      print('⚠️ Error al cerrar cliente HTTP: $e');
    }
    // ✅ FIX: Reiniciar cliente creando uno nuevo
    _httpClient = null; // Liberar referencia
    _httpClient = http.Client(); // Crear nuevo cliente
    print('✅ OpenAIService: Petición cancelada y cliente reiniciado');
  }

  // Método para cambiar el modelo
  void setModel(String newModel) {
    model = newModel;
    print('🔄 OpenAI modelo actualizado a: $newModel');
  }

  // Cerrar el cliente cuando ya no se necesite
  void dispose() {
    _httpClient?.close();
    _httpClient = null;
  }

  // Callback para notificar sobre operaciones de archivos.
  // [line] = línea 1-based a enfocar en el editor (edit_file).
  void Function(String operation, String filePath, {int? line})? onFileOperation;

  // Callback para acciones pendientes que requieren confirmación
  Function(List<Map<String, dynamic>> pendingActions)? onPendingActions;

  // ✅ NUEVO: Callback para tokens usados
  Function(int)? onTokensUsed;

  /// Progreso de pasos del Agent Loop (timeline + tarjetas tipo Cursor).
  AgentStepProgressCallback? onStepProgress;

  /// Control de botones del IDE (set_platform / run_app / hot_restart / stop_app).
  Future<String> Function(
    String action, {
    Map<String, dynamic>? args,
  })? onIdeControl;

  /// Archivos leídos (o abiertos en workspace_state) en el turno actual.
  /// edit_file solo se permite sobre rutas presentes aquí.
  final Set<String> _readFilesInTurn = {};

  List<Map<String, dynamic>> get _toolDefinitions => [
    {
      'type': 'function',
      'function': {
        'name': 'edit_file',
        'description':
            'Edita quirúrgicamente un archivo. Usa read_file primero y proporciona un bloque existente exacto y suficientemente único.',
        'parameters': {
          'type': 'object',
          'properties': {
            'file_path': {
              'type': 'string',
              'description': 'Ruta relativa del archivo dentro del proyecto.',
            },
            'search_block': {
              'type': 'string',
              'description':
                  'Fragmento exacto existente, con contexto suficiente para ser único.',
            },
            'replace_block': {
              'type': 'string',
              'description': 'Código que reemplazará exactamente search_block.',
            },
          },
          'required': ['file_path', 'search_block', 'replace_block'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'write_file',
        'description':
            'Reescribe el contenido completo de un archivo. Úsala solo cuando una edición quirúrgica no sea apropiada.',
        'parameters': {
          'type': 'object',
          'properties': {
            'file_path': {'type': 'string'},
            'content': {'type': 'string'},
          },
          'required': ['file_path', 'content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_file',
        'description': 'Crea un archivo nuevo dentro del proyecto.',
        'parameters': {
          'type': 'object',
          'properties': {
            'file_path': {'type': 'string'},
            'content': {'type': 'string'},
          },
          'required': ['file_path', 'content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_file',
        'description': 'Lee un archivo existente dentro del proyecto.',
        'parameters': {
          'type': 'object',
          'properties': {
            'file_path': {'type': 'string'},
          },
          'required': ['file_path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_image',
        'description':
            'Inspecciona visualmente una imagen del proyecto (.png, .jpg, '
            '.jpeg, .webp, .gif). Usa esta herramienta cuando el usuario '
            'pida mirar capturas, assets o cualquier imagen en disco '
            '(ej. screenshot.png). No uses read_file para binarios de imagen.',
        'parameters': {
          'type': 'object',
          'properties': {
            'file_path': {
              'type': 'string',
              'description':
                  'Ruta relativa (o absoluta dentro del proyecto) de la imagen.',
            },
          },
          'required': ['file_path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'compile_project',
        'description':
            'Compila o ejecuta el proyecto Flutter. ANTES: usa list_files '
            '(carpetas macos/web/ios/android) y get_available_devices '
            '(dispositivos reales). Elige la mejor coincidencia y ejecuta '
            'sin preguntar al usuario si hay opción viable.',
        'parameters': {
          'type': 'object',
          'properties': {
            'platform': {
              'type': 'string',
              'enum': ['macos', 'ios', 'android', 'web'],
            },
            'mode': {
              'type': 'string',
              'enum': ['debug', 'release', 'profile'],
            },
          },
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'execute_command',
        'description': 'Ejecuta un comando del sistema dentro del proyecto.',
        'parameters': {
          'type': 'object',
          'properties': {
            'command': {'type': 'string'},
            'working_directory': {'type': 'string'},
          },
          'required': ['command'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_folder',
        'description': 'Crea una carpeta dentro del proyecto.',
        'parameters': {
          'type': 'object',
          'properties': {
            'folder_path': {'type': 'string'},
          },
          'required': ['folder_path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'download_file',
        'description': 'Descarga un archivo y lo guarda dentro del proyecto.',
        'parameters': {
          'type': 'object',
          'properties': {
            'url': {'type': 'string'},
            'target_path': {'type': 'string'},
          },
          'required': ['url'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'navigate_web',
        'description': 'Obtiene y analiza el contenido de una URL.',
        'parameters': {
          'type': 'object',
          'properties': {
            'url': {'type': 'string'},
          },
          'required': ['url'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'open_external_url',
        'description':
            'Abre una URL en el navegador externo del usuario (login, '
            'dashboards, documentación). Usa cuando falten credenciales '
            'o haga falta un portal: Supabase, Firebase, Stripe, Google, '
            'APIs externas. NO descarga HTML; solo abre el enlace.',
        'parameters': {
          'type': 'object',
          'properties': {
            'url': {
              'type': 'string',
              'description':
                  'URL https a abrir (ej. https://supabase.com/dashboard).',
            },
            'reason': {
              'type': 'string',
              'description':
                  'Por qué se abre (ej. "crear proyecto y copiar anon key").',
            },
          },
          'required': ['url', 'reason'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'grep_search',
        'description':
            'Busca texto o regex en el codebase. Úsala para localizar símbolos, usos o patrones sin leer archivos a ciegas.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Texto literal o expresión regular a buscar.',
            },
            'case_sensitive': {
              'type': 'boolean',
              'description': 'Si es true, la búsqueda distingue mayúsculas.',
            },
            'file_extension': {
              'type': 'string',
              'description':
                  'Filtra por extensión (ej: .dart, .yaml). Opcional.',
            },
            'max_results': {
              'type': 'integer',
              'description': 'Máximo de coincidencias (por defecto 50).',
            },
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'list_files',
        'description':
            'Lista la estructura de archivos del proyecto (árbol relativo).',
        'parameters': {
          'type': 'object',
          'properties': {
            'max_depth': {
              'type': 'integer',
              'description': 'Profundidad máxima desde la raíz (por defecto 4).',
            },
          },
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_available_devices',
        'description':
            'Lista los dispositivos Flutter disponibles AHORA en esta PC '
            '(Chrome, macOS, emuladores iOS/Android, etc.) vía '
            '`flutter devices --machine`. Úsala ANTES de compile_project '
            'cuando el usuario pida run/debug/probar aquí.',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_console_logs',
        'description':
            'Lee el estado vivo del IDE: últimas líneas de Output y Debug '
            'Console, más la lista completa de Problems (errores/warnings). '
            'Úsala cuando falle una compilación o necesites el log exacto '
            'sin pedirle al usuario que lo copie.',
        'parameters': {
          'type': 'object',
          'properties': {
            'max_lines': {
              'type': 'integer',
              'description': 'Máximo de líneas de Output/Debug (default 35).',
            },
          },
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'ide_control',
        'description':
            'Controla la barra Run/Debug del IDE: cambiar plataforma, '
            'ejecutar, hot restart o detener. Actualiza la UI superior y el '
            'Preview en tiempo real. Acciones: set_platform, run_app, '
            'hot_restart, stop_app.',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': [
                'set_platform',
                'run_app',
                'hot_restart',
                'stop_app',
              ],
              'description': 'Acción del IDE a ejecutar.',
            },
            'platform': {
              'type': 'string',
              'enum': [
                'android',
                'android_native',
                'ios',
                'ios_native',
                'web',
                'macos',
              ],
              'description':
                  'android/ios = Preview en marco; '
                  'android_native/ios_native = emulador externo.',
            },
          },
          'required': ['action'],
        },
      },
    },
  ];

  static const Set<String> _readOnlyTools = {
    'read_file',
    'read_image',
    'grep_search',
    'list_files',
    'navigate_web',
    'open_external_url',
    'get_available_devices',
    'read_console_logs',
  };

  /// Controles del IDE que se ejecutan sin PendingActions.
  static const Set<String> _ideControlTools = {
    'ide_control',
    'open_external_url',
  };

  static const Set<String> _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
  };

  /// Mutaciones de archivo que en Agent+autoApply corren sin PendingActions.
  static const Set<String> _autoEditTools = {
    'edit_file',
    'write_file',
    'create_file',
    'create_folder',
  };

  bool _isReadOnlyTool(String functionName) =>
      _readOnlyTools.contains(functionName);

  /// Comandos que pueden correr solos (estilo Cursor Agent).
  bool _isSafeAutoCommand(String command) {
    final c = command.trim().toLowerCase();
    if (c.isEmpty) return false;
    const safePrefixes = [
      'flutter pub get',
      'flutter pub upgrade',
      'flutter pub outdated',
      'flutter analyze',
      'flutter test',
      'flutter devices',
      'flutter doctor',
      'flutter clean',
      'dart analyze',
      'dart format',
      'dart pub get',
    ];
    return safePrefixes.any(c.startsWith);
  }

  /// ¿Requiere PendingActionsCard? Solo execute_command destructivo/externo.
  bool _requiresConfirmation(
    String functionName,
    Map<String, dynamic> args, {
    required bool autoApplyEdits,
  }) {
    if (_isReadOnlyTool(functionName)) return false;
    if (_ideControlTools.contains(functionName)) return false;
    if (functionName == 'compile_project') return false;
    if (_autoEditTools.contains(functionName)) {
      return !autoApplyEdits; // Agent: auto; Ask/manual: confirmar
    }
    if (functionName == 'execute_command') {
      final cmd = args['command'] as String? ?? '';
      return !_isSafeAutoCommand(cmd);
    }
    // download_file y otras mutaciones: confirmar
    return true;
  }

  bool _shouldAutoExecuteTool(
    String functionName,
    Map<String, dynamic> args, {
    required bool autoApplyEdits,
  }) =>
      !_requiresConfirmation(
        functionName,
        args,
        autoApplyEdits: autoApplyEdits,
      );

  /// Texto de progreso visible en el chat (timeline minimalista Cursor).
  String _stepStatusForTool(
    String functionName,
    Map<String, dynamic> args,
  ) {
    switch (functionName) {
      case 'list_files':
        return 'Exploring project files';
      case 'get_available_devices':
        return 'Checking available devices';
      case 'grep_search':
        final q = args['query'] as String? ?? '';
        return q.isEmpty ? 'Searching codebase' : 'Searching $q';
      case 'read_file':
        final path = args['file_path'] as String? ?? 'file';
        return 'Exploring $path';
      case 'read_image':
        final path = args['file_path'] as String? ?? 'image';
        return 'Inspecting image $path';
      case 'read_console_logs':
        return 'Reading Output logs';
      case 'ide_control':
        final action = args['action'] as String? ?? 'control';
        switch (action) {
          case 'set_platform':
            return 'Setting platform to ${args['platform'] ?? '...'}';
          case 'run_app':
            return 'Running on ${args['platform'] ?? 'selected platform'}';
          case 'hot_restart':
            return 'Hot restarting app';
          case 'stop_app':
            return 'Stopping app';
          default:
            return 'Controlling IDE ($action)';
        }
      case 'compile_project':
        final platform = args['platform'] as String? ?? 'auto';
        final mode = args['mode'] as String? ?? 'debug';
        return 'Running flutter run ($platform / $mode)';
      case 'execute_command':
        final cmd = args['command'] as String? ?? 'command';
        return 'Running $cmd';
      case 'edit_file':
        return 'Editing ${args['file_path'] ?? 'file'}';
      case 'write_file':
        return 'Writing ${args['file_path'] ?? 'file'}';
      case 'create_file':
        return 'Creating ${args['file_path'] ?? 'file'}';
      case 'create_folder':
        return 'Creating folder ${args['folder_path'] ?? ''}';
      case 'download_file':
        return 'Downloading file';
      case 'navigate_web':
        return 'Navigating ${args['url'] ?? ''}';
      case 'open_external_url':
        final reason = args['reason'] as String? ?? '';
        final url = args['url'] as String? ?? '';
        return reason.isEmpty
            ? 'Opening $url'
            : 'Opening browser: $reason';
      default:
        return 'Running $functionName';
    }
  }

  void _emitStep(
    AgentStepProgressCallback? onStepProgress,
    String statusText, {
    String? detail,
    AgentLiveStep? card,
  }) {
    onStepProgress?.call(statusText, detail: detail, card: card);
  }

  /// Construye la tarjeta visual (diff / shell) que se pinta en el chat.
  AgentLiveStep? _liveCardForTool({
    required String functionName,
    required Map<String, dynamic> args,
    required String result,
    required bool failed,
    required bool running,
  }) {
    final id =
        '${functionName}_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now();
    switch (functionName) {
      case 'edit_file':
      case 'write_file':
      case 'create_file':
        final path = args['file_path'] as String? ?? 'file';
        final stats = RegExp(r'([+-]\d+)\s+([+-]\d+)').firstMatch(result);
        int? added;
        int? removed;
        if (stats != null) {
          added = int.tryParse(stats.group(1)!.replaceAll('+', ''));
          removed = int.tryParse(stats.group(2)!.replaceAll('-', ''));
        }
        final lines = <AgentLiveStepLine>[];
        if (functionName == 'edit_file') {
          final search = (args['search_block'] as String? ?? '').split('\n');
          final replace = (args['replace_block'] as String? ?? '').split('\n');
          for (final l in search.take(8)) {
            lines.add(AgentLiveStepLine(mark: '-', text: l));
          }
          if (search.length > 8) {
            lines.add(const AgentLiveStepLine(mark: ' ', text: '…'));
          }
          for (final l in replace.take(8)) {
            lines.add(AgentLiveStepLine(mark: '+', text: l));
          }
          if (replace.length > 8) {
            lines.add(const AgentLiveStepLine(mark: ' ', text: '…'));
          }
          added ??= replace.isEmpty ? 0 : replace.length;
          removed ??= search.isEmpty ? 0 : search.length;
        } else {
          final content = (args['content'] as String? ?? '').split('\n');
          for (final l in content.take(10)) {
            lines.add(AgentLiveStepLine(mark: '+', text: l));
          }
          if (content.length > 10) {
            lines.add(const AgentLiveStepLine(mark: ' ', text: '…'));
          }
          added ??= content.isEmpty ? 0 : content.length;
          removed ??= functionName == 'write_file' ? null : 0;
        }
        return AgentLiveStep(
          id: id,
          kind: functionName == 'create_file'
              ? AgentLiveStepKind.create
              : AgentLiveStepKind.edit,
          title: path.split('/').last,
          filePath: path,
          added: failed ? null : added,
          removed: failed ? null : removed,
          previewLines: failed ? const [] : lines,
          running: running,
          at: now,
        );
      case 'execute_command':
      case 'compile_project':
        final cmd = functionName == 'compile_project'
            ? 'flutter run (${args['platform'] ?? 'auto'})'
            : (args['command'] as String? ?? 'command');
        final out = result.length > 600
            ? '${result.substring(0, 600)}…'
            : result;
        return AgentLiveStep(
          id: id,
          kind: AgentLiveStepKind.shell,
          title: running ? 'Running' : (failed ? 'Failed' : 'Ran'),
          command: cmd,
          output: running ? null : out,
          running: running,
          at: now,
        );
      case 'read_file':
      case 'list_files':
      case 'grep_search':
      case 'read_console_logs':
      case 'get_available_devices':
      case 'read_image':
        return AgentLiveStep(
          id: id,
          kind: functionName == 'grep_search'
              ? AgentLiveStepKind.search
              : AgentLiveStepKind.explore,
          title: _completedStatusForTool(functionName, args, result),
          filePath: args['file_path'] as String?,
          running: running,
          at: now,
        );
      case 'open_external_url':
      case 'navigate_web':
        return AgentLiveStep(
          id: id,
          kind: AgentLiveStepKind.browser,
          title: args['reason'] as String? ??
              (args['url'] as String? ?? 'browser'),
          command: args['url'] as String?,
          running: running,
          at: now,
        );
      default:
        return AgentLiveStep(
          id: id,
          kind: AgentLiveStepKind.status,
          title: _stepStatusForTool(functionName, args),
          running: running,
          at: now,
        );
    }
  }

  /// Línea compacta post-tool (estilo Cursor: Edited X +2 -1 / Ran …).
  String _completedStatusForTool(
    String functionName,
    Map<String, dynamic> args,
    String result,
  ) {
    switch (functionName) {
      case 'edit_file':
      case 'write_file':
        final path = args['file_path'] as String? ?? 'file';
        final stats = RegExp(r'([+-]\d+\s+[+-]\d+)').firstMatch(result);
        return stats != null ? 'Edited $path ${stats.group(1)}' : 'Edited $path';
      case 'create_file':
        return 'Created ${args['file_path'] ?? 'file'}';
      case 'create_folder':
        return 'Created folder ${args['folder_path'] ?? ''}';
      case 'read_file':
        return 'Explored ${args['file_path'] ?? 'file'}';
      case 'read_image':
        return 'Inspected ${args['file_path'] ?? 'image'}';
      case 'list_files':
        return 'Explored project files';
      case 'grep_search':
        final q = args['query'] as String? ?? '';
        return q.isEmpty ? 'Searched codebase' : 'Searched $q';
      case 'execute_command':
        return 'Ran ${args['command'] ?? 'command'}';
      case 'compile_project':
        final platform = args['platform'] as String? ?? 'auto';
        return 'Ran flutter run ($platform)';
      case 'get_available_devices':
        return 'Checked available devices';
      case 'read_console_logs':
        return 'Read Output / Debug Console';
      case 'ide_control':
        final action = args['action'] as String? ?? 'control';
        switch (action) {
          case 'set_platform':
            return 'Set platform to ${args['platform'] ?? '...'}';
          case 'run_app':
            return 'Started run (${args['platform'] ?? 'selected'})';
          case 'hot_restart':
            return 'Hot restarted app';
          case 'stop_app':
            return 'Stopped app';
          default:
            return 'IDE control: $action';
        }
      case 'navigate_web':
        return 'Navigated ${args['url'] ?? ''}';
      case 'open_external_url':
        return 'Opened ${args['url'] ?? 'url'} in browser';
      default:
        return 'Ran $functionName';
    }
  }

  /// Recorta stdout/stderr largos: errores + últimas 25 líneas, máx 2500 chars.
  String _compressTerminalOutput(String raw, {int maxChars = 2500}) {
    final text = raw.trimRight();
    if (text.length <= maxChars) return text;

    final lines = text.split('\n');
    final important = <String>[];
    final seen = <String>{};
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.contains('error') ||
          lower.contains('exception') ||
          lower.contains('failed') ||
          lower.contains('fatal')) {
        if (seen.add(line)) important.add(line);
      }
    }
    final tail = lines.length > 25 ? lines.sublist(lines.length - 25) : lines;
    final buffer = StringBuffer();
    if (important.isNotEmpty) {
      buffer.writeln('--- relevant errors ---');
      for (final line in important.take(40)) {
        buffer.writeln(line);
      }
    }
    buffer.writeln('--- last ${tail.length} lines ---');
    for (final line in tail) {
      buffer.writeln(line);
    }
    var out = buffer.toString().trimRight();
    if (out.length > maxChars) {
      out = out.substring(out.length - maxChars);
      out = '…[truncated]\n$out';
    }
    return out;
  }

  /// Tras edits auto: pub get (si pubspec) + analyze. Devuelve nudge si hay errores.
  Future<String?> _runPostEditVerification({
    required String projectPath,
    required List<String> editedPaths,
    required bool runPubGet,
    AgentStepProgressCallback? onStepProgress,
  }) async {
    try {
      if (runPubGet) {
        _emitStep(
          onStepProgress,
          'Running flutter pub get',
          card: AgentLiveStep(
            id: 'pubget_${DateTime.now().microsecondsSinceEpoch}',
            kind: AgentLiveStepKind.shell,
            title: 'Running',
            command: 'flutter pub get',
            running: true,
            at: DateTime.now(),
          ),
        );
        final pub = await _executeCommand(
          'flutter pub get',
          null,
          projectPath,
        );
        final pubFailed =
            pub.toLowerCase().contains('error') || pub.startsWith('❌');
        _emitStep(
          onStepProgress,
          pubFailed ? 'Failed flutter pub get' : 'Ran flutter pub get',
          card: AgentLiveStep(
            id: 'pubget_${DateTime.now().microsecondsSinceEpoch}',
            kind: AgentLiveStepKind.shell,
            title: pubFailed ? 'Failed' : 'Ran',
            command: 'flutter pub get',
            output: _compressTerminalOutput(pub, maxChars: 600),
            running: false,
            at: DateTime.now(),
          ),
        );
        if (pub.startsWith('❌') || pub.toLowerCase().startsWith('error')) {
          return 'flutter pub get failed after editing pubspec.yaml:\n'
              '${_compressTerminalOutput(pub)}\n'
              'Fix pubspec.yaml automatically and retry. Do not ask the user.';
        }
      }

      _emitStep(
        onStepProgress,
        'Running flutter analyze',
        card: AgentLiveStep(
          id: 'analyze_${DateTime.now().microsecondsSinceEpoch}',
          kind: AgentLiveStepKind.shell,
          title: 'Running',
          command: 'dart analyze',
          running: true,
          at: DateTime.now(),
        ),
      );
      final debug = DebugConsoleService();
      final items = await debug.refreshProblemsFromAnalyze(projectPath);
      final errors =
          items.where((p) => p.severity == ProblemSeverity.error).toList();
      if (errors.isEmpty) {
        _emitStep(
          onStepProgress,
          'Analyze clean',
          card: AgentLiveStep(
            id: 'analyze_${DateTime.now().microsecondsSinceEpoch}',
            kind: AgentLiveStepKind.shell,
            title: 'Ran',
            command: 'dart analyze',
            output: '0 errors found.',
            running: false,
            at: DateTime.now(),
          ),
        );
        return null;
      }

      _emitStep(
        onStepProgress,
        'Analyze found ${errors.length} error(s)',
        card: AgentLiveStep(
          id: 'analyze_${DateTime.now().microsecondsSinceEpoch}',
          kind: AgentLiveStepKind.shell,
          title: 'Failed',
          command: 'dart analyze',
          output: errors.take(8).map((e) => e.toString()).join('\n'),
          running: false,
          at: DateTime.now(),
        ),
      );
      final buffer = StringBuffer();
      // Priorizar errores de archivos que el agente acaba de tocar.
      final editedNorm = editedPaths
          .map((p) => p.replaceAll('\\', '/').toLowerCase())
          .toList();
      final related = errors.where((e) {
        final path = e.filePath.replaceAll('\\', '/').toLowerCase();
        return editedNorm.any(
          (ed) => path.endsWith(ed) || path.endsWith('/$ed') || ed.endsWith(path),
        );
      }).toList();
      final focus = related.isNotEmpty ? related : errors;

      // No quemar el loop en tests si el fallo original era Run/CLI.
      final recentOutput = debug.output.take(debug.output.length).toList();
      final tail = recentOutput.length > 40
          ? recentOutput.sublist(recentOutput.length - 40)
          : recentOutput;
      final runCliFailure = tail.any(
        (l) =>
            l.contains('Could not find an option named') ||
            l.contains('--web-renderer') ||
            l.toLowerCase().contains('no devices found') ||
            l.contains('Failed to launch'),
      );

      buffer.writeln(
        'Post-edit verification: flutter analyze found ${errors.length} error(s)'
        '${related.isNotEmpty ? ' (${related.length} in edited files)' : ''}.',
      );
      buffer.writeln('Edited files: ${editedPaths.join(', ')}');
      for (final e in focus.take(12)) {
        buffer.writeln('- $e');
      }
      if (runCliFailure) {
        buffer.writeln(
          'IMPORTANTE: El Output también muestra un fallo de flutter run/CLI '
          '(p. ej. flag inválido). Prioriza read_console_logs + corregir la '
          'causa del Run (no te pierdas arreglando solo tests). '
          'Luego reintenta ide_control(run_app) o compile_project.',
        );
      } else {
        buffer.writeln(
          'Fix the errors in the edited files first with edit_file. '
          'Do not ask the user. Re-run analyze after fixes.',
        );
      }
      return buffer.toString();
    } catch (e) {
      return 'Post-edit verification error: $e';
    }
  }

  /// Detecta respuestas que solo narran la intención de usar herramientas
  /// sin haber emitido tool_calls (p. ej. "voy a leer el archivo…").
  bool _looksLikeToolIntentionNarration(String content) {
    final text = content.trim().toLowerCase();
    if (text.isEmpty) return false;
    const phrases = [
      'voy a leer',
      'vamos a leer',
      'voy a revisar',
      'vamos a revisar',
      'voy a inspeccionar',
      'vamos a inspeccionar',
      'voy a buscar',
      'vamos a buscar',
      'voy a abrir',
      'vamos a abrir',
      'voy a editar',
      'vamos a editar',
      'voy a crear',
      'vamos a crear',
      'voy a analizar',
      'vamos a analizar',
      'voy a examinar',
      'procederé a',
      'procedere a',
      'procedamos a',
      'empezaré por',
      'empezare por',
      'primero leeré',
      'primero leere',
      'déjame leer',
      'dejame leer',
      'déjame revisar',
      'dejame revisar',
      'i will read',
      "i'll read",
      'i will check',
      "i'll check",
      'i will look',
      "i'll look",
      'let me read',
      'let me check',
      'let me look',
      'let me open',
      'going to read',
      'going to check',
      'going to inspect',
    ];
    return phrases.any(text.contains);
  }

  /// Ejecuta exactamente una herramienta con los argumentos ya aprobados.
  static const String _sandboxRejectMsg =
      'Error: No puedes editar archivos externos en .pub-cache. '
      'Si un paquete falla, cambia su versión o reemplázalo en '
      'pubspec.yaml dentro del proyecto.';

  static const String _readBeforeEditMsg =
      'Error de seguridad: Debes leer el archivo con read_file antes de '
      'editarlo para conocer todo su contexto y no dañar código existente.';

  static const int _mutilationMinLines = 40;

  /// Reinicia el set de archivos leídos del turno (si [reset]) y siembra el abierto.
  void _beginAgentTurn({
    String? activeFilePath,
    String? projectPath,
    bool reset = true,
  }) {
    if (reset) _readFilesInTurn.clear();
    _markFileReadInTurn(activeFilePath, projectPath);
  }

  String _normalizeToolPath(String filePath, String? projectPath) {
    var path = filePath.trim().replaceAll('\\', '/');
    if (path.isEmpty) return '';
    if (!path.startsWith('/') &&
        projectPath != null &&
        projectPath.trim().isNotEmpty) {
      final root = projectPath.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
      path = '$root/$path';
    }
    return path;
  }

  void _markFileReadInTurn(String? filePath, String? projectPath) {
    final key = _normalizeToolPath(filePath ?? '', projectPath);
    if (key.isNotEmpty) _readFilesInTurn.add(key);
  }

  bool _wasFileReadInTurn(String filePath, String? projectPath) {
    final key = _normalizeToolPath(filePath, projectPath);
    if (key.isEmpty) return false;
    if (_readFilesInTurn.contains(key)) return true;
    // Comparación por basename si el modelo usó ruta relativa distinta.
    final base = key.split('/').last;
    for (final read in _readFilesInTurn) {
      if (read == key || read.endsWith('/$base')) return true;
    }
    return false;
  }

  /// Rechaza edit_file que trunque/resuma un bloque grande (>60% menos líneas).
  String? _rejectMutilatingEdit(String searchBlock, String replaceBlock) {
    final removedCount =
        searchBlock.isEmpty ? 0 : searchBlock.split('\n').length;
    if (removedCount <= _mutilationMinLines) return null;
    final addedCount =
        replaceBlock.isEmpty ? 0 : replaceBlock.split('\n').length;
    final keptRatio = addedCount / removedCount;
    if (keptRatio >= 0.4) return null;
    return 'Error de seguridad: Tu edit_file intenta borrar más del 60% de '
        'un bloque grande ($removedCount líneas). Está prohibido resumir o '
        'truncar código existente. Haz cambios quirúrgicos pequeños solo en '
        'las líneas exactas a modificar.';
  }

  /// Rechaza rutas fuera del sandbox del proyecto (.pub-cache, SDK, etc.).
  String? _sandboxViolation(String filePath, String? projectPath) {
    if (projectPath == null || projectPath.isEmpty) {
      return 'Error: No hay proyecto cargado';
    }
    final raw = filePath.trim();
    if (raw.isEmpty) return 'Error: file_path vacío';

    final lower = raw.replaceAll('\\', '/').toLowerCase();
    if (lower.contains('.pub-cache') ||
        lower.contains('/flutter/packages/') ||
        lower.contains('/flutter/bin/cache/') ||
        lower.contains('/.pub-cache/')) {
      return _sandboxRejectMsg;
    }

    final projectRoot = projectPath.replaceAll('\\', '/');
    final root = projectRoot.endsWith('/')
        ? projectRoot.substring(0, projectRoot.length - 1)
        : projectRoot;
    var candidate = raw.replaceAll('\\', '/');
    if (!candidate.startsWith('/')) {
      candidate = '$root/$candidate';
    }
    // Normalizar ".."
    final parts = <String>[];
    for (final segment in candidate.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isEmpty) return _sandboxRejectMsg;
        parts.removeLast();
        continue;
      }
      parts.add(segment);
    }
    final fullPath = '/${parts.join('/')}';
    if (fullPath != root && !fullPath.startsWith('$root/')) {
      return _sandboxRejectMsg;
    }
    return null;
  }

  /// Este método no realiza ninguna llamada adicional al modelo.
  Future<String> executeSingleTool(
    String functionName,
    Map<String, dynamic> args,
    String? projectPath, {
    void Function(String operation, String filePath, {int? line})?
        onFileOperation,
  }) async {
    try {
      String? touchedDartPath;
      String? liveViewPath;
      int? liveViewLine;
      String result;

      switch (functionName) {
        case 'edit_file':
          final filePath = args['file_path'] as String? ?? '';
          final blocked = _sandboxViolation(filePath, projectPath);
          if (blocked != null) return blocked;
          if (!_wasFileReadInTurn(filePath, projectPath)) {
            return _readBeforeEditMsg;
          }
          final searchBlock = args['search_block'] as String? ?? '';
          final replaceBlock = args['replace_block'] as String? ?? '';
          final mutilation = _rejectMutilatingEdit(searchBlock, replaceBlock);
          if (mutilation != null) return mutilation;
          onFileOperation?.call('editando', filePath);
          // Anticipar línea ANTES de escribir → el editor subraya en vivo.
          final previewLine = await _estimateFocusLine(
            filePath,
            searchBlock,
            projectPath,
          );
          AgentActivityService().setActive(filePath, line: previewLine ?? 1);
          onFileOperation?.call(
            'editando',
            filePath,
            line: previewLine ?? 1,
          );
          final edit = await _executeSurgicalEditDetailed(
            filePath,
            searchBlock,
            replaceBlock,
            projectPath,
          );
          result = edit.message;
          touchedDartPath = filePath;
          liveViewPath = filePath;
          liveViewLine = edit.focusLine ?? previewLine ?? 1;
          break;
        case 'write_file':
          final filePath = args['file_path'] as String? ?? '';
          final blocked = _sandboxViolation(filePath, projectPath);
          if (blocked != null) return blocked;
          final largeFileError =
              await _rejectWriteOnLargeFile(filePath, projectPath);
          if (largeFileError != null) return largeFileError;
          onFileOperation?.call('editando', filePath, line: 1);
          AgentActivityService().setActive(filePath, line: 1);
          result = await _executeWriteFile(
            filePath,
            args['content'] as String? ?? '',
            projectPath,
          );
          touchedDartPath = filePath;
          liveViewPath = filePath;
          liveViewLine = 1;
          break;
        case 'create_file':
          final filePath = args['file_path'] as String? ?? '';
          final blocked = _sandboxViolation(filePath, projectPath);
          if (blocked != null) return blocked;
          onFileOperation?.call('creando', filePath, line: 1);
          AgentActivityService().setActive(filePath, line: 1);
          result = await _executeCreateFile(
            filePath,
            args['content'] as String? ?? '',
            projectPath,
          );
          touchedDartPath = filePath;
          liveViewPath = filePath;
          liveViewLine = 1;
          break;
        case 'read_file':
          final filePath = args['file_path'] as String? ?? '';
          onFileOperation?.call('leyendo', filePath, line: 1);
          AgentActivityService().setActive(filePath, line: 1);
          result = await _executeReadFile(filePath, projectPath);
          if (!result.toLowerCase().startsWith('error')) {
            _markFileReadInTurn(filePath, projectPath);
          }
          liveViewPath = filePath;
          liveViewLine = 1;
          break;
        case 'read_image':
          final filePath = args['file_path'] as String? ?? '';
          onFileOperation?.call('inspeccionando imagen', filePath);
          final prepared = await _prepareReadImage(filePath, projectPath);
          result = prepared.toolResult;
          break;
        case 'compile_project':
          onFileOperation?.call('compilando', 'proyecto');
          AgentActivityService().setBusy(
            'Compilando y lanzando…',
            operation: 'compilando',
          );
          result = await _executeCompileProject(
            args['platform'] as String?,
            args['mode'] as String?,
            projectPath,
          );
          break;
        case 'execute_command':
          final command = args['command'] as String? ?? '';
          onFileOperation?.call('ejecutando', command);
          AgentActivityService().setBusy(
            'Ejecutando comando',
            operation: 'ejecutando',
            detail: command.length > 56 ? '${command.substring(0, 56)}…' : command,
          );
          result = await _executeCommand(
            command,
            args['working_directory'] as String?,
            projectPath,
          );
          break;
        case 'create_folder':
          final folderPath = args['folder_path'] as String? ?? '';
          onFileOperation?.call('creando', folderPath);
          result = await _executeCreateFolder(folderPath, projectPath);
          break;
        case 'download_file':
          final url = args['url'] as String? ?? '';
          onFileOperation?.call('descargando', url);
          result = await _executeDownloadFile(
            url,
            args['target_path'] as String?,
            projectPath,
          );
          break;
        case 'navigate_web':
          final url = args['url'] as String? ?? '';
          onFileOperation?.call('navegando', url);
          result = await _executeNavigateWeb(url);
          break;
        case 'open_external_url':
          final url = args['url'] as String? ?? '';
          final reason = args['reason'] as String? ?? '';
          onFileOperation?.call('abriendo navegador', url);
          result = await _executeOpenExternalUrl(url, reason);
          break;
        case 'grep_search':
          onFileOperation?.call('buscando', args['query'] as String? ?? '');
          result = await _executeGrepSearch(args, projectPath);
          break;
        case 'list_files':
          onFileOperation?.call('listando', 'proyecto');
          result = await _executeListFiles(args, projectPath);
          break;
        case 'get_available_devices':
          onFileOperation?.call('dispositivos', 'flutter devices');
          result = await _executeGetAvailableDevices();
          break;
        case 'read_console_logs':
          onFileOperation?.call('logs', 'console');
          result = _executeReadConsoleLogs(
            maxLines: (args['max_lines'] as num?)?.toInt(),
          );
          break;
        case 'ide_control':
          final action = args['action'] as String? ?? '';
          onFileOperation?.call('ide', action);
          result = await _executeIdeControl(
            action,
            args,
            projectPath: projectPath,
          );
          break;
        default:
          return 'Error: Función desconocida: $functionName';
      }

      final failed = result.startsWith('❌') ||
          result.toLowerCase().startsWith('error');

      // Tras escribir/leer en disco: avisar a la UI para abrir Code en vivo.
      if (!failed &&
          liveViewPath != null &&
          liveViewPath.trim().isNotEmpty) {
        AgentActivityService().setActive(liveViewPath, line: liveViewLine);
        onFileOperation?.call(
          'archivo_actualizado',
          liveViewPath,
          line: liveViewLine,
        );
      }

      // Preview HTML/web-server: el WebView cachea la página. Tras
      // edit/write/create hay que forzar reload o el usuario sigue viendo
      // el color/estilo viejo aunque el archivo ya cambió.
      if (!failed &&
          (functionName == 'edit_file' ||
              functionName == 'write_file' ||
              functionName == 'create_file')) {
        try {
          final debug = DebugConsoleService();
          if (debug.isRunning &&
              debug.appUrl != null &&
              debug.appUrl!.isNotEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 120));
            // force: el Preview HTML debe refrescar tras cada edit del agente.
            debug.bumpPreviewReload(force: true);
          }
        } catch (_) {}
      }

      if (touchedDartPath != null &&
          touchedDartPath.toLowerCase().endsWith('.dart') &&
          !failed) {
        result = await _appendAnalyzeFeedback(
          result,
          touchedDartPath,
          projectPath,
        );
      }

      return result;
    } catch (e) {
      return 'Error ejecutando $functionName: $e';
    }
  }

  Future<String> _executeGrepSearch(
    Map<String, dynamic> args,
    String? projectPath,
  ) async {
    if (projectPath == null || projectPath.isEmpty) {
      return 'Error: No hay proyecto cargado';
    }
    final query = args['query'] as String? ?? '';
    if (query.trim().isEmpty) {
      return 'Error: query vacío';
    }

    final matches = await CodebaseSearchService.grepSearch(
      projectPath: projectPath,
      query: query,
      caseSensitive: args['case_sensitive'] as bool? ?? false,
      fileExtension: args['file_extension'] as String?,
      maxResults: (args['max_results'] as num?)?.toInt() ?? 30,
    );

    if (matches.isEmpty) {
      return 'Sin coincidencias para "$query". '
          'Prueba con list_files o busca por ruta/nombre parcial.';
    }

    final includeContext = matches.length <= 18;
    final buffer = StringBuffer('Encontradas ${matches.length} coincidencia(s):\n');
    for (final match in matches) {
      final file = match['filePath'];
      final lineNum = match['lineNumber'];
      final ctx = match['context'] as Map?;
      if (includeContext && ctx != null) {
        final b2 = (ctx['before2'] as String? ?? '').trim();
        final b1 = (ctx['before'] as String? ?? '').trim();
        final prefix = [
          if (b2.isNotEmpty && (b2.contains("'") || b2.contains('"'))) b2,
          if (b1.isNotEmpty) b1,
        ].join(' | ');
        if (prefix.isNotEmpty) {
          buffer.writeln(
            '- $file:$lineNum: ${match['lineContent']}  [prev: $prefix]',
          );
          continue;
        }
      }
      buffer.writeln('- $file:$lineNum: ${match['lineContent']}');
    }
    final out = buffer.toString().trimRight();
    return out.length > 6000 ? '${out.substring(0, 6000)}\n…[recortado]' : out;
  }

  Future<String> _executeListFiles(
    Map<String, dynamic> args,
    String? projectPath,
  ) async {
    if (projectPath == null || projectPath.isEmpty) {
      return 'Error: No hay proyecto cargado';
    }
    final maxDepth = (args['max_depth'] as num?)?.toInt() ?? 4;
    return CodebaseSearchService.listProjectFilesAsTree(
      projectPath,
      maxDepth: maxDepth,
    );
  }

  /// Lista dispositivos Flutter activos en esta PC (sin confirmación).
  Future<String> _executeGetAvailableDevices() async {
    try {
      final devices = await AdvancedDebuggingService.getAvailableDevices();
      if (devices.isEmpty) {
        return '''
No se detectaron dispositivos Flutter en esta PC.
Sugerencias:
- Abre Chrome (web)
- Inicia un simulador iOS / emulador Android
- Verifica con: flutter devices
'''.trim();
      }

      final buffer = StringBuffer();
      buffer.writeln('Dispositivos disponibles AHORA (${devices.length}):');
      for (final d in devices) {
        final name = d['name'] ?? 'unknown';
        final id = d['id'] ?? '';
        final category = d['category'] ?? '';
        final platform = d['platform'] ?? '';
        buffer.writeln(
          '- $name (id: $id, category: $category, platform: $platform)',
        );
      }
      buffer.writeln();
      buffer.writeln(
        'Cruza estos dispositivos con las carpetas del proyecto '
        '(macos/, web/, ios/, android/) y elige la mejor opción '
        'compatible. Luego llama compile_project SIN preguntar al usuario '
        'si hay al menos una coincidencia.',
      );
      return buffer.toString().trimRight();
    } catch (e) {
      return 'Error al listar dispositivos: $e';
    }
  }

  Future<String> _appendAnalyzeFeedback(
    String toolResult,
    String filePath,
    String? projectPath,
  ) async {
    try {
      final debug = DebugConsoleService();
      final items = await debug.refreshProblemsFromAnalyze(projectPath);
      final normalizedPath = filePath.replaceAll('\\', '/');
      final fileName = normalizedPath.split('/').last;
      final relatedErrors = items.where((item) {
        if (item.severity != ProblemSeverity.error) return false;
        final itemPath = item.filePath.replaceAll('\\', '/');
        return itemPath == normalizedPath ||
            itemPath.endsWith('/$normalizedPath') ||
            itemPath.endsWith(fileName) ||
            normalizedPath.endsWith(itemPath);
      }).toList();

      if (relatedErrors.isEmpty) {
        return '$toolResult\nflutter analyze: no errors in $filePath.';
      }

      final buffer = StringBuffer(toolResult);
      buffer.writeln();
      buffer.writeln(
        'flutter analyze found ${relatedErrors.length} error(s) in this file:',
      );
      for (final error in relatedErrors.take(8)) {
        buffer.writeln(
          '- Línea ${error.line}: ${error.message}'
          '${error.code.isNotEmpty ? ' (${error.code})' : ''}',
        );
      }
      buffer.writeln(
        'Corrige estos errores con edit_file antes de continuar.',
      );
      return buffer.toString().trimRight();
    } catch (e) {
      return '$toolResult\n⚠️ No se pudo ejecutar flutter analyze: $e';
    }
  }

  Future<List<Map<String, dynamic>>> _buildPendingActions(
    List<dynamic> toolCalls,
    String? projectPath,
  ) async {
    final pendingActions = <Map<String, dynamic>>[];
    for (final toolCall in toolCalls) {
      final functionName = toolCall['function']['name'] as String;
      final arguments = Map<String, dynamic>.from(
        jsonDecode(toolCall['function']['arguments'] as String) as Map,
      );
      final details = await _generateActionDescriptionWithDetails(
        functionName,
        arguments,
        projectPath,
      );
      pendingActions.add({
        'id':
            '${DateTime.now().microsecondsSinceEpoch}_${pendingActions.length}',
        'functionName': functionName,
        'arguments': arguments,
        'description': details['description'],
        'reasoning': details['reasoning'],
        'diff': details['diff'],
        'oldContent': details['oldContent'],
        'newContent': details['newContent'],
        'toolCallId': toolCall['id'] as String?,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
    return pendingActions;
  }

  /// Ejecuta el ciclo agentivo hasta obtener una respuesta final, alcanzar el
  /// máximo de iteraciones o pausar por una confirmación de escritura.
  ///
  /// [messages] se modifica in-place para que la UI pueda reanudar exactamente
  /// desde el assistant message que originó los tool_calls.
  Future<String> continueAgentLoop({
    required List<Map<String, dynamic>> messages,
    required String model,
    required String? projectPath,
    Function(List<Map<String, dynamic>> pendingActions)? onPendingActions,
    void Function(String operation, String filePath, {int? line})?
        onFileOperation,
    Function(String partialText)? onStreamChunk,
    AgentStepProgressCallback? onStepProgress,
    Future<String> Function(
      String action, {
      Map<String, dynamic>? args,
    })? onIdeControl,
    /// Agent: aplica edit/write/create sin pausar (con checkpoint externo).
    bool autoApplyEdits = true,
    /// Se llama una vez por lote de edits auto, ANTES de tocar disco.
    Future<void> Function(List<String> filePaths)? onBeforeAutoEdits,
    int maxIterations = defaultMaxIterations,
    /// Auto routing: arranca en mini y escala a gpt-4.1 tras 2 fallos.
    bool autoMode = false,
    /// Archivo abierto en el editor (cuenta como leído vía workspace_state).
    String? activeFilePath,
    /// false al reanudar tras confirmación / "Continuar tarea": conserva lo leído.
    bool resetReadFiles = true,
  }) async {
    lastRunHitIterationLimit = false;
    if (onIdeControl != null) this.onIdeControl = onIdeControl;
    _beginAgentTurn(
      activeFilePath: activeFilePath,
      projectPath: projectPath,
      reset: resetReadFiles,
    );
    final stepProgress = onStepProgress ?? this.onStepProgress;
    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer $apiKey',
      'User-Agent': 'VoryxelCode/1.0',
      'Accept': 'application/json',
    };

    var toolsExecutedThisTurn = false;
    var narrationRetries = 0;
    var webFallbackNudged = false;
    var checkpointCreatedThisTurn = false;
    var activeModel = model;
    lastAutoModel = activeModel;
    var consecutiveFixFails = 0;
    final commandRepeatCounts = <String, int>{};
    var repeatedCommandFails = 0;
    var consecutiveGrepOnlyTurns = 0;

    try {
    for (var iteration = 0; iteration < maxIterations; iteration++) {
      if (_isCancelled) {
        throw Exception('Solicitud cancelada por el usuario');
      }

      // Prefijo system+tools estable; podar tool results viejos (ahorro tokens).
      _pruneStaleToolResults(messages, keepRecent: 8);

      if (iteration == 0) _emitStep(stepProgress, 'Thought briefly');

      // Reintento automático ante OpenAI 429 (Rate limit TPM/RPM) sin tumbar la UI.
      late http.StreamedResponse response;
      for (var rateAttempt = 0; ; rateAttempt++) {
        if (_isCancelled) {
          throw Exception('Solicitud cancelada por el usuario');
        }
        final request = http.Request(
          'POST',
          Uri.parse('$baseUrl/chat/completions'),
        )
          ..headers.addAll(headers)
          ..body = jsonEncode({
            'model': activeModel,
            'messages': messages,
            'tools': _toolDefinitions,
            'tool_choice': 'auto',
            'temperature': 0.3,
            'max_tokens': 4096,
            'stream': true,
            'stream_options': {'include_usage': true},
          });
        response = await httpClient
            .send(request)
            .timeout(const Duration(seconds: 90));

        if (response.statusCode == 200) break;

        final errorBody = await response.stream.bytesToString();
        final parsed = _parseOpenAIError(response.statusCode, errorBody);
        if (response.statusCode == 429 && !parsed.isQuota && rateAttempt < 3) {
          final waitSec = _parseRetryDelaySeconds(
            errorBody,
            response.headers['retry-after'],
            fallback: 4 * (rateAttempt + 1),
          );
          _emitStep(
            stepProgress,
            '⏳ Límite OpenAI (429) — reintentando en ${waitSec}s',
          );
          _pruneStaleToolResults(messages, keepRecent: 4);
          await Future.delayed(Duration(seconds: waitSec));
          continue;
        }
        throw Exception(parsed.userMessage);
      }

      var accumulatedContent = '';
      final streamedToolCalls = <int, Map<String, dynamic>>{};
      var cutByLength = false;

      await for (final rawLine in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final line = rawLine.trim();
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') break;

        final Map<String, dynamic> chunk;
        try {
          chunk = jsonDecode(payload) as Map<String, dynamic>;
        } on FormatException {
          continue;
        }
        final fr = (chunk['choices'] as List?)?.firstOrNull;
        if (fr is Map && fr['finish_reason'] == 'length' && !cutByLength) {
          cutByLength = true;
          _emitStep(
            stepProgress,
            '✂️ Respuesta cortada por límite de tokens — recuperando...',
          );
        }
        final usage = chunk['usage'];
        final totalTokens = usage is Map
            ? (usage['total_tokens'] as num?)?.toInt()
            : null;
        if (totalTokens != null) {
          onTokensUsed?.call(totalTokens);
        }

        final choices = chunk['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;
        final choice = choices.first as Map<String, dynamic>;
        final delta = Map<String, dynamic>.from(
          choice['delta'] as Map? ?? const {},
        );

        final contentDelta = delta['content'] as String?;
        if (contentDelta != null && contentDelta.isNotEmpty) {
          accumulatedContent += contentDelta;
          onStreamChunk?.call(accumulatedContent);
        }

        final toolCallDeltas = delta['tool_calls'] as List<dynamic>?;
        if (toolCallDeltas != null) {
          for (final rawToolCall in toolCallDeltas) {
            final toolCall = rawToolCall as Map<String, dynamic>;
            final index = (toolCall['index'] as num?)?.toInt() ?? 0;
            final assembled = streamedToolCalls.putIfAbsent(
              index,
              () => {
                'id': '',
                'type': 'function',
                'function': {'name': '', 'arguments': ''},
              },
            );

            final id = toolCall['id'] as String?;
            if (id != null && id.isNotEmpty) assembled['id'] = id;
            final type = toolCall['type'] as String?;
            if (type != null && type.isNotEmpty) assembled['type'] = type;

            final functionDelta = toolCall['function'] as Map?;
            if (functionDelta != null) {
              final function = assembled['function'] as Map<String, dynamic>;
              final nameDelta = functionDelta['name'] as String?;
              final argumentsDelta = functionDelta['arguments'] as String?;
              if (nameDelta != null) {
                function['name'] = '${function['name']}$nameDelta';
              }
              if (argumentsDelta != null) {
                function['arguments'] =
                    '${function['arguments']}$argumentsDelta';
              }
            }
          }
        }

        // Esperar [DONE] para poder recibir el chunk final de usage.
      }

      final assistantMessage = <String, dynamic>{
        'role': 'assistant',
        'content': accumulatedContent.isEmpty ? null : accumulatedContent,
      };
      // Con finish_reason=length la última tool call está incompleta aunque
      // su JSON parsee; las anteriores sí se cerraron. Además, cualquier JSON
      // inválido se trata como truncado.
      final truncatedReplies = <Map<String, dynamic>>[];
      if (streamedToolCalls.isNotEmpty) {
        final orderedIndexes = streamedToolCalls.keys.toList()..sort();
        final calls = [
          for (final index in orderedIndexes) streamedToolCalls[index]!,
        ];
        for (var i = 0; i < calls.length; i++) {
          final call = calls[i];
          final fn = call['function'] as Map<String, dynamic>;
          final rawArgs = fn['arguments'] as String? ?? '';
          var truncated = cutByLength && i == calls.length - 1;
          if (!truncated) {
            try {
              jsonDecode(rawArgs.isEmpty ? '{}' : rawArgs);
            } on FormatException {
              truncated = true;
            }
          }
          if (!truncated) continue;
          fn['arguments'] = '{}';
          call['_truncated'] = true;
          truncatedReplies.add({
            'role': 'tool',
            'tool_call_id': call['id'],
            'name': fn['name'],
            'content':
                'Error: los argumentos de ${fn['name']} llegaron truncados '
                '(respuesta cortada por límite de tokens). No se ejecutó '
                'nada. No reescribas archivos completos: usa edit_file con '
                'search_block/replace_block pequeños, uno por llamada.',
          });
        }
        assistantMessage['tool_calls'] = [
          for (final c in calls)
            {
              'id': c['id'],
              'type': c['type'],
              'function': c['function'],
            },
        ];
        if (truncatedReplies.isNotEmpty) {
          final validCalls =
              calls.where((c) => c['_truncated'] != true).toList();
          messages.add(assistantMessage);
          messages.addAll(truncatedReplies);
          _emitStep(
            stepProgress,
            'Respuesta truncada — reintentando en partes',
            detail: '${truncatedReplies.length} tool call(s) cortadas',
          );
          if (validCalls.isEmpty) continue;
          // Procesar solo las válidas sin re-añadir el assistant message.
          assistantMessage['_validOnly'] = [
            for (final c in validCalls)
              {'id': c['id'], 'type': c['type'], 'function': c['function']},
          ];
        }
      }
      if (assistantMessage['_validOnly'] == null &&
          truncatedReplies.isEmpty) {
        messages.add(assistantMessage);
      }

      final toolCalls = (assistantMessage.remove('_validOnly') as List?) ??
          assistantMessage['tool_calls'] as List<dynamic>?;
      if ((toolCalls == null || toolCalls.isEmpty) &&
          cutByLength &&
          truncatedReplies.isEmpty) {
        messages.add({
          'role': 'user',
          'content':
              'Tu respuesta se cortó por límite de tokens. Continúa de forma '
              'concisa; si ibas a editar código, usa edit_file con bloques '
              'pequeños en lugar de escribir archivos completos.',
        });
        continue;
      }
      if (toolCalls == null || toolCalls.isEmpty) {
        final textOnly =
            assistantMessage['content'] as String? ?? '';
        // Evitar "teatro": narrar intención sin tool_calls en las primeras
        // iteraciones → reinyectar orden de ejecutar herramientas (máx. 2).
        if (!toolsExecutedThisTurn &&
            iteration < 2 &&
            narrationRetries < 2 &&
            _looksLikeToolIntentionNarration(textOnly)) {
          narrationRetries++;
          _emitStep(
            stepProgress,
            '⚡ Forzando ejecución de herramientas '
            '(reintento $narrationRetries/2)...',
            detail: textOnly.length > 160
                ? '${textOnly.substring(0, 160)}…'
                : textOnly,
          );
          messages.add({
            'role': 'user',
            'content':
                'No describas lo que vas a hacer. Ejecuta ahora mismo la '
                'herramienta correspondiente (read_file, read_image, '
                'list_files, grep_search, edit_file, etc.) usando '
                'function calling.',
          });
          continue;
        }
        return textOnly;
      }

      toolsExecutedThisTurn = true;

      Map<String, dynamic> argsOf(dynamic call) =>
          _safeToolArgs(call['function']['arguments']);

      final autoCalls = toolCalls
          .where(
            (call) => _shouldAutoExecuteTool(
              call['function']['name'] as String,
              argsOf(call),
              autoApplyEdits: autoApplyEdits,
            ),
          )
          .toList();
      final mutatingCalls = toolCalls
          .where(
            (call) => !_shouldAutoExecuteTool(
              call['function']['name'] as String,
              argsOf(call),
              autoApplyEdits: autoApplyEdits,
            ),
          )
          .toList();

      // Checkpoint antes del primer lote de edits auto-aplicados.
      if (autoApplyEdits &&
          !checkpointCreatedThisTurn &&
          onBeforeAutoEdits != null) {
        final editPaths = <String>[];
        for (final call in autoCalls) {
          final name = call['function']['name'] as String;
          if (!_autoEditTools.contains(name)) continue;
          final args = argsOf(call);
          final path = (args['file_path'] as String?) ??
              (args['folder_path'] as String?) ??
              '';
          if (path.trim().isNotEmpty) editPaths.add(path.trim());
        }
        if (editPaths.isNotEmpty) {
          checkpointCreatedThisTurn = true;
          await onBeforeAutoEdits(editPaths);
        }
      }

      // Lecturas en paralelo; mutaciones/runtime en serie (estilo Cursor).
      final visionFollowUps = <Map<String, dynamic>>[];
      final readCalls = autoCalls
          .where(
            (c) => _isReadOnlyTool(c['function']['name'] as String),
          )
          .toList();
      final writeCalls = autoCalls
          .where(
            (c) => !_isReadOnlyTool(c['function']['name'] as String),
          )
          .toList();

      Future<({dynamic toolCall, String result})> runOne(
        dynamic toolCall,
      ) async {
        final functionName = toolCall['function']['name'] as String;
        final arguments = argsOf(toolCall);
        _emitStep(
          stepProgress,
          _stepStatusForTool(functionName, arguments),
          card: _liveCardForTool(
            functionName: functionName,
            args: arguments,
            result: '',
            failed: false,
            running: true,
          ),
        );

        late final String result;
        if (functionName == 'read_image') {
          final prepared = await _prepareReadImage(
            arguments['file_path'] as String? ?? '',
            projectPath,
          );
          result = prepared.toolResult;
          if (prepared.visionUserMessage != null) {
            visionFollowUps.add(prepared.visionUserMessage!);
          }
          onFileOperation?.call(
            'inspeccionando imagen',
            arguments['file_path'] as String? ?? '',
          );
        } else {
          result = await executeSingleTool(
            functionName,
            arguments,
            projectPath,
            onFileOperation: onFileOperation,
          );
        }
        return (toolCall: toolCall, result: result);
      }

      void appendToolResult(dynamic toolCall, String result) {
        final functionName = toolCall['function']['name'] as String;
        final arguments = argsOf(toolCall);
        final failed = result.startsWith('❌') ||
            result.startsWith('Error') ||
            result.toLowerCase().contains('errores de compilación');
        final card = _liveCardForTool(
          functionName: functionName,
          args: arguments,
          result: result,
          failed: failed,
          running: false,
        );
        if (failed) {
          _emitStep(
            stepProgress,
            'Failed $functionName',
            detail:
                result.length > 280 ? '${result.substring(0, 280)}…' : result,
            card: card,
          );
        } else {
          _emitStep(
            stepProgress,
            _completedStatusForTool(functionName, arguments, result),
            card: card,
          );
        }
        messages.add({
          'role': 'tool',
          'tool_call_id': toolCall['id'],
          'name': functionName,
          'content': result,
        });

        final platformArg =
            (arguments['platform'] as String? ?? '').toLowerCase();
        final noMobileDevice = result.toLowerCase().contains(
              'no se encontró dispositivo',
            ) &&
            (platformArg == 'android' ||
                platformArg == 'ios' ||
                result.toLowerCase().contains('android') ||
                result.toLowerCase().contains('ios'));
        if (!webFallbackNudged &&
            (functionName == 'compile_project' ||
                functionName == 'execute_command') &&
            noMobileDevice) {
          webFallbackNudged = true;
          final selector = PlatformService().selectedPlatform.toLowerCase();
          // Si el usuario eligió Android/iOS, usar Preview embebido — NO Web.
          final previewTarget =
              selector.startsWith('ios') ? 'ios' : 'android';
          _emitStep(
            stepProgress,
            'Using ${ProjectPlatformSupport.humanLabel(previewTarget)}',
          );
          messages.add({
            'role': 'user',
            'content':
                'No hay emulador nativo. NO cambies el selector a Web. '
                'Llama ide_control(set_platform: "$previewTarget") solo si el '
                'selector no es ya Preview, luego ide_control(run_app) o '
                'compile_project(platform: "$previewTarget", mode: "debug"). '
                'Android/iOS (Preview) usan el marco de teléfono interno. '
                'Solo usa platform web si el usuario eligió Web explícitamente.',
          });
        }
      }

      if (readCalls.isNotEmpty) {
        final parallel = await Future.wait(
          readCalls.map(runOne),
        );
        for (final item in parallel) {
          appendToolResult(item.toolCall, item.result);
        }
      }

      final onlyGreps = writeCalls.isEmpty &&
          readCalls.isNotEmpty &&
          readCalls.every(
            (c) => c['function']['name'] == 'grep_search',
          );
      consecutiveGrepOnlyTurns = onlyGreps ? consecutiveGrepOnlyTurns + 1 : 0;
      if (consecutiveGrepOnlyTurns >= 4) {
        consecutiveGrepOnlyTurns = 0;
        messages.add({
          'role': 'user',
          'content':
              'Llevas varias búsquedas grep_search seguidas sin leer ni listar '
              'archivos. Usa list_files para ver las pantallas del proyecto o '
              'read_file sobre los archivos ya encontrados (si encontraste texto '
              'en internationalization.dart / .arb, lee la clave de traducción '
              'y búscala con grep_search).',
        });
      }

      final editedPaths = <String>[];
      var touchedPubspec = false;
      String? repeatedCmdNudge;

      void escalateToFullModel(String reason) {
        if (!autoMode || !activeModel.toLowerCase().contains('mini')) return;
        activeModel = 'gpt-4.1';
        model = 'gpt-4.1';
        lastAutoModel = 'gpt-4.1';
        _emitStep(stepProgress, 'Escalando a gpt-4.1', detail: reason);
      }

      bool isFailureResult(String res) {
        final l = res.toLowerCase();
        return res.startsWith('❌') ||
            l.contains('command failed') ||
            l.contains('failed to compile') ||
            l.contains('errores de compilación') ||
            l.contains('la compilación/ejecución falló') ||
            l.contains('timeout esperando compilación');
      }

      for (final toolCall in writeCalls) {
        final item = await runOne(toolCall);
        appendToolResult(item.toolCall, item.result);
        final name = toolCall['function']['name'] as String;
        final args = argsOf(toolCall);

        if (_autoEditTools.contains(name)) {
          final path = (args['file_path'] as String?)?.trim() ?? '';
          if (path.isNotEmpty) {
            editedPaths.add(path);
            if (path.toLowerCase().endsWith('pubspec.yaml')) {
              touchedPubspec = true;
            }
          }
        }

        // Detectar comandos / compilaciones repetidos o fallidos en serie.
        final isRuntimeCmd = name == 'execute_command' ||
            name == 'compile_project' ||
            (name == 'ide_control' &&
                (args['action'] as String? ?? '').toLowerCase() == 'run_app');
        if (isRuntimeCmd) {
          final String sig;
          if (name == 'execute_command') {
            sig = 'cmd:${(args['command'] as String? ?? '').trim().toLowerCase()}';
          } else if (name == 'compile_project') {
            final p = (args['platform'] as String? ??
                    PlatformService().selectedPlatform)
                .toLowerCase();
            sig = 'compile:$p';
          } else {
            sig = 'run_app:${PlatformService().selectedPlatform.toLowerCase()}';
          }

          final failed = isFailureResult(item.result);
          final count = (commandRepeatCounts[sig] ?? 0) + 1;
          commandRepeatCounts[sig] = count;

          if (failed) {
            repeatedCommandFails++;
          } else if (name == 'compile_project' || name == 'ide_control') {
            repeatedCommandFails = 0;
          }

          if (count >= 2 && (failed || name == 'execute_command')) {
            escalateToFullModel('Comando repetido ($count×) sin resolver');
            repeatedCmdNudge =
                'Estás repitiendo "$sig" ($count veces) sin resolver el '
                'problema. DETENTE y cambia de estrategia: revisa el error '
                'real (si apunta a ~/.pub-cache, fija la versión exacta sin ^ '
                'en pubspec.yaml o ejecuta flutter pub cache repair; si es '
                'código, edítalo con edit_file).';
          } else if (repeatedCommandFails >= 2) {
            escalateToFullModel('2 comandos/compilaciones fallidas seguidas');
          }
        }
      }

      if (repeatedCmdNudge != null) {
        messages.add({'role': 'user', 'content': repeatedCmdNudge});
      }

      // Tras edits: pub get (si pubspec) + analyze; si hay errores, forzar fix.
      if (editedPaths.isNotEmpty && projectPath != null) {
        final verifyMsg = await _runPostEditVerification(
          projectPath: projectPath,
          editedPaths: editedPaths,
          runPubGet: touchedPubspec,
          onStepProgress: stepProgress,
        );
        if (verifyMsg != null && verifyMsg.isNotEmpty) {
          messages.add({'role': 'user', 'content': verifyMsg});
          consecutiveFixFails++;
          if (consecutiveFixFails >= 2) {
            escalateToFullModel('2 fallos seguidos de corrección');
          }
        } else {
          consecutiveFixFails = 0;
        }
      }

      // Tras tool results de read_image: inyectar la imagen multimodal.
      for (final visionMsg in visionFollowUps) {
        messages.add(visionMsg);
      }

      var confirmableCalls = mutatingCalls;
      if (onPendingActions != null && mutatingCalls.isNotEmpty) {
        confirmableCalls = [];
        for (final toolCall in mutatingCalls) {
          final functionName = toolCall['function']['name'] as String;
          if (functionName != 'edit_file') {
            confirmableCalls.add(toolCall);
            continue;
          }

          final arguments = _safeToolArgs(toolCall['function']['arguments']);
          final editPath = arguments['file_path'] as String? ?? '';
          final searchBlock = arguments['search_block'] as String? ?? '';
          final replaceBlock = arguments['replace_block'] as String? ?? '';
          String? validationError;
          if (!_wasFileReadInTurn(editPath, projectPath)) {
            validationError = _readBeforeEditMsg;
          } else {
            validationError =
                _rejectMutilatingEdit(searchBlock, replaceBlock);
          }
          validationError ??= (await _prepareSurgicalEdit(
            editPath,
            searchBlock,
            replaceBlock,
            projectPath,
          ))['error'] as String?;
          if (validationError == null) {
            confirmableCalls.add(toolCall);
          } else {
            // No hubo mutación: devolver el error inmediatamente para que el
            // agente lea el archivo y corrija search_block en el siguiente paso.
            _emitStep(
              stepProgress,
              '⚠️ edit_file no válido — reintentando con otra estrategia...',
              detail: validationError,
            );
            messages.add({
              'role': 'tool',
              'tool_call_id': toolCall['id'],
              'name': functionName,
              'content': validationError,
            });
          }
        }
      }

      if (confirmableCalls.isNotEmpty && onPendingActions != null) {
        _emitStep(
          stepProgress,
          'Waiting for confirmation '
          '(${confirmableCalls.length} action(s))',
        );
        final pendingActions = await _buildPendingActions(
          confirmableCalls,
          projectPath,
        );
        onPendingActions(pendingActions);
        return 'Esperando tu confirmación para ejecutar '
            '${pendingActions.length} acción(es).';
      }

      if (onPendingActions != null &&
          mutatingCalls.isNotEmpty &&
          confirmableCalls.isEmpty) {
        // Todos los edits fallaron la validación sin tocar disco. El siguiente
        // ciclo permite que el modelo se auto-corrija automáticamente.
        continue;
      }

      // Modo sin confirmación: ejecutar determinísticamente todas las
      // herramientas restantes y seguir el ciclo.
      for (final toolCall in mutatingCalls) {
        final functionName = toolCall['function']['name'] as String;
        final arguments = _safeToolArgs(toolCall['function']['arguments']);
        _emitStep(stepProgress, _stepStatusForTool(functionName, arguments));
        final result = await executeSingleTool(
          functionName,
          arguments,
          projectPath,
          onFileOperation: onFileOperation,
        );
        messages.add({
          'role': 'tool',
          'tool_call_id': toolCall['id'],
          'name': functionName,
          'content': result,
        });
      }
    }

    lastRunHitIterationLimit = true;
    return await _summarizeUnfinishedTask(
      messages: messages,
      model: activeModel,
      headers: headers,
      stepProgress: stepProgress,
      maxIterations: maxIterations,
    );
    } finally {
      // Siempre apagar "Agente trabajando…" al salir del bucle
      // (respuesta final, pausa por confirmación, cancelación o límite).
      AgentActivityService().clear();
    }
  }

  static const int defaultMaxIterations = 20;

  /// true si el último [continueAgentLoop] agotó los pasos sin terminar;
  /// la UI lo usa para ofrecer "Continuar tarea".
  bool lastRunHitIterationLimit = false;

  /// Modelo efectivo usado en el último turno Auto (conserva escalado a gpt-4.1).
  String? lastAutoModel;

  static const String continueTaskPrompt =
      'Continúa la tarea exactamente donde la dejaste. No repitas pasos ya '
      'completados; ejecuta lo que falta y termina con un resumen breve.';

  /// Cierre al agotar pasos: una llamada sin herramientas que resume avance
  /// y pendientes. Mantiene `tools` con tool_choice none para no romper el
  /// historial con tool_calls ni el prefijo cacheado.
  Future<String> _summarizeUnfinishedTask({
    required List<Map<String, dynamic>> messages,
    required String model,
    required Map<String, String> headers,
    required AgentStepProgressCallback? stepProgress,
    required int maxIterations,
  }) async {
    _emitStep(stepProgress, 'Resumiendo avance');
    final fallback = 'Llegué al límite de $maxIterations pasos sin terminar '
        'la tarea. Pulsa «Continuar tarea» para seguir desde aquí.';
    final summaryRequest = <Map<String, dynamic>>[
      ...messages,
      {
        'role': 'user',
        'content':
            'Has agotado los $maxIterations pasos de este turno. No llames '
            'herramientas. Resume en máximo 6 viñetas cortas: qué completaste '
            '(archivos editados, comandos ejecutados) y qué falta para '
            'terminar la tarea.',
      },
    ];
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: headers,
            body: jsonEncode({
              'model': model,
              'messages': summaryRequest,
              'tools': _toolDefinitions,
              'tool_choice': 'none',
              'temperature': 0.2,
              'max_tokens': 500,
            }),
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) return fallback;
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      final usage = data['usage'];
      if (usage is Map && usage['total_tokens'] is num) {
        onTokensUsed?.call((usage['total_tokens'] as num).toInt());
      }
      final text = ((data['choices'] as List?)?.firstOrNull as Map?)?['message']
          ?['content'] as String?;
      if (text == null || text.trim().isEmpty) return fallback;
      final summary = text.trim();
      messages.add({'role': 'assistant', 'content': summary});
      return summary;
    } catch (_) {
      return fallback;
    }
  }

  static const int _maxWriteFileLines = 80;

  /// write_file sobre un archivo existente > [_maxWriteFileLines] líneas
  /// dispara respuestas enormes que se truncan con max_tokens 4096.
  Future<String?> _rejectWriteOnLargeFile(
    String filePath,
    String? projectPath,
  ) async {
    if (filePath.isEmpty) return null;
    final fullPath = filePath.startsWith('/')
        ? filePath
        : '${projectPath ?? ''}/$filePath';
    final file = File(fullPath);
    if (!await file.exists()) return null;
    try {
      final lineCount = (await file.readAsLines()).length;
      if (lineCount <= _maxWriteFileLines) return null;
    } catch (_) {
      return null;
    }
    return 'Error: El archivo ya existe y supera las 80 líneas. No uses '
        'write_file para reescribir archivos grandes; usa edit_file con '
        'search_block y replace_block modificando únicamente las líneas '
        'necesarias.';
  }

  /// Parsea argumentos de tool_call sin lanzar (JSON truncado → {}).
  Map<String, dynamic> _safeToolArgs(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is! String || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  ({bool isQuota, String userMessage}) _parseOpenAIError(
    int statusCode,
    String errorBody,
  ) {
    var apiMessage = '';
    var errorType = '';
    var errorCode = '';
    try {
      final decoded = jsonDecode(errorBody);
      final err = decoded is Map ? decoded['error'] : null;
      if (err is Map) {
        apiMessage = err['message']?.toString() ?? '';
        errorType = err['type']?.toString() ?? '';
        errorCode = err['code']?.toString() ?? '';
      }
    } catch (_) {}

    final lowerMsg = apiMessage.toLowerCase();
    final lowerBody = errorBody.toLowerCase();
    final isQuota = errorType == 'insufficient_quota' ||
        errorCode == 'insufficient_quota' ||
        (lowerMsg.contains('insufficient_quota') &&
            !lowerMsg.contains('rate') &&
            !lowerMsg.contains('limit')) ||
        lowerMsg.contains('insufficient funds') ||
        (lowerMsg.contains('exceeded your current quota') &&
            !lowerMsg.contains('rate'));

    if (isQuota) {
      return (
        isQuota: true,
        userMessage:
            'Tu cuenta real de OpenAI se quedó sin saldo o alcanzó su límite de facturación '
            '(insufficient_quota). El contador verde de Voryxel Code es solo local; revisa tu '
            'crédito en platform.openai.com/settings/organization/billing.\n\nDetalle: '
            '${apiMessage.isNotEmpty ? apiMessage : errorBody}',
      );
    }
    if (statusCode == 429) {
      return (
        isQuota: false,
        userMessage:
            'OpenAI alcanzó el límite temporal de peticiones/tokens por minuto (429). '
            'Espera unos segundos y vuelve a intentar.\n\nDetalle: '
            '${apiMessage.isNotEmpty ? apiMessage : errorBody}',
      );
    }
    if (statusCode == 401) {
      return (
        isQuota: false,
        userMessage:
            'API Key de OpenAI inválida o expirada (401). Revísala en Settings.\n\nDetalle: '
            '${apiMessage.isNotEmpty ? apiMessage : errorBody}',
      );
    }
    if (statusCode == 400 &&
        (errorCode == 'context_length_exceeded' ||
            lowerMsg.contains('context_length_exceeded') ||
            lowerMsg.contains('maximum context length'))) {
      return (
        isQuota: false,
        userMessage:
            'La conversación superó el tamaño máximo permitido por el modelo (400). '
            'Abre un chat nuevo o acorta el mensaje.',
      );
    }
    final detail = apiMessage.isNotEmpty
        ? apiMessage
        : (lowerBody.isNotEmpty ? errorBody : 'Error HTTP $statusCode');
    return (isQuota: false, userMessage: 'OpenAI ($statusCode): $detail');
  }

  int _parseRetryDelaySeconds(
    String errorBody,
    String? retryAfterHeader, {
    int fallback = 4,
  }) {
    final headerSec = int.tryParse(retryAfterHeader?.trim() ?? '');
    if (headerSec != null && headerSec > 0) {
      return headerSec.clamp(2, 25);
    }
    final m = RegExp(
      r'try again in\s+(\d+(?:\.\d+)?)\s*(ms|s)',
      caseSensitive: false,
    ).firstMatch(errorBody);
    if (m != null) {
      final raw = double.tryParse(m.group(1)!) ?? fallback.toDouble();
      final unit = m.group(2)!.toLowerCase();
      final secs = unit == 'ms' ? (raw / 1000).ceil() : raw.ceil() + 1;
      return secs.clamp(2, 25);
    }
    return fallback.clamp(2, 25);
  }

  /// Comprime tool results antiguos (deja intactos los últimos [keepRecent]).
  void _pruneStaleToolResults(
    List<Map<String, dynamic>> messages, {
    int keepRecent = 8,
  }) {
    if (messages.length <= keepRecent) return;
    final cutoff = messages.length - keepRecent;
    const marker =
        '[Salida de herramienta anterior comprimida para ahorro de tokens]';
    for (var i = 0; i < cutoff; i++) {
      final m = messages[i];
      if (m['role'] != 'tool') continue;
      final content = m['content'];
      if (content is String && content.length > 400 && content != marker) {
        m['content'] = marker;
      }
    }
  }

  /// Ventana de ~120 líneas alrededor del cursor (1-based). Sin cursor → centro.
  String _clipOpenFileWindow(
    String content, {
    int? cursorLine,
    int maxLines = 120,
  }) {
    final lines = content.split('\n');
    if (lines.length <= maxLines) return content;
    final radius = maxLines ~/ 2;
    final center = (cursorLine ?? ((lines.length / 2).floor() + 1))
        .clamp(1, lines.length);
    final start = (center - radius).clamp(1, lines.length);
    final end = (start + maxLines - 1).clamp(1, lines.length);
    final slice = lines.sublist(start - 1, end);
    return '// … líneas 1–${start - 1} omitidas …\n'
        '${slice.join('\n')}\n'
        '// … líneas ${end + 1}–${lines.length} omitidas …';
  }

  /// Bloque invisible inyectado en el ÚLTIMO user (Prompt Caching del system).
  Future<String> buildWorkspaceState({
    String? projectPath,
    String? activeFilePath,
    String? activeFileContent,
    int? activeCursorLine,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('<workspace_state>');
    if (projectPath != null && projectPath.isNotEmpty) {
      buffer.writeln('project_path: $projectPath');
    }

    // Archivo abierto: ruta + máx. 120 líneas alrededor del cursor
    if (activeFilePath != null && activeFilePath.trim().isNotEmpty) {
      buffer.writeln('open_file: $activeFilePath');
      final content = activeFileContent ?? '';
      if (content.isNotEmpty) {
        final clipped = _clipOpenFileWindow(
          content,
          cursorLine: activeCursorLine,
          maxLines: 120,
        );
        buffer.writeln(
          '<open_file_window path="$activeFilePath" '
          'cursor_line="${activeCursorLine ?? 'mid'}">',
        );
        buffer.writeln(clipped);
        buffer.writeln('</open_file_window>');
      } else {
        buffer.writeln('open_file_content: (empty or unavailable)');
      }
    } else {
      buffer.writeln('open_file: (none)');
    }

    // Problems: máx. 15
    try {
      final debug = DebugConsoleService();
      final problems = debug.problemItems;
      final errors = problems
          .where((p) => p.severity == ProblemSeverity.error)
          .length;
      buffer.writeln(
        'problems: ${problems.length} (errors: $errors) showing≤15',
      );
      if (problems.isEmpty) {
        buffer.writeln('problems_list: (none)');
      } else {
        buffer.writeln('<problems>');
        for (final p in problems.take(15)) {
          buffer.writeln('- $p');
        }
        buffer.writeln('</problems>');
      }

      if (debug.compilationStatus.isNotEmpty) {
        buffer.writeln('compilation_status: ${debug.compilationStatus}');
      }
      if (debug.appUrl != null && debug.appUrl!.isNotEmpty) {
        buffer.writeln('preview_url: ${debug.appUrl}');
      }

      // Últimas 15 líneas de Output (+ debug console compacto)
      buffer.write(_formatConsoleTail('output', debug.output, 15));
      buffer.write(
        _formatConsoleTail('debug_console', debug.debugConsole, 15),
      );
    } catch (_) {
      buffer.writeln('problems: (unavailable)');
    }

    try {
      buffer.writeln(
        'selected_platform: ${PlatformService().selectedPlatform}',
      );
    } catch (_) {
      buffer.writeln('selected_platform: (unknown)');
    }

    // Elemento señalado en Preview Inspector (si hay)
    try {
      buffer.writeln(InspectorSelectionService().toWorkspaceBlock());
    } catch (_) {
      buffer.writeln('inspector: (unavailable)');
    }

    // Claves .env (solo nombres — nunca valores secretos)
    try {
      buffer.write(
        await EnvConnectionsService.toWorkspaceBlock(projectPath),
      );
    } catch (_) {
      buffer.writeln('env_keys: (unavailable)');
    }

    // Árbol nivel 2 (sin flutter devices — caro en tokens/tiempo)
    if (projectPath != null && projectPath.isNotEmpty) {
      try {
        final tree = await CodebaseSearchService.listProjectFilesAsTree(
          projectPath,
          maxDepth: 2,
        ).timeout(
          const Duration(seconds: 3),
          onTimeout: () => '(timeout listing files)',
        );
        buffer.writeln('<project_tree depth="2">');
        buffer.writeln(tree);
        buffer.writeln('</project_tree>');
      } catch (e) {
        buffer.writeln('project_tree: (error: $e)');
      }
    } else {
      buffer.writeln('project_tree: (no project)');
    }

    buffer.writeln('</workspace_state>');
    return buffer.toString().trimRight();
  }

  String _formatConsoleTail(String label, List<String> lines, int maxLines) {
    final buffer = StringBuffer();
    if (lines.isEmpty) {
      buffer.writeln('$label: (empty)');
      return buffer.toString();
    }
    final start =
        lines.length > maxLines ? lines.length - maxLines : 0;
    final tail = lines.sublist(start);
    buffer.writeln('<$label last="${tail.length}">');
    for (final line in tail) {
      buffer.writeln(line);
    }
    buffer.writeln('</$label>');
    return buffer.toString();
  }

  String _executeReadConsoleLogs({int? maxLines}) {
    final n = (maxLines == null || maxLines <= 0) ? 35 : maxLines.clamp(1, 200);
    final debug = DebugConsoleService();
    final buffer = StringBuffer();
    buffer.writeln('=== IDE CONSOLE SNAPSHOT ===');
    buffer.writeln('running: ${debug.isRunning}');
    buffer.writeln(
      'compilation: ${debug.compilationProgress.toStringAsFixed(2)} '
      '· ${debug.compilationStatus}',
    );
    if (debug.appUrl != null && debug.appUrl!.isNotEmpty) {
      buffer.writeln('preview_url: ${debug.appUrl}');
    }
    buffer.writeln();
    buffer.writeln('Problems (${debug.problemItems.length}):');
    if (debug.problemItems.isEmpty) {
      buffer.writeln('(none)');
    } else {
      for (final p in debug.problemItems) {
        buffer.writeln('- $p');
      }
    }
    buffer.writeln();
    buffer.write(_formatConsoleTail('output', debug.output, n));
    buffer.write(_formatConsoleTail('debug_console', debug.debugConsole, n));
    return buffer.toString().trimRight();
  }

  Future<String> _executeIdeControl(
    String action,
    Map<String, dynamic> args, {
    String? projectPath,
  }) async {
    final normalized = action.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'Error: action vacío. Usa set_platform, run_app, hot_restart o stop_app.';
    }

    // Preferir callback UI (actualiza toolbar/preview en vivo).
    final handler = onIdeControl;
    if (handler != null) {
      try {
        return await handler(normalized, args: args);
      } catch (e) {
        return 'Error en ide_control($normalized): $e';
      }
    }

    // Fallback sin UI: servicios compartidos.
    switch (normalized) {
      case 'set_platform':
        final platform = (args['platform'] as String? ?? '').toLowerCase();
        if (!const {'android', 'ios', 'web', 'macos'}.contains(platform)) {
          return 'Error: platform inválida. Usa android, ios, web o macos.';
        }
        PlatformService().setPlatform(platform);
        return '✅ Plataforma del IDE → $platform';
      case 'run_app':
        // Usar el selector actual; no pisarlo con args.platform.
        final p = PlatformService().selectedPlatform;
        return await _executeCompileProject(p, 'debug', projectPath);
      case 'hot_restart':
        final ok = await DebugConsoleService().requestHotRestart();
        return ok
            ? '✅ Hot Restart enviado'
            : '⚠️ Hot Restart: no hay proceso Flutter activo';
      case 'stop_app':
        await DebugConsoleService().requestStop();
        return '✅ Stop enviado — proceso detenido';
      default:
        return 'Error: action desconocida "$action". '
            'Usa set_platform | run_app | hot_restart | stop_app.';
    }
  }

  /// Auto: tareas que requieren gpt-4.1 (no mini).
  bool _needsFullModel(String userMessage) {
    final t = userMessage.toLowerCase();
    return t.contains('@codebase') ||
        t.contains('refactor') ||
        t.contains('refactoriz') ||
        t.contains('arquitectura') ||
        t.contains('rediseña') ||
        t.contains('redisen') ||
        t.contains('deep refactor') ||
        t.contains('restructure') ||
        t.contains('reestructur') ||
        t.contains('diagnostica la causa raíz exacta') ||
        t.contains('la compilación/ejecución falló');
  }

  Future<String> sendMessage({
    required String message,
    List<String>? imagePaths,
    List<Map<String, dynamic>>? conversationHistory,
    String? fileContent,
    String? systemPrompt,
    String? projectPath, // Para ejecutar funciones de archivos
    String? activeFilePath,
    String? activeFileContent,
    int? activeCursorLine,
    void Function(String operation, String filePath, {int? line})?
    onFileOperation, // Callback para operaciones de archivos
    Function(List<Map<String, dynamic>> pendingActions)?
    onPendingActions, // Callback para acciones pendientes
    Function(int)? onTokensUsed, // ✅ NUEVO: Callback para tokens usados
    Function(String partialText)? onStreamChunk,
    AgentStepProgressCallback? onStepProgress,
    Future<String> Function(
      String action, {
      Map<String, dynamic>? args,
    })? onIdeControl,
    bool allowTools = true, // Controla si se permiten herramientas
    /// Agent: auto-aplica edits sin PendingActionsCard.
    bool autoApplyEdits = true,
    Future<void> Function(List<String> filePaths)? onBeforeAutoEdits,
    List<Map<String, dynamic>>? apiMessages,
    /// Selector Auto del chat: enruta a gpt-4.1-mini por defecto.
    bool autoMode = false,
    /// True cuando el turno viene de "Arreglar con IA": escala directo a gpt-4.1.
    bool forceFullModel = false,
  }) async {
    this.onFileOperation = onFileOperation;
    this.onPendingActions = onPendingActions;
    this.onTokensUsed = onTokensUsed; // ✅ Guardar callback
    this.onStepProgress = onStepProgress;
    if (onIdeControl != null) this.onIdeControl = onIdeControl;
    _isCancelled = false; // Reset cancel flag
    try {
      final messages = apiMessages ?? <Map<String, dynamic>>[];
      messages.clear();

      // Enrutamiento inteligente (Auto): mini por defecto; full si @codebase/refactor/Arreglar con IA.
      if (autoMode) {
        model = (forceFullModel || _needsFullModel(message))
            ? 'gpt-4.1'
            : 'gpt-4.1-mini';
        lastAutoModel = model;
        print('🤖 Auto routing → $model');
      }

      // System ESTÁTICO (Prompt Caching): agent mindset + .cursorrules.
      // Nunca: reloj, logs, archivo abierto, conteo de imágenes.
      String finalSystemPrompt = systemPrompt ?? '';
      if (allowTools) {
        final agentMindset = _cursorAgentSystemPrompt();
        finalSystemPrompt = finalSystemPrompt.isEmpty
            ? agentMindset
            : '$agentMindset\n\n$finalSystemPrompt';
      }
      if (projectPath != null && projectPath.isNotEmpty) {
        final projectRules =
            await ProjectRulesService.loadProjectInstructions(projectPath);
        if (projectRules.isNotEmpty) {
          finalSystemPrompt = finalSystemPrompt.isEmpty
              ? projectRules
              : '$finalSystemPrompt\n\n$projectRules';
        }
      }

      if (finalSystemPrompt.isNotEmpty) {
        messages.add({'role': 'system', 'content': finalSystemPrompt});
      }

      // Agregar historial de conversación si existe
      if (conversationHistory != null) {
        messages.addAll(conversationHistory);
      }

      // Dinámico SOLO en el último user (no rompe caché del system).
      var apiUserText = message;
      if (allowTools) {
        try {
          final workspace = await buildWorkspaceState(
            projectPath: projectPath,
            activeFilePath: activeFilePath,
            activeFileContent: activeFileContent,
            activeCursorLine: activeCursorLine,
          );
          apiUserText =
              '$workspace\n\n<user_query>\n$message\n</user_query>';
        } catch (e) {
          print('⚠️ workspace_state: $e');
        }
      }
      // Solo en modo Ask (sin tools) se pide describir la imagen en detalle.
      // En modo Agent la regla de capturas vive en _cursorAgentSystemPrompt:
      // localizar el código y corregir, no describir.
      if (!allowTools && imagePaths != null && imagePaths.isNotEmpty) {
        apiUserText +=
            '\n\n<images_note>El usuario adjuntó ${imagePaths.length} '
            'imagen(es). Analízalas en detalle (UI, texto, código visible).'
            '</images_note>';
      }

      // Construir el contenido del mensaje
      List<Map<String, dynamic>> content = [
        {'type': 'text', 'text': apiUserText},
      ];

      // Agregar imágenes si existen (con optimización + MIME real)
      if (imagePaths != null && imagePaths.isNotEmpty) {
        // Verificar que el modelo soporte visión
        if (!_supportsVision(model)) {
          print(
            '⚠️ El modelo $model no soporta análisis de imágenes. Usando gpt-4o automáticamente.',
          );
          model = 'gpt-4o'; // Cambiar a modelo con visión
        }

        print('🖼️ Procesando ${imagePaths.length} imagen(es)...');

        for (var imagePath in imagePaths) {
          final file = File(imagePath);
          if (await file.exists()) {
            final optimized = await _optimizeImage(file);
            final base64Image = base64Encode(optimized.bytes);

            final imageTokens = _estimateImageTokens(optimized.bytes.length);
            print(
              '📊 Imagen optimizada: ${(optimized.bytes.length / 1024).toStringAsFixed(1)}KB '
              '(${optimized.mimeType}), ~$imageTokens tokens',
            );

            content.add({
              'type': 'image_url',
              'image_url': {
                'url': 'data:${optimized.mimeType};base64,$base64Image',
                'detail': 'high',
              },
            });
          }
        }
      }

      // Agregar contenido de archivo si existe
      if (fileContent != null) {
        content[0]['text'] =
            '$apiUserText\n\n--- Código del archivo ---\n$fileContent';
      }

      messages.add({'role': 'user', 'content': content});

      if (allowTools) {
        return await continueAgentLoop(
          messages: messages,
          model: model,
          projectPath: projectPath,
          onPendingActions: onPendingActions,
          onFileOperation: onFileOperation,
          onStreamChunk: onStreamChunk,
          onStepProgress: onStepProgress,
          onIdeControl: onIdeControl ?? this.onIdeControl,
          autoApplyEdits: autoApplyEdits,
          onBeforeAutoEdits: onBeforeAutoEdits,
          autoMode: autoMode,
          activeFilePath: activeFilePath,
        );
      }

      // Headers mejorados siguiendo las mejores prácticas de OpenAI
      final headers = {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $apiKey',
        'User-Agent': 'VoryxelCode/1.0',
        'Accept': 'application/json',
      };

      // Definir funciones disponibles para Function Calling
      final tools = [
        {
          'type': 'function',
          'function': {
            'name': 'edit_file',
            'description':
                'Edita quirúrgicamente un bloque único de un archivo existente.',
            'parameters': {
              'type': 'object',
              'properties': {
                'file_path': {
                  'type': 'string',
                  'description':
                      'Ruta relativa del archivo a editar.',
                },
                'search_block': {
                  'type': 'string',
                  'description':
                      'Bloque existente exacto y suficientemente único.',
                },
                'replace_block': {
                  'type': 'string',
                  'description': 'Código que reemplazará search_block.',
                },
              },
              'required': ['file_path', 'search_block', 'replace_block'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'write_file',
            'description': 'Reescribe completamente un archivo existente.',
            'parameters': {
              'type': 'object',
              'properties': {
                'file_path': {'type': 'string'},
                'content': {'type': 'string'},
              },
              'required': ['file_path', 'content'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'create_file',
            'description':
                'Crea un nuevo archivo en el proyecto con el código proporcionado.',
            'parameters': {
              'type': 'object',
              'properties': {
                'file_path': {
                  'type': 'string',
                  'description':
                      'Ruta completa del archivo a crear (ej: lib/widgets/new_widget.dart)',
                },
                'content': {
                  'type': 'string',
                  'description': 'Contenido completo del archivo nuevo',
                },
              },
              'required': ['file_path', 'content'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'read_file',
            'description':
                'Lee el contenido de un archivo existente en el proyecto. SIEMPRE usa esto ANTES de edit_file() para entender el contexto.',
            'parameters': {
              'type': 'object',
              'properties': {
                'file_path': {
                  'type': 'string',
                  'description':
                      'Ruta completa del archivo a leer (ej: lib/main.dart)',
                },
              },
              'required': ['file_path'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'read_image',
            'description':
                'Inspecciona visualmente una imagen del proyecto (.png/.jpg/.jpeg/.webp/.gif).',
            'parameters': {
              'type': 'object',
              'properties': {
                'file_path': {
                  'type': 'string',
                  'description': 'Ruta de la imagen relativa al proyecto',
                },
              },
              'required': ['file_path'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'compile_project',
            'description':
                'Compila el proyecto Flutter y detecta errores de compilación. Útil para verificar que el código compila correctamente. IMPORTANTE: Solo usar cuando el usuario explícitamente pida compilar, ejecutar, probar o verificar el proyecto. NO usar para saludos o preguntas simples.',
            'parameters': {
              'type': 'object',
              'properties': {
                'platform': {
                  'type': 'string',
                  'description':
                      'Plataforma para compilar: macos, ios, android, web',
                  'enum': ['macos', 'ios', 'android', 'web'],
                },
                'mode': {
                  'type': 'string',
                  'description': 'Modo de compilación: debug, release, profile',
                  'enum': ['debug', 'release', 'profile'],
                },
              },
              'required': [],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'execute_command',
            'description':
                'Ejecuta un comando del sistema (Flutter, Git, etc.). Útil para instalar dependencias, ejecutar scripts, etc.',
            'parameters': {
              'type': 'object',
              'properties': {
                'command': {
                  'type': 'string',
                  'description':
                      'Comando a ejecutar (ej: flutter pub get, git status)',
                },
                'working_directory': {
                  'type': 'string',
                  'description':
                      'Directorio donde ejecutar el comando (opcional, por defecto proyecto actual)',
                },
              },
              'required': ['command'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'create_folder',
            'description':
                'Crea una carpeta/directorio en el proyecto. Útil para estructurar el proyecto antes de crear archivos.',
            'parameters': {
              'type': 'object',
              'properties': {
                'folder_path': {
                  'type': 'string',
                  'description':
                      'Ruta de la carpeta a crear (ej: lib/screens, lib/widgets). Se crean directorios recursivamente si es necesario.',
                },
              },
              'required': ['folder_path'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'download_file',
            'description':
                'Descarga un archivo desde una URL y lo guarda en el proyecto.',
            'parameters': {
              'type': 'object',
              'properties': {
                'url': {
                  'type': 'string',
                  'description': 'URL del archivo a descargar',
                },
                'target_path': {
                  'type': 'string',
                  'description':
                      'Ruta donde guardar el archivo (ej: lib/assets/file.zip). Si no se especifica, se guarda en la raíz del proyecto.',
                },
              },
              'required': ['url'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'navigate_web',
            'description':
                'Navega a una URL y obtiene su contenido HTML para analizarlo. Útil para buscar información, documentación, etc.',
            'parameters': {
              'type': 'object',
              'properties': {
                'url': {
                  'type': 'string',
                  'description': 'URL a navegar y analizar',
                },
              },
              'required': ['url'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'open_external_url',
            'description':
                'Abre una URL en el navegador externo (Supabase, Firebase, '
                'Stripe, login). Parámetros: url y reason.',
            'parameters': {
              'type': 'object',
              'properties': {
                'url': {'type': 'string'},
                'reason': {'type': 'string'},
              },
              'required': ['url', 'reason'],
            },
          },
        },
      ];

      final Map<String, dynamic> bodyMap = {
        'model': model, // Usar el modelo configurado
        'messages': messages,
        'temperature':
            0.3, // Reducido de 0.7 a 0.3 para mayor precisión (como Cursor agent)
        'max_tokens': 4096,
        'stream': false, // Asegurar que no es streaming
      };

      // CRÍTICO: Solo incluir tools y tool_choice si allowTools es true
      // Si allowTools es false, NO incluir NADA relacionado con tools
      if (allowTools) {
        bodyMap['tools'] = tools; // Function Calling habilitado
        bodyMap['tool_choice'] = 'auto';
      }
      // Si allowTools es false, NO agregamos tools ni tool_choice al body

      final body = jsonEncode(bodyMap);

      print('🔄 Enviando solicitud a OpenAI...');
      print('📊 Modelo: $model');
      print('💬 Mensajes: ${messages.length}');

      // Calcular tokens aproximados
      int estimatedTokens = 0;
      for (var msg in messages) {
        if (msg['content'] is String) {
          estimatedTokens += (msg['content'] as String).length ~/ 4;
        } else if (msg['content'] is List) {
          for (var item in msg['content'] as List) {
            if (item['type'] == 'text') {
              estimatedTokens += (item['text'] as String).length ~/ 4;
            } else if (item['type'] == 'image_url') {
              // Tokens de imagen ya calculados arriba
              estimatedTokens += 170; // Aproximación para imagen
            }
          }
        }
      }
      print('📊 Tokens estimados: ~$estimatedTokens');

      // Usar cliente HTTP reutilizable con timeout optimizado
      final response = await httpClient
          .post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: headers,
            body: body,
          )
          .timeout(
            const Duration(seconds: 90), // Timeout de 90 segundos
            onTimeout: () {
              print('⏱️ Timeout después de 90 segundos');
              throw TimeoutException(
                'La solicitud tardó más de 90 segundos. '
                'Esto puede deberse a:\n'
                '1. Conexión a internet lenta\n'
                '2. Alta demanda en los servidores de OpenAI\n'
                '3. Mensaje muy largo que requiere más tiempo de procesamiento',
                const Duration(seconds: 90),
              );
            },
          );

      print('📥 Respuesta recibida: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final message = data['choices'][0]['message'];

        // ✅ NUEVO: Obtener tokens usados para sistema de créditos
        int? totalTokens;
        if (data['usage'] != null) {
          totalTokens = data['usage']['total_tokens'] as int?;
          print('📊 Tokens usados: $totalTokens');
          // Notificar tokens usados
          if (totalTokens != null && onTokensUsed != null) {
            onTokensUsed(totalTokens);
          }
        }

        // Verificar si la IA quiere llamar a una función
        if (message['tool_calls'] != null && message['tool_calls'].isNotEmpty) {
          print(
            '🔧 La IA quiere ejecutar funciones: ${message['tool_calls'].length}',
          );

          // NUEVO: En lugar de ejecutar directamente, crear acciones pendientes
          // que requieren confirmación del usuario
          if (onPendingActions != null) {
            final pendingActionsList = <Map<String, dynamic>>[];
            for (var toolCall in message['tool_calls']) {
              final functionName = toolCall['function']['name'];
              final functionArgs = jsonDecode(
                toolCall['function']['arguments'],
              );
              final callId = toolCall['id'];

              // Generar descripción detallada con diff y análisis de riesgo
              final details = await _generateActionDescriptionWithDetails(
                functionName,
                functionArgs,
                projectPath,
              );

              // Verificar protección del archivo si aplica
              String? protectionWarning;
              List<String>? securityRecommendations;
              final filePath = functionArgs['file_path'] as String?;

              if (filePath != null) {
                final protection = ProjectProtectionService.canModifyFile(
                  filePath,
                  functionName,
                );

                if (!protection.allowed) {
                  // Si la operación no está permitida, agregar advertencia
                  protectionWarning =
                      '🚫 OPERACIÓN BLOQUEADA: ${protection.reason}';
                  print(
                    '🚫 Operación bloqueada por protección: $functionName en $filePath',
                  );
                } else if (protection.requiresExtraConfirmation) {
                  // Si requiere confirmación extra, agregar advertencias
                  protectionWarning =
                      ProjectProtectionService.getCriticalFileWarning(filePath);
                  securityRecommendations =
                      ProjectProtectionService.getSecurityRecommendations(
                        functionName,
                        filePath,
                      );
                  print(
                    '⚠️ Archivo crítico detectado: $filePath (requiere confirmación extra)',
                  );
                }
              }

              // Crear acción pendiente con toda la información
              final pendingAction = {
                'id':
                    DateTime.now().millisecondsSinceEpoch.toString() +
                    '_${pendingActionsList.length}',
                'functionName': functionName,
                'arguments': functionArgs,
                'description': details['description'],
                'reasoning': details['reasoning'],
                'diff': details['diff'],
                'oldContent': details['oldContent'],
                'newContent': details['newContent'],
                'toolCallId': callId,
                'timestamp': DateTime.now().toIso8601String(),
                'protectionWarning': protectionWarning,
                'securityRecommendations': securityRecommendations,
              };
              pendingActionsList.add(pendingAction);

              print('⏸️ Acción pendiente creada: $functionName');
              if (details['diff'] != null) {
                print('📊 Diff generado para: ${functionArgs['file_path']}');
              }
            }

            // Notificar al UI sobre las acciones pendientes
            print(
              '🔔 NOTIFICANDO UI sobre ${pendingActionsList.length} acciones pendientes',
            );
            onPendingActions(pendingActionsList);
            print('✅ Callback onPendingActions ejecutado');

            // NO ejecutar todavía - esperar confirmación del usuario
            // Retornar mensaje indicando que se espera confirmación
            return 'Esperando tu confirmación para ejecutar ${pendingActionsList.length} acción(es). Por favor, revisa las acciones propuestas y confirma.';
          }

          // Si no hay callback de pending actions, ejecutar directamente (fallback)
          // Ejecutar las funciones solicitadas
          final toolResults = <Map<String, dynamic>>[];
          for (var toolCall in message['tool_calls']) {
            final functionName = toolCall['function']['name'];
            final functionArgs = jsonDecode(toolCall['function']['arguments']);
            final callId = toolCall['id'];

            print(
              '🔧 Ejecutando función: $functionName con args: $functionArgs',
            );

            final result = await executeSingleTool(
              functionName,
              Map<String, dynamic>.from(functionArgs),
              projectPath,
              onFileOperation: onFileOperation,
            );

            toolResults.add({
              'tool_call_id': callId,
              'role': 'tool',
              'name': functionName,
              'content': result,
            });
          }

          // Agregar los resultados de las funciones al historial
          messages.add(message); // Agregar el mensaje con tool_calls
          messages.addAll(toolResults); // Agregar los resultados

          // Hacer una segunda llamada con los resultados
          print('🔄 Enviando resultados de funciones a la IA...');
          final secondResponse = await httpClient
              .post(
                Uri.parse('$baseUrl/chat/completions'),
                headers: headers,
                body: jsonEncode({
                  'model': model,
                  'messages': messages,
                  'temperature': 0.7,
                  'max_tokens': 4000,
                }),
              )
              .timeout(const Duration(seconds: 90));

          if (secondResponse.statusCode == 200) {
            final secondData = jsonDecode(
              utf8.decode(secondResponse.bodyBytes),
            );
            final finalContent = secondData['choices'][0]['message']['content'];
            print('✅ Funciones ejecutadas y respuesta final recibida');
            return finalContent ?? 'Archivos editados/creados exitosamente.';
          } else {
            return 'Funciones ejecutadas, pero error al obtener respuesta final.';
          }
        }

        // Si no hay function calls, devolver respuesta normal
        final content = message['content'];
        print('✅ Respuesta exitosa');
        return content ?? '';
      } else {
        // Parsear el error para dar mensajes más específicos
        final errorBody = utf8.decode(
          response.bodyBytes,
        ); // Usar UTF-8 decoding consistentemente
        String errorMessage = 'Error: ${response.statusCode}';

        print('❌ Error: ${response.statusCode}');
        print('📄 Body: $errorBody');

        try {
          final errorData = jsonDecode(errorBody);
          final error = errorData['error'];
          if (error != null) {
            final errorType = error['type']?.toString() ?? '';
            final errorCode = error['code']?.toString() ?? '';
            final message = error['message']?.toString() ?? '';

            print('🔍 Error Type: $errorType');
            print('🔍 Error Code: $errorCode');
            print('🔍 Error Message: $message');

            // Detectar errores específicos - SOLO insufficient_quota si es realmente eso
            if (errorType == 'insufficient_quota' ||
                errorCode == 'insufficient_quota') {
              // SOLO si el tipo o código es explícitamente insufficient_quota
              errorMessage = 'insufficient_quota: $message';
            } else if (message.toLowerCase().contains('insufficient_quota') &&
                !message.toLowerCase().contains('rate') &&
                !message.toLowerCase().contains('limit')) {
              // Solo si el mensaje menciona insufficient_quota Y NO menciona rate/limit
              errorMessage = 'insufficient_quota: $message';
            } else if (response.statusCode == 401 ||
                message.toLowerCase().contains('invalid api key') ||
                message.toLowerCase().contains('authentication')) {
              errorMessage = 'invalid_api_key: $message';
            } else if (response.statusCode == 429) {
              // 429 puede ser rate limit O insufficient quota - verificar el mensaje
              if (message.toLowerCase().contains('insufficient_quota') ||
                  message.toLowerCase().contains('insufficient funds') ||
                  message.toLowerCase().contains('billing') ||
                  errorType == 'insufficient_quota' ||
                  errorCode == 'insufficient_quota') {
                errorMessage = 'insufficient_quota: $message';
              } else {
                // Es un rate limit, NO insufficient quota
                errorMessage = 'rate_limit: $message';
              }
            } else if (response.statusCode == 400) {
              // 400 puede ser context_length_exceeded u otros errores
              if (message.toLowerCase().contains('context_length_exceeded') ||
                  message.toLowerCase().contains('maximum context length') ||
                  errorCode == 'context_length_exceeded') {
                errorMessage =
                    'context_length_exceeded: El mensaje es demasiado largo. Por favor, reduce el tamaño del proyecto o del mensaje.';
              } else {
                errorMessage = 'Error: $message';
              }
            } else {
              errorMessage = 'Error: $message';
            }
          }
        } catch (e) {
          print('⚠️ No se pudo parsear el error: $e');
          // Si no se puede parsear, ser más conservador - NO asumir insufficient_quota
          // Solo marcar como insufficient_quota si el body claramente lo dice
          final lowerBody = errorBody.toLowerCase();
          if ((lowerBody.contains('insufficient_quota') ||
                  lowerBody.contains('insufficient funds')) &&
              !lowerBody.contains('rate') &&
              !lowerBody.contains('limit')) {
            errorMessage = 'insufficient_quota: $errorBody';
          } else {
            // Si no está claro, marcar como error genérico
            errorMessage = 'Error: ${response.statusCode} - $errorBody';
          }
        }

        throw Exception(errorMessage);
      }
    } on TimeoutException catch (e) {
      print('⏱️ TimeoutException: ${e.message}');
      throw Exception('timeout: ${e.message}');
    } on SocketException catch (e) {
      print('🔌 SocketException: ${e.message}');
      throw Exception(
        'connection: No se pudo conectar a OpenAI. Verifica tu conexión a internet y el firewall.',
      );
    } on HttpException catch (e) {
      print('🌐 HttpException: ${e.message}');
      throw Exception('http: Error de HTTP: ${e.message}');
    } catch (e) {
      print('❌ Error general: $e');
      final text = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      if (text.startsWith('OpenAI ') ||
          text.startsWith('Tu cuenta real de OpenAI') ||
          text.startsWith('API Key de OpenAI') ||
          text.startsWith('La conversación superó') ||
          text.startsWith('Solicitud cancelada') ||
          text.startsWith('timeout:') ||
          text.startsWith('connection:') ||
          text.startsWith('http:')) {
        throw Exception(text);
      }
      throw Exception('Error al comunicarse con OpenAI: $text');
    }
  }

  Future<Map<String, dynamic>> _prepareSurgicalEdit(
    String filePath,
    String searchBlock,
    String replaceBlock,
    String? projectPath,
  ) async {
    const notFoundError =
        'Error: No se encontró el bloque search_block en el archivo. Usa read_file primero para ver las líneas exactas.';
    if (projectPath == null || projectPath.isEmpty) {
      return {'error': 'Error: No hay proyecto cargado'};
    }
    if (filePath.isEmpty || searchBlock.isEmpty) {
      return {'error': notFoundError};
    }
    final sandbox = _sandboxViolation(filePath, projectPath);
    if (sandbox != null) return {'error': sandbox};

    final fullPath =
        filePath.startsWith('/') ? filePath : '$projectPath/$filePath';
    final file = File(fullPath);
    if (!await file.exists()) {
      return {'error': 'Error: El archivo no existe: $filePath'};
    }

    final oldContent = await file.readAsString();
    int startLine = 0;
    int removedLineCount = searchBlock.split('\n').length;
    var matchedBlock = searchBlock;
    String newContent;

    final exactIndex = oldContent.indexOf(searchBlock);
    if (exactIndex >= 0) {
      if (oldContent.indexOf(searchBlock, exactIndex + searchBlock.length) >=
          0) {
        return {
          'error':
              'Error: search_block coincide más de una vez. Incluye más líneas de contexto para que el bloque sea único.',
        };
      }
      startLine = '\n'.allMatches(oldContent.substring(0, exactIndex)).length;
      newContent = oldContent.replaceRange(
        exactIndex,
        exactIndex + searchBlock.length,
        replaceBlock,
      );
    } else {
      // Fallback tolerante únicamente a espacios al inicio/final de cada línea.
      final currentLines = oldContent.split('\n');
      final searchLines = searchBlock.split('\n');
      final matchingStarts = <int>[];
      for (var start = 0;
          start + searchLines.length <= currentLines.length;
          start++) {
        var matches = true;
        for (var offset = 0; offset < searchLines.length; offset++) {
          if (currentLines[start + offset].trim() !=
              searchLines[offset].trim()) {
            matches = false;
            break;
          }
        }
        if (matches) matchingStarts.add(start);
      }

      if (matchingStarts.isEmpty) return {'error': notFoundError};
      if (matchingStarts.length > 1) {
        return {
          'error':
              'Error: search_block coincide más de una vez aun ignorando espacios. Incluye más contexto para que sea único.',
        };
      }

      startLine = matchingStarts.single;
      removedLineCount = searchLines.length;
      matchedBlock = currentLines
          .sublist(startLine, startLine + removedLineCount)
          .join('\n');
      currentLines.replaceRange(
        startLine,
        startLine + removedLineCount,
        replaceBlock.split('\n'),
      );
      newContent = currentLines.join('\n');
    }

    return {
      'oldContent': oldContent,
      'newContent': newContent,
      'startLine': startLine, // 0-based
      'diff': _generateSurgicalDiff(
        oldContent,
        matchedBlock,
        replaceBlock,
        filePath,
        startLine,
        removedLineCount,
      ),
    };
  }

  String _generateSurgicalDiff(
    String oldContent,
    String searchBlock,
    String replaceBlock,
    String fileName,
    int startLine,
    int removedLineCount,
  ) {
    final oldLines = oldContent.split('\n');
    final beforeStart = (startLine - 3).clamp(0, oldLines.length);
    final afterStart =
        (startLine + removedLineCount).clamp(0, oldLines.length);
    final afterEnd = (afterStart + 3).clamp(0, oldLines.length);
    final buffer = StringBuffer()
      ..writeln('--- $fileName')
      ..writeln('+++ $fileName')
      ..writeln('@@ ${startLine + 1} @@');

    for (var index = beforeStart; index < startLine; index++) {
      buffer.writeln('  ${oldLines[index]}');
    }
    for (final line in searchBlock.split('\n')) {
      buffer.writeln('- $line');
    }
    for (final line in replaceBlock.split('\n')) {
      buffer.writeln('+ $line');
    }
    for (var index = afterStart; index < afterEnd; index++) {
      buffer.writeln('  ${oldLines[index]}');
    }
    return buffer.toString().trimRight();
  }

  /// Estima la línea 1-based donde empezará el edit (para subrayar en el editor).
  Future<int?> _estimateFocusLine(
    String filePath,
    String searchBlock,
    String? projectPath,
  ) async {
    if (searchBlock.trim().isEmpty) return 1;
    try {
      final fullPath = filePath.startsWith('/')
          ? filePath
          : (projectPath != null ? '$projectPath/$filePath' : filePath);
      final file = File(fullPath);
      if (!await file.exists()) return 1;
      final content = await file.readAsString();
      final idx = content.indexOf(searchBlock);
      if (idx < 0) {
        // Fallback: primera línea no vacía del search_block.
        final needle = searchBlock
            .split('\n')
            .map((l) => l.trim())
            .firstWhere((l) => l.isNotEmpty, orElse: () => '');
        if (needle.isEmpty) return 1;
        final idx2 = content.indexOf(needle);
        if (idx2 < 0) return 1;
        return content.substring(0, idx2).split('\n').length;
      }
      return content.substring(0, idx).split('\n').length;
    } catch (_) {
      return 1;
    }
  }

  Future<String> _executeSurgicalEdit(
    String filePath,
    String searchBlock,
    String replaceBlock,
    String? projectPath,
  ) async {
    final edit = await _executeSurgicalEditDetailed(
      filePath,
      searchBlock,
      replaceBlock,
      projectPath,
    );
    return edit.message;
  }

  Future<({String message, int? focusLine})> _executeSurgicalEditDetailed(
    String filePath,
    String searchBlock,
    String replaceBlock,
    String? projectPath,
  ) async {
    final prepared = await _prepareSurgicalEdit(
      filePath,
      searchBlock,
      replaceBlock,
      projectPath,
    );
    final error = prepared['error'] as String?;
    if (error != null) return (message: error, focusLine: null);
    final added = replaceBlock.isEmpty ? 0 : replaceBlock.split('\n').length;
    final removed = searchBlock.isEmpty ? 0 : searchBlock.split('\n').length;
    final writeResult = await _executeWriteFile(
      filePath,
      prepared['newContent'] as String,
      projectPath,
    );
    if (writeResult.toLowerCase().startsWith('error')) {
      return (message: writeResult, focusLine: null);
    }
    final start0 = prepared['startLine'] as int? ?? 0;
    return (
      message: 'Edited $filePath +$added -$removed',
      focusLine: start0 + 1, // editor 1-based
    );
  }

  /// Reescribe un archivo completo con protección y backup.
  Future<String> _executeWriteFile(
    String filePath,
    String content,
    String? projectPath,
  ) async {
    try {
      if (projectPath == null || projectPath.isEmpty) {
        return 'Error: No hay proyecto cargado';
      }

      // Construir ruta completa si es relativa
      final fullPath = filePath.startsWith('/')
          ? filePath
          : '$projectPath/$filePath';

      // PROTECCIÓN CRÍTICA: Verificar que el archivo está dentro del proyecto
      final normalizedFullPath = fullPath.replaceAll('\\', '/');
      final normalizedProjectPath = projectPath.replaceAll('\\', '/');

      if (!normalizedFullPath.startsWith(normalizedProjectPath)) {
        return 'Error: No se pueden editar archivos fuera del proyecto';
      }

      // PROTECCIÓN: Verificar con ProjectProtectionService
      final protection = ProjectProtectionService.canEditFile(fullPath);
      if (!protection.allowed) {
        return 'Error: ${protection.reason}';
      }

      // ROLLBACK: Crear backup antes de modificar
      print('💾 Creando backup antes de editar: $fullPath');
      final backup = await BackupService.createBackup(fullPath, projectPath);
      if (backup != null) {
        print('✅ Backup creado exitosamente: ${backup.backupPath}');
      } else {
        print('⚠️ No se pudo crear backup (el archivo puede no existir aún)');
      }

      final file = File(fullPath);
      final before = await file.exists() ? await file.readAsString() : '';
      final oldLines = before.isEmpty && !await file.exists()
          ? 0
          : before.split('\n').length;
      await file.writeAsString(content);
      final newLines = content.split('\n').length;
      final added = newLines > oldLines ? newLines - oldLines : 0;
      final removed = oldLines > newLines ? oldLines - newLines : 0;
      AgentDiffReviewService().recordEdit(
        filePath: fullPath,
        before: before,
        after: content,
      );
      print('✅ Archivo editado: $fullPath');
      return 'Edited $filePath +$added -$removed';
    } catch (e) {
      print('❌ Error editando archivo: $e');
      return 'Error al editar archivo: $e';
    }
  }

  /// Ejecuta la función create_file (PROTEGIDO - solo archivos del proyecto)
  /// Ejecuta create_folder para crear directorios
  Future<String> _executeCreateFolder(
    String folderPath,
    String? projectPath,
  ) async {
    try {
      if (projectPath == null || projectPath.isEmpty) {
        return 'Error: No hay proyecto cargado';
      }

      // Construir ruta completa si es relativa
      final fullPath = folderPath.startsWith('/')
          ? folderPath
          : '$projectPath/$folderPath';

      // PROTECCIÓN CRÍTICA: Verificar que la carpeta está dentro del proyecto
      final normalizedFullPath = fullPath.replaceAll('\\', '/');
      final normalizedProjectPath = projectPath.replaceAll('\\', '/');

      if (!normalizedFullPath.startsWith(normalizedProjectPath)) {
        return 'Error: No se pueden crear carpetas fuera del proyecto';
      }

      final directory = Directory(fullPath);

      if (!await directory.exists()) {
        await directory.create(recursive: true);
        print('✅ Carpeta creada: $fullPath');
        return 'Carpeta creada exitosamente: $folderPath';
      } else {
        print('ℹ️ La carpeta ya existe: $fullPath');
        return 'La carpeta ya existe: $folderPath';
      }
    } catch (e) {
      print('❌ Error creando carpeta: $e');
      return 'Error al crear carpeta: $e';
    }
  }

  Future<String> _executeCreateFile(
    String filePath,
    String content,
    String? projectPath,
  ) async {
    try {
      if (projectPath == null || projectPath.isEmpty) {
        return 'Error: No hay proyecto cargado';
      }

      // Construir ruta completa si es relativa
      final fullPath = filePath.startsWith('/')
          ? filePath
          : '$projectPath/$filePath';

      // PROTECCIÓN CRÍTICA: Verificar que el archivo está dentro del proyecto
      final normalizedFullPath = fullPath.replaceAll('\\', '/');
      final normalizedProjectPath = projectPath.replaceAll('\\', '/');

      if (!normalizedFullPath.startsWith(normalizedProjectPath)) {
        return 'Error: No se pueden crear archivos fuera del proyecto';
      }

      final file = File(fullPath);

      // Crear directorios si no existen
      final directory = file.parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        print('ℹ️ Creando directorio automáticamente: ${directory.path}');
      }

      final before = await file.exists() ? await file.readAsString() : '';
      await file.writeAsString(content);
      AgentDiffReviewService().recordEdit(
        filePath: fullPath,
        before: before,
        after: content,
      );
      final lines = content.split('\n').length;
      print('✅ Archivo creado: $fullPath');
      return 'Created $filePath +$lines -0';
    } catch (e) {
      print('❌ Error creando archivo: $e');
      return 'Error al crear archivo: $e';
    }
  }

  /// Ejecuta la función read_file
  Future<String> _executeReadFile(String filePath, String? projectPath) async {
    try {
      // Construir ruta completa si es relativa
      final fullPath = filePath.startsWith('/')
          ? filePath
          : (projectPath != null ? '$projectPath/$filePath' : filePath);

      final file = File(fullPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        print('✅ Archivo leído: $fullPath');
        return content;
      } else {
        return 'Error: El archivo no existe: $filePath';
      }
    } catch (e) {
      print('❌ Error leyendo archivo: $e');
      return 'Error al leer archivo: $e';
    }
  }

  /// Prepara read_image: valida sandbox + extensión y arma mensaje multimodal.
  Future<({String toolResult, Map<String, dynamic>? visionUserMessage})>
      _prepareReadImage(String filePath, String? projectPath) async {
    try {
      if (projectPath == null || projectPath.isEmpty) {
        return (
          toolResult: 'Error: No hay proyecto cargado',
          visionUserMessage: null,
        );
      }
      if (filePath.trim().isEmpty) {
        return (
          toolResult: 'Error: file_path vacío',
          visionUserMessage: null,
        );
      }

      final resolved = _resolveProjectImagePath(filePath, projectPath);
      if (resolved.error != null) {
        return (toolResult: resolved.error!, visionUserMessage: null);
      }

      final fullPath = resolved.fullPath!;
      final displayPath = resolved.relativePath ?? filePath;
      final file = File(fullPath);
      if (!await file.exists()) {
        return (
          toolResult: 'Error: El archivo no existe: $displayPath',
          visionUserMessage: null,
        );
      }

      final optimized = await _optimizeImage(file);
      final base64Data = base64Encode(optimized.bytes);
      final mimeType = optimized.mimeType;

      print(
        '🖼️ read_image: $displayPath → ${(optimized.bytes.length / 1024).toStringAsFixed(1)}KB ($mimeType)',
      );

      final visionUserMessage = <String, dynamic>{
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text':
                'Aquí está la imagen solicitada del proyecto ($displayPath):',
          },
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:$mimeType;base64,$base64Data',
              'detail': 'high',
            },
          },
        ],
      };

      return (
        toolResult:
            'Imagen cargada exitosamente: $displayPath. Analízala en el siguiente mensaje.',
        visionUserMessage: visionUserMessage,
      );
    } catch (e) {
      return (
        toolResult: 'Error al leer imagen: $e',
        visionUserMessage: null,
      );
    }
  }

  /// Resuelve y valida que [filePath] esté dentro de [projectPath] y sea imagen.
  ({String? fullPath, String? relativePath, String? error})
      _resolveProjectImagePath(String filePath, String projectPath) {
    final normalizedProject = projectPath.replaceAll('\\', '/');
    final projectRoot = normalizedProject.endsWith('/')
        ? normalizedProject.substring(0, normalizedProject.length - 1)
        : normalizedProject;

    String candidate;
    if (filePath.startsWith('/')) {
      candidate = filePath.replaceAll('\\', '/');
    } else {
      candidate = '$projectRoot/${filePath.replaceAll('\\', '/')}';
    }

    // Normalizar ".." relativos de forma segura
    final parts = <String>[];
    for (final segment in candidate.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isEmpty) {
          return (
            fullPath: null,
            relativePath: null,
            error: 'Error: Ruta inválida fuera del proyecto: $filePath',
          );
        }
        parts.removeLast();
        continue;
      }
      parts.add(segment);
    }
    final fullPath = '/${parts.join('/')}';

    if (fullPath != projectRoot && !fullPath.startsWith('$projectRoot/')) {
      return (
        fullPath: null,
        relativePath: null,
        error: 'Error: La imagen debe estar dentro del proyecto: $filePath',
      );
    }

    final lower = fullPath.toLowerCase();
    final hasExt = _imageExtensions.any(lower.endsWith);
    if (!hasExt) {
      return (
        fullPath: null,
        relativePath: null,
        error:
            'Error: Extensión no soportada. Usa .png, .jpg, .jpeg, .webp o .gif: $filePath',
      );
    }

    final relative = fullPath == projectRoot
        ? filePath
        : fullPath.substring(projectRoot.length + 1);
    return (fullPath: fullPath, relativePath: relative, error: null);
  }

  /// Ejecuta la función compile_project
  Future<String> _executeCompileProject(
    String? platform,
    String? mode,
    String? projectPath,
  ) async {
    try {
      if (projectPath == null || projectPath.isEmpty) {
        return 'Error: No hay proyecto cargado';
      }

      final available = await _detectFlutterPlatforms(projectPath);
      // Respetar selector del IDE; NUNCA default a web si el usuario eligió otra.
      final fromSelector = PlatformService().selectedPlatform.toLowerCase();
      var requested = (platform ?? fromSelector).toLowerCase().trim();
      if (requested.isEmpty) requested = 'web';

      final base = ProjectPlatformSupport.basePlatform(requested);
      if (!available.contains(base)) {
        // Solo para ejecutar: elegir carpeta existente. NO tocar el dropdown.
        if (available.contains('web')) {
          requested = 'web';
        } else if (available.contains('macos')) {
          requested = 'macos';
        } else if (available.isNotEmpty) {
          requested = available.first;
        } else {
          return '''
❌ Compilación cancelada: no hay plataformas Flutter detectadas en el proyecto.
Añade soporte con: flutter create --platforms=web .
'''.trim();
        }
      }
      // Importante: compile_project NO llama setPlatform. El selector solo lo
      // cambia el usuario o ide_control(set_platform). Así Android no "salta" a Web.

      final debug = DebugConsoleService();
      debug.setRunning(true);
      debug.setCompilationProgress(
        0.1,
        ProjectPlatformSupport.isEmbeddedMobilePreview(requested)
            ? 'Compilando ${ProjectPlatformSupport.humanLabel(requested)}…'
            : requested == 'web'
                ? 'Compilando Web Preview…'
                : 'Compilando para $requested…',
      );

      final output = StringBuffer();
      final errorOutput = StringBuffer();

      try {
        // Espera el resultado real de compilación en TODAS las plataformas
        // (Web, Android/iOS Preview, Android/iOS nativo, macOS, etc.).
        final result = await RunDebugService.runFlutterProject(
          mode: mode ?? 'debug',
          platform: requested,
          onOutput: (data) => output.write(data),
          onError: (error) => errorOutput.write(error),
        );

        final success = result['success'] == true;
        final exitCode = result['exitCode'] as int? ?? (success ? 0 : 1);
        final previewUrl = result['previewUrl']?.toString();
        final errText = [
          errorOutput.toString(),
          if ((result['error']?.toString() ?? '').isNotEmpty)
            result['error'].toString(),
        ].where((s) => s.trim().isNotEmpty).join('\n');
        final outText = output.toString().isNotEmpty
            ? output.toString()
            : (result['output']?.toString() ?? '');

        final compressedErr = _compressTerminalOutput(errText);
        final compressedOut = _compressTerminalOutput(outText);
        final lowerErr = errText.toLowerCase();
        final lowerOut = outText.toLowerCase();
        final hasFatalErrors = !success ||
            exitCode != 0 ||
            lowerOut.contains('failed to compile application') ||
            lowerErr.contains('failed to compile application') ||
            lowerOut.contains('no devices found') ||
            lowerOut.contains('not configured for');

        if (hasFatalErrors) {
          return '''
❌ Compilación/ejecución falló (plataforma: $requested, modo: ${mode ?? 'debug'}, exitCode: $exitCode).
Plataformas disponibles en el proyecto: ${available.join(', ')}.

Errors:
$compressedErr

Output:
$compressedOut

Si el error está dentro de .pub-cache, NO repitas flutter clean/pub get: fija la versión exacta sin ^ en pubspec.yaml o ejecuta flutter pub cache repair. Si falla por falta de emulador nativo, usa Android/iOS (Preview) con compile_project(platform: "android"|"ios"), NO Web.
'''.trim();
        }

        if (previewUrl != null && previewUrl.isNotEmpty) {
          DebugConsoleService().setAppUrl(previewUrl);
          DebugConsoleService().setRunning(true);
          DebugConsoleService().setCompilationProgress(
            1.0,
            requested == 'web'
                ? 'Aplicación web ejecutándose'
                : '${ProjectPlatformSupport.humanLabel(requested)} en Preview',
          );
          return '✅ App compilada y ejecutándose en Preview ($requested): '
              '$previewUrl (mode: ${mode ?? 'debug'})\n\n'
              'Output:\n$compressedOut';
        }

        return '✅ App compilada y ejecutándose (mode: ${mode ?? 'debug'}, '
            'platform: $requested)\n\nOutput:\n$compressedOut';
      } catch (e) {
        return '''
❌ Error al compilar (plataforma: $requested): $e
Plataformas disponibles: ${available.join(', ')}.

Output:
${_compressTerminalOutput(output.toString())}

Errors:
${_compressTerminalOutput(errorOutput.toString())}

Si falta emulador nativo: compile_project(platform: "android"|"ios") Preview — NO Web.
'''.trim();
      }
    } catch (e) {
      print('❌ Error en compile_project: $e');
      return 'Error al compilar proyecto: $e';
    }
  }

  /// Detecta carpetas de plataforma Flutter presentes en el proyecto.
  Future<List<String>> _detectFlutterPlatforms(String projectPath) async {
    const platforms = ['macos', 'web', 'ios', 'android', 'linux', 'windows'];
    final found = <String>[];
    for (final p in platforms) {
      if (await Directory('$projectPath/$p').exists()) {
        found.add(p);
      }
    }
    return found;
  }

  /// Ejecuta la función execute_command
  Future<String> _executeCommand(
    String command,
    String? workingDirectory,
    String? projectPath,
  ) async {
    try {
      final workingDir =
          workingDirectory ?? projectPath ?? Directory.current.path;

      print('🔧 Ejecutando comando (shell): $command en $workingDir');

      final ProcessResult result;
      if (Platform.isMacOS || Platform.isLinux) {
        final shell = Platform.isMacOS || File('/bin/zsh').existsSync()
            ? '/bin/zsh'
            : '/bin/sh';
        result = await Process.run(
          shell,
          ['-lc', command],
          workingDirectory: workingDir,
        ).timeout(const Duration(minutes: 3));
      } else {
        result = await Process.run(
          'cmd',
          ['/c', command],
          workingDirectory: workingDir,
          runInShell: true,
        ).timeout(const Duration(minutes: 3));
      }

      final output = StringBuffer();
      output.writeln('Comando: $command');
      output.writeln('Directorio: $workingDir');
      output.writeln('Exit Code: ${result.exitCode}');

      if (result.stdout.toString().isNotEmpty) {
        output.writeln('\nOutput:');
        output.writeln(result.stdout.toString());
      }

      if (result.stderr.toString().isNotEmpty) {
        output.writeln('\nErrors:');
        output.writeln(result.stderr.toString());
      }

      final compressed = _compressTerminalOutput(output.toString());
      if (result.exitCode == 0) {
        return 'Ran successfully:\n$compressed';
      } else {
        return '❌ Command failed (exit code: ${result.exitCode}):\n$compressed';
      }
    } catch (e) {
      print('❌ Error ejecutando comando: $e');
      return 'Error al ejecutar comando: $e';
    }
  }

  /// Ejecuta la función download_file
  Future<String> _executeDownloadFile(
    String url,
    String? targetPath,
    String? projectPath,
  ) async {
    try {
      if (projectPath == null || projectPath.isEmpty) {
        return 'Error: No hay proyecto cargado';
      }

      final result = await WebNavigationService.downloadFile(
        url,
        fileName: targetPath?.split('/').last,
        targetDirectory: targetPath != null
            ? '$projectPath/${targetPath.substring(0, targetPath.lastIndexOf('/'))}'
            : projectPath,
      );

      if (result['success'] == true) {
        return '✅ Archivo descargado exitosamente: ${result['filePath']}';
      } else {
        return '❌ Error al descargar archivo: ${result['error']}';
      }
    } catch (e) {
      print('❌ Error descargando archivo: $e');
      return 'Error al descargar archivo: $e';
    }
  }

  /// Ejecuta la función navigate_web
  Future<String> _executeNavigateWeb(String url) async {
    try {
      print('🌐 Navegando a: $url');

      final result = await WebNavigationService.navigateToUrl(url);

      if (result['success'] == true) {
        final content = result['content'] as String? ?? '';
        final title = result['title'] as String? ?? '';

        // Limitar el contenido a 5000 caracteres para no exceder tokens
        final limitedContent = content.length > 5000
            ? '${content.substring(0, 5000)}...\n\n[Contenido truncado - total: ${content.length} caracteres]'
            : content;

        return '✅ Navegación exitosa:\n\nURL: $url\nTítulo: $title\n\nContenido:\n$limitedContent';
      } else {
        return '❌ Error al navegar: ${result['error']}';
      }
    } catch (e) {
      print('❌ Error navegando: $e');
      return 'Error al navegar a la URL: $e';
    }
  }

  /// Abre una URL en el navegador externo del sistema (login / dashboards).
  Future<String> _executeOpenExternalUrl(String url, String reason) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return 'Error: url vacía en open_external_url';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'Error: URL inválida (solo http/https): $trimmed';
    }
    try {
      final ok = await canLaunchUrl(uri);
      if (!ok) {
        return '❌ No se puede abrir la URL en este sistema: $trimmed';
      }
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return '❌ launchUrl devolvió false para: $trimmed';
      }
      final why = reason.trim().isEmpty ? '(sin motivo)' : reason.trim();
      return '✅ Navegador externo abierto\nURL: $trimmed\nMotivo: $why\n'
          'Guía al usuario con los pasos siguientes (copiar keys, login, etc.).';
    } catch (e) {
      return 'Error al abrir URL externa: $e';
    }
  }

  /// Genera una descripción amigable de la acción basada en el tipo y argumentos
  /// Incluye análisis de riesgo, diff y razonamiento
  Future<Map<String, dynamic>> _generateActionDescriptionWithDetails(
    String functionName,
    Map<String, dynamic> arguments,
    String? projectPath,
  ) async {
    final filePath = arguments['file_path'] as String?;
    String description = '';
    String? reasoning;
    String? diff;
    String? oldContent;
    String? newContent;

    switch (functionName) {
      case 'edit_file':
        description =
            'Reemplazar un bloque en "${filePath ?? 'archivo'}"';
        reasoning =
            'Aplicar una edición quirúrgica sin reescribir el resto del archivo';

        if (filePath != null && projectPath != null) {
          try {
            final prepared = await _prepareSurgicalEdit(
              filePath,
              arguments['search_block'] as String? ?? '',
              arguments['replace_block'] as String? ?? '',
              projectPath,
            );
            if (prepared['error'] == null) {
              oldContent = prepared['oldContent'] as String?;
              newContent = prepared['newContent'] as String?;
              diff = prepared['diff'] as String?;
            } else {
              reasoning = prepared['error'] as String;
            }
          } catch (e) {
            print('⚠️ No se pudo generar diff: $e');
          }
        }
        break;

      case 'write_file':
        description =
            'Reescribir completamente "${filePath ?? 'archivo'}"';
        reasoning =
            'Reemplazar todo el contenido cuando una edición por bloque no es apropiada';
        if (filePath != null && projectPath != null) {
          oldContent = await _executeReadFile(filePath, projectPath);
          newContent = arguments['content'] as String?;
          if (newContent != null) {
            diff = _generateDiff(oldContent, newContent, filePath);
          }
        }
        break;

      case 'create_file':
        description = 'Crear nuevo archivo "${filePath ?? 'nuevo archivo'}"';
        reasoning = 'Crear archivo nuevo con código inicial';
        newContent = arguments['content'] as String?;
        break;

      case 'read_file':
        description =
            'Leer el contenido del archivo "${filePath ?? 'archivo'}"';
        reasoning = 'Analizar código existente para entender el contexto';
        break;

      case 'read_image':
        description =
            'Inspeccionar visualmente la imagen "${filePath ?? 'imagen'}"';
        reasoning =
            'Analizar capturas, assets o diseños del proyecto con visión';
        break;

      case 'compile_project':
        final platform = arguments['platform'] as String? ?? 'macos';
        final mode = arguments['mode'] as String? ?? 'debug';
        description = 'Compilar proyecto para $platform en modo $mode';
        reasoning =
            'Verificar que el código compile correctamente y detectar errores';
        break;

      case 'execute_command':
        final command = arguments['command'] as String? ?? 'comando';
        description = 'Ejecutar comando: $command';
        reasoning = 'Ejecutar operación del sistema necesaria para la tarea';
        break;

      case 'download_file':
        final url = arguments['url'] as String? ?? 'URL';
        description = 'Descargar archivo desde: $url';
        reasoning = 'Obtener recurso externo necesario para el proyecto';
        break;

      case 'navigate_web':
        final url = arguments['url'] as String? ?? 'URL';
        description = 'Navegar a: $url';
        reasoning = 'Obtener información actualizada desde la web';
        break;

      case 'open_external_url':
        final url = arguments['url'] as String? ?? 'URL';
        final reason = arguments['reason'] as String? ?? '';
        description = 'Abrir en navegador: $url';
        reasoning = reason.isEmpty
            ? 'Abrir portal externo (login / dashboard / docs)'
            : reason;
        break;

      default:
        description = 'Ejecutar: $functionName';
        reasoning = 'Operación personalizada solicitada';
    }

    return {
      'description': description,
      'reasoning': reasoning,
      'diff': diff,
      'oldContent': oldContent,
      'newContent': newContent,
    };
  }

  /// Genera un diff legible entre dos versiones de un archivo
  String _generateDiff(String oldContent, String newContent, String fileName) {
    final oldLines = oldContent.split('\n');
    final newLines = newContent.split('\n');

    final buffer = StringBuffer();
    buffer.writeln('--- $fileName (original)');
    buffer.writeln('+++ $fileName (modificado)');
    buffer.writeln('');

    int addedLines = 0;
    int removedLines = 0;

    // Algoritmo simple de diff línea por línea
    final maxLines = oldLines.length > newLines.length
        ? oldLines.length
        : newLines.length;

    for (int i = 0; i < maxLines; i++) {
      final oldLine = i < oldLines.length ? oldLines[i] : null;
      final newLine = i < newLines.length ? newLines[i] : null;

      if (oldLine == newLine && oldLine != null) {
        // Línea sin cambios (mostrar solo algunas para contexto)
        if (i < 3 ||
            i > maxLines - 3 ||
            (i > 0 && oldLines[i - 1] != newLines.elementAtOrNull(i - 1))) {
          buffer.writeln('  ${i + 1} | $oldLine');
        }
      } else if (oldLine != null && newLine != null && oldLine != newLine) {
        // Línea modificada
        buffer.writeln('- ${i + 1} | $oldLine');
        buffer.writeln('+ ${i + 1} | $newLine');
        removedLines++;
        addedLines++;
      } else if (oldLine == null && newLine != null) {
        // Línea añadida
        buffer.writeln('+ ${i + 1} | $newLine');
        addedLines++;
      } else if (oldLine != null && newLine == null) {
        // Línea eliminada
        buffer.writeln('- ${i + 1} | $oldLine');
        removedLines++;
      }
    }

    buffer.writeln('');
    buffer.writeln('Resumen: +$addedLines líneas, -$removedLines líneas');

    return buffer.toString();
  }

  /// Versión síncrona simple de descripción (para compatibilidad)
  String _generateActionDescription(
    String functionName,
    Map<String, dynamic> arguments,
  ) {
    switch (functionName) {
      case 'edit_file':
        final filePath = arguments['file_path'] as String? ?? 'archivo';
        return 'Editar el archivo "$filePath" con el nuevo código proporcionado.';
      case 'create_file':
        final filePath = arguments['file_path'] as String? ?? 'nuevo archivo';
        return 'Crear el archivo "$filePath" con el código proporcionado.';
      case 'read_file':
        final filePath = arguments['file_path'] as String? ?? 'archivo';
        return 'Leer el contenido del archivo "$filePath".';
      case 'read_image':
        final filePath = arguments['file_path'] as String? ?? 'imagen';
        return 'Inspeccionar visualmente la imagen "$filePath".';
      case 'compile_project':
        final platform = arguments['platform'] as String? ?? 'macos';
        final mode = arguments['mode'] as String? ?? 'debug';
        return 'Compilar el proyecto para $platform en modo $mode.';
      case 'execute_command':
        final command = arguments['command'] as String? ?? 'comando';
        return 'Ejecutar el comando: $command';
      case 'download_file':
        final url = arguments['url'] as String? ?? 'URL';
        return 'Descargar archivo desde: $url';
      case 'navigate_web':
        final url = arguments['url'] as String? ?? 'URL';
        return 'Navegar a la URL: $url y analizar su contenido.';
      case 'open_external_url':
        final url = arguments['url'] as String? ?? 'URL';
        final reason = arguments['reason'] as String? ?? '';
        return reason.isEmpty
            ? 'Abrir en el navegador: $url'
            : 'Abrir $url ($reason)';
      default:
        return 'Ejecutar acción: $functionName';
    }
  }

  /// Verifica el saldo y estado de la cuenta de OpenAI
  Future<Map<String, dynamic>> checkAccountStatus() async {
    try {
      // Intentar hacer una llamada simple a la API para verificar el estado
      final response = await httpClient
          .get(
            Uri.parse('$baseUrl/models'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'User-Agent': 'VoryxelCode/1.0',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // La API funciona, la cuenta tiene acceso
        return {
          'success': true,
          'hasAccess': true,
          'message': 'API Key válida y funcionando',
        };
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'hasAccess': false,
          'error': 'API Key inválida o expirada',
          'statusCode': 401,
        };
      } else if (response.statusCode == 429) {
        // Verificar si es rate limit o insufficient quota
        final errorBody = response.body;
        if (errorBody.toLowerCase().contains('insufficient_quota') ||
            errorBody.toLowerCase().contains('insufficient funds') ||
            errorBody.toLowerCase().contains('billing')) {
          return {
            'success': false,
            'hasAccess': false,
            'error': 'Saldo insuficiente',
            'statusCode': 429,
            'isQuotaError': true,
          };
        } else {
          return {
            'success': false,
            'hasAccess': true,
            'error': 'Límite de tasa alcanzado (espera unos momentos)',
            'statusCode': 429,
            'isQuotaError': false,
          };
        }
      } else {
        return {
          'success': false,
          'hasAccess': false,
          'error': 'Error desconocido: ${response.statusCode}',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'hasAccess': false,
        'error': 'Error al verificar: $e',
      };
    }
  }

  Future<String> generateCode({
    required String instructions,
    String? filePath,
    String? currentContent,
    String? context,
  }) async {
    try {
      String prompt =
          '''
Eres un asistente de programación experto. Tu tarea es ACTUAR DIRECTAMENTE creando o editando código según las instrucciones del usuario.

${filePath != null ? 'Archivo objetivo: $filePath' : ''}
${context != null ? 'Contexto del proyecto:\n$context' : ''}

Instrucciones del usuario: $instructions

${currentContent != null ? 'Contenido actual del archivo:\n```\n$currentContent\n```\n\n⚠️ ACTÚA DIRECTAMENTE: Proporciona el código completo editado INMEDIATAMENTE. No des instrucciones, muestra el código corregido completo.' : '⚠️ ACTÚA DIRECTAMENTE: Crea el código completo desde cero INMEDIATAMENTE. No des instrucciones, muestra el código completo.'}

⚠️ REGLAS CRÍTICAS - ACTÚA DIRECTAMENTE:
- NO digas "deberías hacer..." o "necesitas...", en su lugar MUESTRA el código completo
- NO des pasos o instrucciones, PROPORCIONA EL CÓDIGO COMPLETO Y FUNCIONAL
- Proporciona el código completo y funcional INMEDIATAMENTE
- Si es un archivo nuevo, incluye todas las importaciones y dependencias necesarias
- El código debe estar listo para usar, sin comentarios explicativos fuera del código
- Usa bloques de código con el formato: ```language\ncódigo\n```
- Si hay múltiples archivos, sepáralos claramente
- El usuario quiere VER el código corregido, no instrucciones sobre cómo corregirlo
''';

      final response = await sendMessage(message: prompt);
      return response;
    } catch (e) {
      throw Exception('Error al generar código: $e');
    }
  }

  /// Verifica si un modelo soporta visión (análisis de imágenes)
  bool _supportsVision(String modelName) {
    final visionModels = [
      'gpt-4.1',
      'gpt-4.1-mini',
      'gpt-4o',
      'gpt-4o-mini',
      'gpt-4-turbo',
      'gpt-4-vision-preview',
      'gpt-4',
      'o4-mini',
      'o3',
    ];

    final lower = modelName.toLowerCase();
    // Ordenar por longitud desc. para que gpt-4.1-mini / gpt-4o matcheen antes que gpt-4
    final sorted = [...visionModels]
      ..sort((a, b) => b.length.compareTo(a.length));
    return sorted.any((m) => lower.contains(m.toLowerCase()));
  }

  /// MIME real según extensión del archivo.
  String _mimeTypeForImagePath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'image/jpeg';
  }

  /// Optimiza una imagen antes de enviarla a OpenAI.
  /// Si pesa >4 MB, redimensiona a máx. 2048px de ancho y comprime a JPEG.
  Future<({Uint8List bytes, String mimeType})> _optimizeImage(
    File imageFile,
  ) async {
    final originalMime = _mimeTypeForImagePath(imageFile.path);
    try {
      final bytes = await imageFile.readAsBytes();
      final sizeKB = bytes.length / 1024;
      const maxBytes = 4 * 1024 * 1024; // 4 MB

      if (bytes.length <= maxBytes) {
        print('✅ Tamaño de imagen: ${sizeKB.toStringAsFixed(1)}KB ($originalMime)');
        return (bytes: bytes, mimeType: originalMime);
      }

      print(
        '⚠️ Imagen >4MB (${sizeKB.toStringAsFixed(1)}KB) → redimensionando a máx. 2048px…',
      );
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        print('⚠️ No se pudo decodificar; enviando original');
        return (bytes: bytes, mimeType: originalMime);
      }

      img.Image resized = decoded;
      if (decoded.width > 2048) {
        resized = img.copyResize(
          decoded,
          width: 2048,
          interpolation: img.Interpolation.average,
        );
      } else if (decoded.height > 2048 && decoded.width <= 2048) {
        // Mantener proporción si el alto es el eje dominante
        final newWidth =
            ((2048 / decoded.height) * decoded.width).round().clamp(1, 2048);
        resized = img.copyResize(
          decoded,
          width: newWidth,
          height: 2048,
          interpolation: img.Interpolation.average,
        );
      }

      // JPEG reduce peso de forma fiable tras el resize
      var encoded = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
      if (encoded.length > maxBytes) {
        encoded = Uint8List.fromList(img.encodeJpg(resized, quality: 70));
      }
      print(
        '✅ Imagen comprimida: ${(encoded.length / 1024).toStringAsFixed(1)}KB (image/jpeg)',
      );
      return (bytes: encoded, mimeType: 'image/jpeg');
    } catch (e) {
      print('❌ Error procesando imagen: $e');
      final fallback = await imageFile.readAsBytes();
      return (bytes: fallback, mimeType: originalMime);
    }
  }

  /// Estima tokens de una imagen según documentación de OpenAI
  /// Fórmula: base_tokens + (tiles * 170) donde tiles = (width/512) * (height/512)
  int _estimateImageTokens(int imageSizeBytes) {
    // Estimación aproximada basada en tamaño
    // Una imagen de 512x512 ≈ 85 tokens
    // Una imagen de 1024x1024 ≈ 170 tokens (detail: high)

    // Estimación conservadora: ~1 token por 100 bytes de base64
    // Base64 es ~33% más grande que binario
    final base64Size = imageSizeBytes * 1.33;
    final estimatedTokens = (base64Size / 100).ceil();

    // Mínimo 85 tokens (imagen pequeña)
    // Máximo razonable: 2000 tokens (imagen muy grande)
    return estimatedTokens.clamp(85, 2000);
  }

  /// System prompt base del modo Agente — 100% estático (Prompt Caching).
  /// Sin reloj, sin projectPath, sin logs ni archivo abierto.
  /// Se combina después con [ProjectRulesService.loadProjectInstructions].
  static String _cursorAgentSystemPrompt() {
    return '''
Eres un AI Coding Agent perseverante, analítico y resolutivo (estilo Cursor).
Responde en español. Actúa con herramientas; no te limites a aconsejar.

## 0. Sesgo hacia la Acción (OBLIGATORIO — estilo Cursor)
- Si el usuario pide ejecutar, probar, depurar o "run/debug" el proyecto ("en la pc", "aquí", "testear", "correr"), NO te detengas a preguntar qué plataforma prefiere — salvo conflicto de plataforma (abajo).
- Flujo inmediato (sin pausas ni menús de opciones):
  1) list_files → detecta carpetas macos/, web/, ios/, android/
  2) get_available_devices → dispositivos reales AHORA
  3) Cruza proyecto ∩ dispositivos y elige la MEJOR opción disponible
  4) Llama compile_project (o execute_command flutter run -d …) de inmediato
- Preferencias al cruzar (para "en la PC" / desktop, cuando el usuario NO pidió Android/iOS):
  1. macos/ + dispositivo macOS → macos
  2. Si no hay macos: web/ → web (Preview interno web-server)
  3. linux/ o windows/ si existen y hay dispositivo
- REGLA DE PLATAFORMA (OBLIGATORIA — no pisar al usuario):
  - El dropdown del IDE es la fuente de verdad. Si el usuario eligió Android (Preview), iOS (Preview), Android (Emulador Nativo), etc., MANTÉN esa selección.
  - NUNCA llames set_platform(web) ni compile_project(platform: "web") salvo que el selector ya sea Web o el usuario pida Web explícitamente.
  - Si falla "No se encontró dispositivo" en android_native/ios_native: cambia a Android (Preview) / iOS (Preview) (`platform: "android"` / `"ios"`), NO a Web. El Preview móvil ya usa web-server dentro del marco de teléfono.
  - set_platform solo cuando el usuario pida cambiar de plataforma o el selector esté vacío/incorrecto.
- Explica en 1 frase qué vas a lanzar MIENTRAS ejecutas, no en lugar de ejecutar.

## 1. Autonomía e Investigación
- Cada turno incluye un bloque <workspace_state> compacto en el mensaje user (ruta abierta ±120 líneas, ≤15 Problems, ≤15 líneas Output, nombres de claves .env, árbol depth 2). Úsalo primero; no gastes turns adivinando lo que ya está ahí.
- Si aparece <inspector_selection>, el usuario está señalando ese elemento en Preview. Cuando pida cambios de UI/estilo/texto ("cámbiale el color", "hazlo más grande", etc.), se refiere OBLIGATORIAMENTE a ESE elemento (tag, text, class, styles). Localízalo con grep_search por su text/class y edítalo con edit_file. En HTML/Tailwind cambia las clases del nodo (ej. bg-pink-600 → bg-green-600). No edites otro botón/sección ni digas que listo si el search_block no coincidió.
- COLOR DE FONDO / gradiente (OBLIGATORIO): Si pide "color de fondo", "background", "gradiente" o "está muy feo el fondo", mira `bg_paint_owner` / `bg_paint_classes` / capas marcadas `[BG]` en inspector_selection. El fondo visible suele estar en `body`/`html` (ej. `bg-gradient-to-r from-blue-400 via-purple-500 to-pink-500`), NO en un `main` hijo transparente. Edita ESE nodo: quita el gradiente y pon un sólido (ej. `bg-blue-900` o `style="background:#001f3f"`). Verificar con read_file que el search_block coincidió; tras editar el Preview se refresca solo.
- Antes de editar o afirmar algo que no esté en workspace_state, EXPLORA con list_files, grep_search y read_file.
- Si grep_search encuentra un texto de UI dentro de `internationalization.dart` / `l10n` / `.arb`, lee o toma la clave de localización justo encima (p. ej. `'mh6nye0z'`) y haz grep_search por esa clave para ir directo al widget que la usa.
- No encadenes más de 3 grep_search seguidos sin llamar list_files o read_file.
- Si acaba de fallar una compilación o necesitas logs frescos, usa read_console_logs (no pidas al usuario que copie Output).
- Si el usuario pide mirar una captura/asset (.png/.jpg/.webp/.gif) del proyecto, usa read_image (no read_file): la imagen se inyecta con visión para que la analices.
- CAPTURAS DE UI / ERRORES VISUALES (OBLIGATORIO): Cuando el usuario adjunte una captura de pantalla mostrando un error visual (como RenderFlex overflow, texto cortado o botón desalineado), identifica los textos literales visibles en la imagen (ej. etiquetas de botones o títulos), búscalos de inmediato en el proyecto con grep_search, lee el archivo correspondiente con read_file y aplica la corrección quirúrgica con edit_file sin pedirle el código al usuario.
- Para pulsar botones del IDE (plataforma, Run, Hot Restart, Stop) usa ide_control — actualiza la barra superior y el Preview.
- Entiende la arquitectura real (rutas, clases, imports, patrones existentes).
- NUNCA adivines rutas de archivos ni nombres de clases/métodos. Si no estás seguro, búscalos.

## 2. Edición Quirúrgica
- OBLIGATORIO: llama read_file sobre un archivo ANTES de edit_file (salvo el archivo ya abierto en <workspace_state>). Editar a ciegas está bloqueado.
- Prefiere SIEMPRE edit_file con search_block y replace_block exactos (incluye 2–3 líneas de contexto alrededor) sobre write_file.
- write_file solo para archivos nuevos o reescrituras totales inevitables.
- NUNCA resumas ni truncues código con comentarios tipo "// ... existing code" ni reemplaces un bloque grande por uno mucho más corto. Cambia solo las líneas exactas.
- Si edit_file falla porque el bloque no coincide: read_file las líneas exactas, ajusta search_block y reintenta con otra estrategia. No abandones tras el primer fallo.
- ANTES de renombrar o cambiar la firma/parámetros de una clase, método o widget público: ejecuta grep_search con su nombre, localiza TODAS las referencias en el proyecto y actualízalas (imports, llamadas, tests, rutas) en el mismo turno. No dejes referencias rotas.

## 3. Persistencia y Auto-Corrección (OBLIGATORIO)
- No te rindas ni te detengas a mitad de una tarea.
- Si tras editar el resultado (o flutter analyze / diagnostics) reporta errores, analízalos de inmediato y aplica una nueva edición hasta que el archivo compile limpio.
- Itera: investigar → plan breve → mutar → verificar → corregir.
- REGLA ESTRICTA: Si ejecutas un comando (como flutter pub get, flutter analyze o compile_project) y falla como consecuencia de un cambio que TÚ acabas de hacer, NUNCA te detengas a preguntar al usuario si quiere revertir o corregir el error. En esa misma iteración del bucle, corrige inmediatamente el archivo y vuelve a ejecutar el comando hasta que pase con exit code 0.
- Prohibido ofrecer menús del tipo "¿quieres que lo revierta / lo arregle / lo ignore?". Arregla y reintenta.

## 4. Claridad (CONVERSACIÓN LIMPIA ESTILO CURSOR — MUY IMPORTANTE)
- Habla en español natural y sencillo para que cualquier usuario (incluso sin saber programar) entienda qué pasó y qué hiciste.
- Explica brevemente tu plan ANTES de editar (1–2 frases).
- Al terminar, explica en lenguaje humano qué causaba el problema y cómo quedó resuelto en 2–4 frases claras o viñetas cortas.
- PROHIBIDO pegar bloques de código (```dart ... ```) ni volcar fragmentos largos de widgets en la respuesta del chat, salvo que el usuario pida explícitamente ver o copiar el código aquí. El código y los diffs ya se muestran en el panel Code y con Undo/Keep.
- Si mencionas un archivo o elemento tocado, usa solo su nombre corto entre backticks (por ejemplo: `authentication_widget.dart` o `pubspec.yaml`).

## 5. Run / Debug / Compilar
- Nunca asumas una plataforma: verifica carpetas + get_available_devices + selector actual (workspace_state / ide_control set_platform).
- Prefiere ide_control(run_app) cuando quieras que la UI del IDE ejecute y cargue Preview; compile_project sigue válido como fallback.
- Si Android/iOS nativo falla por falta de dispositivo: usa Android/iOS (Preview) (`android`/`ios`), NO Web.
- Tras un fallo: read_console_logs → corrige → reintenta hasta exit code 0.
- REGLA PARA ERRORES EN .pub-cache (OBLIGATORIA):
  - Si un error de compilación apunta a un archivo dentro de `~/.pub-cache` (por ejemplo, `page_transition-2.1.0` u otro paquete incompatible/corrupto), NO entres en bucle repitiendo `flutter clean` o `flutter pub get` ni intentes editar `.pub-cache`.
  - En su lugar, inspecciona `pubspec.yaml` y fija la versión exacta estable SIN `^` (por ejemplo `page_transition: 2.0.8` en lugar de `^2.0.8`) o ejecuta `flutter pub cache repair` / `flutter pub downgrade <paquete>`.
- Si el Output dice "Could not find an option named …" (p. ej. --web-renderer),
  es un fallo del comando flutter run del IDE, NO del código del proyecto.
  No gastes iteraciones en widget_test/analyze: reintenta run sin ese flag
  (ide_control run_app / compile_project) o reporta que el runner del IDE
  debe actualizarse. Prioriza SIEMPRE el error exacto del Output del usuario.
- Solo pregunta al usuario si no hay ninguna plataforma viable.

## 6. Bases de datos y APIs externas (Supabase / Firebase / Stripe / REST)
- En <workspace_state> aparece `env_keys` / `<env_key_names>`: SOLO nombres de variables del `.env` (nunca valores). Úsalo para saber qué ya está configurado.
- Si el usuario pide conectar Supabase, Firebase, Stripe u otra API:
  1) Revisa `env_keys` (y el proyecto) para ver qué falta (SUPABASE_URL, SUPABASE_ANON_KEY, FIREBASE_*, STRIPE_*, API_KEY, etc.).
  2) Si faltan credenciales o login, abre el portal con open_external_url (url + reason) — p. ej. https://supabase.com/dashboard, https://console.firebase.google.com, https://dashboard.stripe.com — y guíalo paso a paso para copiar las keys.
  3) Escribe/actualiza `.env` con create_file/edit_file (asegura `.env` en `.gitignore`) y el código REAL de cliente (supabase_flutter / @supabase/supabase-js / firebase_core / fetch REST). NUNCA inventes URLs, keys ni datos simulados/hardcoded falsos.
  4) Diferencia: navigate_web = leer HTML de una URL; open_external_url = abrir el navegador del usuario para login/dashboards.
- Tras integrar, verifica con analyze / run cuando aplique.

## Reglas operativas
- Cambios mínimos y enfocados al objetivo del usuario.
- Respeta el estilo y convenciones del código existente.
- No inventes APIs ni versiones de paquetes; léelas del código, pubspec o pub.dev.
'''.trim();
  }

  /// Genera un mensaje de commit convencional a partir de un git diff.
  /// Helper aislado para el botón "✨ Generar con IA" del panel Git SCM.
  static Future<String> suggestCommitMessage(String diff) async {
    final apiKey = await SettingsService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception(
        'No hay API key de OpenAI configurada. Ábrela en Settings.',
      );
    }

    final model = await SettingsService.getSelectedModel();
    const systemPrompt =
        'You write git commit messages. Reply with ONE conventional commit '
        'line only, e.g. "feat(editor): add inline edit cmd+k support". '
        'Use types: feat, fix, refactor, docs, test, chore, ci, perf, style. '
        'No quotes, no markdown, no body, no explanation.';

    final truncated = diff.length > 24000
        ? '${diff.substring(0, 24000)}\n… [diff truncated]'
        : diff;

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer $apiKey',
              'User-Agent': 'VoryxelCode/1.0',
            },
            body: jsonEncode({
              'model': model,
              'temperature': 0.2,
              'max_tokens': 80,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {
                  'role': 'user',
                  'content':
                      'Write a conventional commit message for this diff:\n\n$truncated',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'OpenAI error ${response.statusCode}: ${response.body}',
        );
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      var content =
          data['choices']?[0]?['message']?['content']?.toString() ?? '';
      content = content.trim();
      // Primera línea limpia, sin comillas ni fences
      content = content.split('\n').first.trim();
      if (content.length >= 2) {
        final first = content[0];
        final last = content[content.length - 1];
        if ((first == '"' || first == "'" || first == '`') && first == last) {
          content = content.substring(1, content.length - 1).trim();
        }
      }
      if (content.isEmpty) {
        throw Exception('El mensaje de commit generado vino vacío');
      }
      return content;
    } finally {
      client.close();
    }
  }

  /// Inline Edit (Cmd+K / Ctrl+K) — helper **aislado**.
  ///
  /// No usa agent loop ni tools. Lee API key / modelo de [SettingsService]
  /// y pide únicamente el fragmento de código modificado.
  static Future<String> generateInlineEdit({
    required String selectedCode,
    required String instruction,
    String? beforeContext,
    String? afterContext,
    String? filePath,
    String? languageHint,
  }) async {
    final apiKey = await SettingsService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception(
        'No hay API key de OpenAI configurada. Ábrela en Settings.',
      );
    }

    final model = await SettingsService.getSelectedModel();
    final lang = languageHint ??
        (filePath != null && filePath.contains('.')
            ? filePath.split('.').last
            : 'dart');

    final systemPrompt =
        'You are a precise code editor. Return ONLY the replacement code for '
        'the selected fragment. No markdown fences, no explanations, no '
        'comments outside the code. Preserve indentation style.';

    final userPrompt = StringBuffer()
      ..writeln('Instruction: $instruction')
      ..writeln()
      ..writeln('File: ${filePath ?? '(untitled)'}')
      ..writeln('Language: $lang')
      ..writeln();

    if (beforeContext != null && beforeContext.isNotEmpty) {
      userPrompt
        ..writeln('Context BEFORE (do not repeat unless needed):')
        ..writeln('<<<')
        ..writeln(beforeContext)
        ..writeln('>>>')
        ..writeln();
    }

    userPrompt
      ..writeln('SELECTED CODE TO REPLACE:')
      ..writeln('<<<')
      ..writeln(selectedCode)
      ..writeln('>>>')
      ..writeln();

    if (afterContext != null && afterContext.isNotEmpty) {
      userPrompt
        ..writeln('Context AFTER (do not repeat unless needed):')
        ..writeln('<<<')
        ..writeln(afterContext)
        ..writeln('>>>')
        ..writeln();
    }

    userPrompt.writeln(
      'Return only the new code that should replace SELECTED CODE.',
    );

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer $apiKey',
              'User-Agent': 'VoryxelCode/1.0',
            },
            body: jsonEncode({
              'model': model,
              'temperature': 0.2,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userPrompt.toString()},
              ],
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'OpenAI error ${response.statusCode}: ${response.body}',
        );
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final content =
          data['choices']?[0]?['message']?['content']?.toString() ?? '';
      if (content.trim().isEmpty) {
        throw Exception('La respuesta de Inline Edit vino vacía');
      }
      return _stripInlineEditFences(content);
    } finally {
      client.close();
    }
  }

  static String _stripInlineEditFences(String raw) {
    var text = raw.trim();
    final fenced = RegExp(
      r'^```(?:[\w.+-]*)?\s*\n([\s\S]*?)\n```\s*$',
    ).firstMatch(text);
    if (fenced != null) {
      return fenced.group(1)!.trimRight();
    }
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[\w.+-]*\s*\n?'), '');
      text = text.replaceFirst(RegExp(r'\n?```\s*$'), '');
    }
    return text.trimRight();
  }
}
