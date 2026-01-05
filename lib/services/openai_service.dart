import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;

class OpenAIService {
  final String apiKey;
  final String baseUrl = 'https://api.openai.com/v1';
  String model; // Modelo configurable
  
  // Cliente HTTP reutilizable con configuración optimizada
  late final http.Client _httpClient;

  OpenAIService({required this.apiKey, this.model = 'gpt-4o'}) {
    _httpClient = http.Client();
  }

  // Método para cambiar el modelo
  void setModel(String newModel) {
    model = newModel;
  }
  
  // Cerrar el cliente cuando ya no se necesite
  void dispose() {
    _httpClient.close();
  }

  // Callback para notificar sobre operaciones de archivos
  Function(String operation, String filePath)? onFileOperation;

  Future<String> sendMessage({
    required String message,
    List<String>? imagePaths,
    List<Map<String, dynamic>>? conversationHistory,
    String? fileContent,
    String? systemPrompt,
    String? projectPath, // Para ejecutar funciones de archivos
    Function(String operation, String filePath)? onFileOperation, // Callback para operaciones de archivos
  }) async {
    this.onFileOperation = onFileOperation;
    try {
      final List<Map<String, dynamic>> messages = [];

      // Agregar system prompt si existe (reglas y comportamiento)
      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        messages.add({
          'role': 'system',
          'content': systemPrompt,
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

      // Agregar imágenes si existen
      if (imagePaths != null && imagePaths.isNotEmpty) {
        for (var imagePath in imagePaths) {
          final file = File(imagePath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final base64Image = base64Encode(bytes);
            content.add({
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$base64Image',
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
            'description': 'Lee el contenido de un archivo existente en el proyecto.',
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
      ];

      final body = jsonEncode({
        'model': model, // Usar el modelo configurado
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 4000,
        'stream': false, // Asegurar que no es streaming
        'tools': tools, // Function Calling habilitado (ahora protegido)
        'tool_choice': 'auto',
      });

      print('🔄 Enviando solicitud a OpenAI...');
      print('📊 Modelo: $model');
      print('💬 Mensajes: ${messages.length}');

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
              
              // Notificar sobre la operación
              if (functionName == 'edit_file') {
                onFileOperation?.call('editando', filePath);
                result = await _executeEditFile(filePath, functionArgs['content'], projectPath);
              } else if (functionName == 'create_file') {
                onFileOperation?.call('creando', filePath);
                result = await _executeCreateFile(filePath, functionArgs['content'], projectPath);
              } else if (functionName == 'read_file') {
                onFileOperation?.call('leyendo', filePath);
                result = await _executeReadFile(filePath, projectPath);
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
              'content': result ?? 'Completado',
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
      
      // PROTECCIÓN: No editar archivos críticos del sistema
      final criticalFiles = [
        'pubspec.yaml',
        'analysis_options.yaml',
        '.gitignore',
        'README.md',
      ];
      
      final fileName = fullPath.split('/').last;
      if (criticalFiles.contains(fileName) && !normalizedFullPath.contains('/lib/')) {
        return 'Error: No se pueden editar archivos de configuración críticos';
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
}
