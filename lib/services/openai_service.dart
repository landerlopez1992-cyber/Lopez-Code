import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'web_navigation_service.dart';
import 'run_debug_service.dart';
import 'project_protection_service.dart';
import 'backup_service.dart';

class OpenAIService {
  final String apiKey;
  final String baseUrl = 'https://api.openai.com/v1';
  String model; // Modelo configurable
  
  // Cliente HTTP reutilizable con configuración optimizada
  late final http.Client _httpClient;
  bool _isCancelled = false;

  OpenAIService({required this.apiKey, this.model = 'gpt-4o'}) {
    _httpClient = http.Client();
  }
  
  /// Cancela la petición actual
  void cancelRequest() {
    print('🛑 OpenAIService: Cancelando petición...');
    _isCancelled = true;
    try {
      _httpClient.close();
    } catch (e) {
      print('⚠️ Error al cerrar cliente HTTP: $e');
    }
    // ✅ FIX: Reiniciar cliente solo si está cerrado
    try {
      _httpClient = http.Client();
    } catch (e) {
      print('⚠️ Error al reiniciar cliente HTTP: $e');
      // Si falla, intentar crear uno nuevo
      _httpClient = http.Client();
    }
    print('✅ OpenAIService: Petición cancelada');
  }

  // Método para cambiar el modelo
  void setModel(String newModel) {
    model = newModel;
    print('🔄 OpenAI modelo actualizado a: $newModel');
  }
  
  // Cerrar el cliente cuando ya no se necesite
  void dispose() {
    _httpClient.close();
  }

  // Callback para notificar sobre operaciones de archivos
  Function(String operation, String filePath)? onFileOperation;
  
  // Callback para acciones pendientes que requieren confirmación
  Function(List<Map<String, dynamic>> pendingActions)? onPendingActions;

  Future<String> sendMessage({
    required String message,
    List<String>? imagePaths,
    List<Map<String, dynamic>>? conversationHistory,
    String? fileContent,
    String? systemPrompt,
    String? projectPath, // Para ejecutar funciones de archivos
    Function(String operation, String filePath)? onFileOperation, // Callback para operaciones de archivos
    Function(List<Map<String, dynamic>> pendingActions)? onPendingActions, // Callback para acciones pendientes
    bool allowTools = true, // Controla si se permiten herramientas
  }) async {
    this.onFileOperation = onFileOperation;
    this.onPendingActions = onPendingActions;
    _isCancelled = false; // Reset cancel flag
    try {
      final List<Map<String, dynamic>> messages = [];

      // Agregar system prompt si existe (reglas y comportamiento)
      // Si hay imágenes, mejorar el prompt para análisis de imágenes
      String finalSystemPrompt = systemPrompt ?? '';
      if (imagePaths != null && imagePaths.isNotEmpty) {
        finalSystemPrompt += '''
        
IMPORTANTE: El usuario ha enviado ${imagePaths.length} imagen(es). 
DEBES analizar cada imagen en detalle y describir:
- Lo que ves en la imagen
- Elementos, objetos, texto, personas, lugares
- Colores, formas, composición
- Cualquier texto visible
- Contexto y significado
- Si es código, transcribe el código completo
- Si es un diseño, describe el diseño detalladamente

Responde en español y sé detallado en tu análisis.''';
      }
      
      if (finalSystemPrompt.isNotEmpty) {
        messages.add({
          'role': 'system',
          'content': finalSystemPrompt,
        });
      }

      // Agregar historial de conversación si existe
      if (conversationHistory != null) {
        messages.addAll(conversationHistory);
      }

      // Construir el contenido del mensaje
      List<Map<String, dynamic>> content = [
        {
          'type': 'text',
          'text': message,
        }
      ];

      // Agregar imágenes si existen (con optimización)
      if (imagePaths != null && imagePaths.isNotEmpty) {
        // Verificar que el modelo soporte visión
        if (!_supportsVision(model)) {
          print('⚠️ El modelo $model no soporta análisis de imágenes. Usando gpt-4o automáticamente.');
          model = 'gpt-4o'; // Cambiar a modelo con visión
        }
        
        print('🖼️ Procesando ${imagePaths.length} imagen(es)...');
        
        for (var imagePath in imagePaths) {
          final file = File(imagePath);
          if (await file.exists()) {
            // Optimizar imagen antes de enviar
            final optimizedBytes = await _optimizeImage(file);
            final base64Image = base64Encode(optimizedBytes);
            
            // Calcular tokens aproximados de la imagen
            final imageTokens = _estimateImageTokens(optimizedBytes.length);
            print('📊 Imagen optimizada: ${(optimizedBytes.length / 1024).toStringAsFixed(1)}KB, ~$imageTokens tokens');
            
            content.add({
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$base64Image',
                'detail': 'high', // Alta resolución para mejor análisis
              },
            });
          }
        }
      }

      // Agregar contenido de archivo si existe
      if (fileContent != null) {
        content[0]['text'] = '$message\n\n--- Código del archivo ---\n$fileContent';
      }

      messages.add({
        'role': 'user',
        'content': content,
      });

      // Headers mejorados siguiendo las mejores prácticas de OpenAI
      final headers = {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $apiKey',
        'User-Agent': 'LopezCode/1.0',
        'Accept': 'application/json',
      };

      // Definir funciones disponibles para Function Calling
      final tools = [
        {
          'type': 'function',
          'function': {
            'name': 'edit_file',
            'description': 'Edita un archivo existente en el proyecto. Reemplaza todo el contenido del archivo con el nuevo código proporcionado.',
            'parameters': {
              'type': 'object',
              'properties': {
                'file_path': {
                  'type': 'string',
                  'description': 'Ruta completa del archivo a editar (ej: lib/screens/welcome_screen.dart)',
                },
                'content': {
                  'type': 'string',
                  'description': 'Contenido completo del archivo después de la edición',
                },
              },
              'required': ['file_path', 'content'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'create_file',
            'description': 'Crea un nuevo archivo en el proyecto con el código proporcionado.',
            'parameters': {
              'type': 'object',
              'properties': {
                'file_path': {
                  'type': 'string',
                  'description': 'Ruta completa del archivo a crear (ej: lib/widgets/new_widget.dart)',
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
            'description': 'Lee el contenido de un archivo existente en el proyecto. SIEMPRE usa esto ANTES de edit_file() para entender el contexto.',
            'parameters': {
              'type': 'object',
              'properties': {
                'file_path': {
                  'type': 'string',
                  'description': 'Ruta completa del archivo a leer (ej: lib/main.dart)',
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
            'description': 'Compila el proyecto Flutter y detecta errores de compilación. Útil para verificar que el código compila correctamente.',
            'parameters': {
              'type': 'object',
              'properties': {
                'platform': {
                  'type': 'string',
                  'description': 'Plataforma para compilar: macos, ios, android, web',
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
            'description': 'Ejecuta un comando del sistema (Flutter, Git, etc.). Útil para instalar dependencias, ejecutar scripts, etc.',
            'parameters': {
              'type': 'object',
              'properties': {
                'command': {
                  'type': 'string',
                  'description': 'Comando a ejecutar (ej: flutter pub get, git status)',
                },
                'working_directory': {
                  'type': 'string',
                  'description': 'Directorio donde ejecutar el comando (opcional, por defecto proyecto actual)',
                },
              },
              'required': ['command'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'download_file',
            'description': 'Descarga un archivo desde una URL y lo guarda en el proyecto.',
            'parameters': {
              'type': 'object',
              'properties': {
                'url': {
                  'type': 'string',
                  'description': 'URL del archivo a descargar',
                },
                'target_path': {
                  'type': 'string',
                  'description': 'Ruta donde guardar el archivo (ej: lib/assets/file.zip). Si no se especifica, se guarda en la raíz del proyecto.',
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
            'description': 'Navega a una URL y obtiene su contenido HTML para analizarlo. Útil para buscar información, documentación, etc.',
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
      ];

      final Map<String, dynamic> bodyMap = {
        'model': model, // Usar el modelo configurado
        'messages': messages,
        'temperature': 0.3, // Reducido de 0.7 a 0.3 para mayor precisión (como Cursor agent)
        'max_tokens': 8000, // Aumentado para respuestas más completas
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
      final response = await _httpClient
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
        
        // Verificar si la IA quiere llamar a una función
        if (message['tool_calls'] != null && message['tool_calls'].isNotEmpty) {
          print('🔧 La IA quiere ejecutar funciones: ${message['tool_calls'].length}');
          
          // NUEVO: En lugar de ejecutar directamente, crear acciones pendientes
          // que requieren confirmación del usuario
          if (onPendingActions != null) {
            final pendingActionsList = <Map<String, dynamic>>[];
            for (var toolCall in message['tool_calls']) {
              final functionName = toolCall['function']['name'];
              final functionArgs = jsonDecode(toolCall['function']['arguments']);
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
                final protection = ProjectProtectionService.canModifyFile(filePath, functionName);
                
                if (!protection.allowed) {
                  // Si la operación no está permitida, agregar advertencia
                  protectionWarning = '🚫 OPERACIÓN BLOQUEADA: ${protection.reason}';
                  print('🚫 Operación bloqueada por protección: $functionName en $filePath');
                } else if (protection.requiresExtraConfirmation) {
                  // Si requiere confirmación extra, agregar advertencias
                  protectionWarning = ProjectProtectionService.getCriticalFileWarning(filePath);
                  securityRecommendations = ProjectProtectionService.getSecurityRecommendations(functionName, filePath);
                  print('⚠️ Archivo crítico detectado: $filePath (requiere confirmación extra)');
                }
              }
              
              // Crear acción pendiente con toda la información
              final pendingAction = {
                'id': DateTime.now().millisecondsSinceEpoch.toString() + '_${pendingActionsList.length}',
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
            print('🔔 NOTIFICANDO UI sobre ${pendingActionsList.length} acciones pendientes');
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
            
            print('🔧 Ejecutando función: $functionName con args: $functionArgs');
            
            String? result;
            try {
              final filePath = functionArgs['file_path'] as String? ?? '';
              
              // Para edit_file, SIEMPRE leer el archivo primero (OBLIGATORIO)
              if (functionName == 'edit_file') {
                // PROTECCIÓN CRÍTICA: SIEMPRE leer el archivo primero para entender el contexto
                String currentContent = '';
                String? readWarning;
                try {
                  currentContent = await _executeReadFile(filePath, projectPath);
                  if (currentContent.isEmpty) {
                    readWarning = 'Advertencia: El archivo está vacío. Asegúrate de proporcionar el contenido completo.';
                  } else {
                    // El archivo fue leído exitosamente - continuar con la edición
                    print('✅ Archivo leído antes de editar: $filePath (${currentContent.length} caracteres)');
                  }
                } catch (e) {
                  result = 'Error: NO SE PUEDE EDITAR - No se pudo leer el archivo primero. Verifica que existe: $e\n\nIMPORTANTE: Siempre lee el archivo con read_file() antes de editarlo.';
                }
                
                // Solo proceder si se leyó exitosamente o si el archivo no existe (es nuevo)
                if (result == null || result.isEmpty) {
                  // Notificar sobre la operación
                  onFileOperation?.call('editando', filePath);
                  final editResult = await _executeEditFile(filePath, functionArgs['content'], projectPath);
                  if (readWarning != null && readWarning.isNotEmpty) {
                    result = '$readWarning\n\n$editResult'; // Combinar advertencia con resultado
                  } else {
                    result = editResult; // Usar el resultado de la edición
                  }
                }
              } else if (functionName == 'create_file') {
                onFileOperation?.call('creando', filePath);
                result = await _executeCreateFile(filePath, functionArgs['content'], projectPath);
              } else if (functionName == 'read_file') {
                onFileOperation?.call('leyendo', filePath);
                result = await _executeReadFile(filePath, projectPath);
              } else if (functionName == 'compile_project') {
                onFileOperation?.call('compilando', 'proyecto');
                result = await _executeCompileProject(
                  functionArgs['platform'] as String?,
                  functionArgs['mode'] as String?,
                  projectPath,
                );
              } else if (functionName == 'execute_command') {
                onFileOperation?.call('ejecutando', functionArgs['command'] as String);
                result = await _executeCommand(
                  functionArgs['command'] as String,
                  functionArgs['working_directory'] as String?,
                  projectPath,
                );
              } else if (functionName == 'download_file') {
                onFileOperation?.call('descargando', functionArgs['url'] as String);
                result = await _executeDownloadFile(
                  functionArgs['url'] as String,
                  functionArgs['target_path'] as String?,
                  projectPath,
                );
              } else if (functionName == 'navigate_web') {
                onFileOperation?.call('navegando', functionArgs['url'] as String);
                result = await _executeNavigateWeb(functionArgs['url'] as String);
              } else {
                result = 'Función desconocida: $functionName';
              }
            } catch (e) {
              result = 'Error ejecutando función: $e';
            }
            
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
          final secondResponse = await _httpClient.post(
            Uri.parse('$baseUrl/chat/completions'),
            headers: headers,
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'temperature': 0.7,
              'max_tokens': 4000,
            }),
          ).timeout(const Duration(seconds: 90));
          
          if (secondResponse.statusCode == 200) {
            final secondData = jsonDecode(utf8.decode(secondResponse.bodyBytes));
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
        final errorBody = utf8.decode(response.bodyBytes); // Usar UTF-8 decoding consistentemente
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
                errorMessage = 'context_length_exceeded: El mensaje es demasiado largo. Por favor, reduce el tamaño del proyecto o del mensaje.';
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
      throw Exception('connection: No se pudo conectar a OpenAI. Verifica tu conexión a internet y el firewall.');
    } on HttpException catch (e) {
      print('🌐 HttpException: ${e.message}');
      throw Exception('http: Error de HTTP: ${e.message}');
    } catch (e) {
      print('❌ Error general: $e');
      throw Exception('Error al comunicarse con OpenAI: $e');
    }
  }

  /// Ejecuta la función edit_file (PROTEGIDO - solo archivos del proyecto)
  Future<String> _executeEditFile(String filePath, String content, String? projectPath) async {
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
      await file.writeAsString(content);
      print('✅ Archivo editado: $fullPath');
      return 'Archivo editado exitosamente: $filePath';
    } catch (e) {
      print('❌ Error editando archivo: $e');
      return 'Error al editar archivo: $e';
    }
  }

  /// Ejecuta la función create_file (PROTEGIDO - solo archivos del proyecto)
  Future<String> _executeCreateFile(String filePath, String content, String? projectPath) async {
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
      }
      
      await file.writeAsString(content);
      print('✅ Archivo creado: $fullPath');
      return 'Archivo creado exitosamente: $filePath';
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

  /// Ejecuta la función compile_project
  Future<String> _executeCompileProject(String? platform, String? mode, String? projectPath) async {
    try {
      if (projectPath == null || projectPath.isEmpty) {
        return 'Error: No hay proyecto cargado';
      }

      final output = StringBuffer();
      final errorOutput = StringBuffer();

      try {
        await RunDebugService.runFlutterProject(
          mode: mode ?? 'debug',
          platform: platform ?? 'macos',
          onOutput: (data) => output.write(data),
          onError: (error) => errorOutput.write(error),
        );

        // Esperar un momento para que el proceso inicie
        await Future.delayed(const Duration(seconds: 2));

        final hasErrors = errorOutput.toString().isNotEmpty && 
                         errorOutput.toString().toLowerCase().contains('error');

        if (hasErrors) {
          return '❌ Errores de compilación detectados:\n${errorOutput.toString()}\n\nOutput:\n${output.toString()}';
        } else {
          return '✅ Compilación iniciada exitosamente (modo: ${mode ?? 'debug'}, plataforma: ${platform ?? 'macos'})\n\nOutput:\n${output.toString()}';
        }
      } catch (e) {
        return 'Error al compilar: $e\n\nOutput:\n${output.toString()}\n\nErrors:\n${errorOutput.toString()}';
      }
    } catch (e) {
      print('❌ Error en compile_project: $e');
      return 'Error al compilar proyecto: $e';
    }
  }

  /// Ejecuta la función execute_command
  Future<String> _executeCommand(String command, String? workingDirectory, String? projectPath) async {
    try {
      final workingDir = workingDirectory ?? projectPath ?? Directory.current.path;
      
      print('🔧 Ejecutando comando: $command en $workingDir');

      final parts = command.split(' ');
      final executable = parts[0];
      final args = parts.length > 1 ? parts.sublist(1) : <String>[];

      final result = await Process.run(
        executable,
        args,
        workingDirectory: workingDir,
      );

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

      if (result.exitCode == 0) {
        return '✅ Comando ejecutado exitosamente:\n${output.toString()}';
      } else {
        return '❌ Comando falló (exit code: ${result.exitCode}):\n${output.toString()}';
      }
    } catch (e) {
      print('❌ Error ejecutando comando: $e');
      return 'Error al ejecutar comando: $e';
    }
  }

  /// Ejecuta la función download_file
  Future<String> _executeDownloadFile(String url, String? targetPath, String? projectPath) async {
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
        description = 'Editar el archivo "${filePath ?? 'archivo'}"';
        reasoning = 'Modificar código existente para implementar cambios solicitados';
        
        // Generar diff si es posible
        if (filePath != null && projectPath != null) {
          try {
            oldContent = await _executeReadFile(filePath, projectPath);
            newContent = arguments['content'] as String?;
            
            if (oldContent.isNotEmpty && newContent != null) {
              diff = _generateDiff(oldContent, newContent, filePath);
            }
          } catch (e) {
            print('⚠️ No se pudo generar diff: $e');
          }
        }
        break;
        
      case 'create_file':
        description = 'Crear nuevo archivo "${filePath ?? 'nuevo archivo'}"';
        reasoning = 'Crear archivo nuevo con código inicial';
        newContent = arguments['content'] as String?;
        break;
        
      case 'read_file':
        description = 'Leer el contenido del archivo "${filePath ?? 'archivo'}"';
        reasoning = 'Analizar código existente para entender el contexto';
        break;
        
      case 'compile_project':
        final platform = arguments['platform'] as String? ?? 'macos';
        final mode = arguments['mode'] as String? ?? 'debug';
        description = 'Compilar proyecto para $platform en modo $mode';
        reasoning = 'Verificar que el código compile correctamente y detectar errores';
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
    final maxLines = oldLines.length > newLines.length ? oldLines.length : newLines.length;
    
    for (int i = 0; i < maxLines; i++) {
      final oldLine = i < oldLines.length ? oldLines[i] : null;
      final newLine = i < newLines.length ? newLines[i] : null;
      
      if (oldLine == newLine && oldLine != null) {
        // Línea sin cambios (mostrar solo algunas para contexto)
        if (i < 3 || i > maxLines - 3 || 
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
  String _generateActionDescription(String functionName, Map<String, dynamic> arguments) {
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
      default:
        return 'Ejecutar acción: $functionName';
    }
  }

  /// Verifica el saldo y estado de la cuenta de OpenAI
  Future<Map<String, dynamic>> checkAccountStatus() async {
    try {
      // Intentar hacer una llamada simple a la API para verificar el estado
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/models'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'User-Agent': 'LopezCode/1.0',
        },
      ).timeout(const Duration(seconds: 10));

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
      String prompt = '''
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
      'gpt-4o',
      'gpt-4o-mini',
      'gpt-4-turbo',
      'gpt-4-vision-preview',
      'gpt-4',
    ];
    
    return visionModels.any((m) => modelName.toLowerCase().contains(m.toLowerCase()));
  }
  
  /// Optimiza una imagen antes de enviarla a OpenAI
  /// Por ahora solo verifica tamaño y advierte si es muy grande
  /// TODO: Implementar redimensionamiento con paquete de imágenes
  Future<Uint8List> _optimizeImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final sizeKB = bytes.length / 1024;
      
      // Advertir si la imagen es muy grande (>5MB)
      if (sizeKB > 5120) {
        print('⚠️ Imagen muy grande: ${sizeKB.toStringAsFixed(1)}KB');
        print('💡 Considera comprimir la imagen antes de enviarla para ahorrar tokens');
      } else {
        print('✅ Tamaño de imagen: ${sizeKB.toStringAsFixed(1)}KB');
      }
      
      // Por ahora devolver imagen original
      // TODO: Implementar redimensionamiento cuando se agregue paquete de imágenes
      return bytes;
    } catch (e) {
      print('❌ Error procesando imagen: $e');
      return await imageFile.readAsBytes();
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
}
