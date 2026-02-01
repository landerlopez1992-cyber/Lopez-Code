import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio para persistir reglas, estilos de código y memorias del proyecto
/// Similar a Cursor - recuerda preferencias y patrones del proyecto
class RuleService {
  static const String _rulesKey = 'ai_rules';
  static const String _codeStyleKey = 'code_style_preferences';
  static const String _projectMemoriesKey = 'project_memories';
  static const String _architectureKey = 'project_architecture';

  // ========== REGLAS PERSONALIZADAS ==========
  
  /// Guardar reglas personalizadas del usuario
  static Future<void> saveRules(String rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rulesKey, rules);
    print('✅ Reglas guardadas');
  }

  /// Obtener reglas personalizadas
  static Future<String?> getRules() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rulesKey);
  }

  /// Verificar si hay reglas guardadas
  static Future<bool> hasRules() async {
    final rules = await getRules();
    return rules != null && rules.isNotEmpty;
  }
  
  // ========== ESTILO DE CÓDIGO ==========
  
  /// Guardar preferencias de estilo de código
  /// Ejemplo: { "indentation": "2 spaces", "naming": "camelCase", "comments": "always" }
  static Future<void> saveCodeStyle(Map<String, dynamic> style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_codeStyleKey, jsonEncode(style));
    print('✅ Estilo de código guardado');
  }
  
  /// Obtener preferencias de estilo de código
  static Future<Map<String, dynamic>> getCodeStyle() async {
    final prefs = await SharedPreferences.getInstance();
    final styleJson = prefs.getString(_codeStyleKey);
    if (styleJson != null && styleJson.isNotEmpty) {
      try {
        return jsonDecode(styleJson) as Map<String, dynamic>;
      } catch (e) {
        print('⚠️ Error al parsear estilo: $e');
      }
    }
    // Estilo por defecto
    return {
      'indentation': '2 spaces',
      'naming': 'camelCase',
      'comments': 'moderate',
      'lineLength': 80,
      'trailingCommas': true,
    };
  }
  
  // ========== MEMORIAS DEL PROYECTO ==========
  
  /// Guardar memorias específicas del proyecto
  /// Ejemplo: frameworks usados, patrones preferidos, decisiones arquitectónicas
  static Future<void> saveProjectMemory(String projectPath, Map<String, dynamic> memory) async {
    final prefs = await SharedPreferences.getInstance();
    final allMemories = await getAllProjectMemories();
    allMemories[projectPath] = memory;
    await prefs.setString(_projectMemoriesKey, jsonEncode(allMemories));
    print('✅ Memoria del proyecto guardada para: $projectPath');
  }
  
  /// Obtener memorias de un proyecto específico
  static Future<Map<String, dynamic>> getProjectMemory(String projectPath) async {
    final allMemories = await getAllProjectMemories();
    return allMemories[projectPath] ?? {};
  }
  
  /// Obtener todas las memorias de proyectos
  static Future<Map<String, dynamic>> getAllProjectMemories() async {
    final prefs = await SharedPreferences.getInstance();
    final memoriesJson = prefs.getString(_projectMemoriesKey);
    if (memoriesJson != null && memoriesJson.isNotEmpty) {
      try {
        return jsonDecode(memoriesJson) as Map<String, dynamic>;
      } catch (e) {
        print('⚠️ Error al parsear memorias: $e');
      }
    }
    return {};
  }
  
  /// Agregar framework usado al proyecto
  static Future<void> addFrameworkUsed(String projectPath, String framework) async {
    final memory = await getProjectMemory(projectPath);
    final frameworks = List<String>.from(memory['frameworks'] ?? []);
    if (!frameworks.contains(framework)) {
      frameworks.add(framework);
      memory['frameworks'] = frameworks;
      await saveProjectMemory(projectPath, memory);
      print('✅ Framework agregado: $framework');
    }
  }
  
  /// Agregar patrón usado al proyecto
  static Future<void> addPatternUsed(String projectPath, String pattern) async {
    final memory = await getProjectMemory(projectPath);
    final patterns = List<String>.from(memory['patterns'] ?? []);
    if (!patterns.contains(pattern)) {
      patterns.add(pattern);
      memory['patterns'] = patterns;
      await saveProjectMemory(projectPath, memory);
      print('✅ Patrón agregado: $pattern');
    }
  }
  
  // ========== ARQUITECTURA DEL PROYECTO ==========
  
  /// Guardar arquitectura del proyecto
  /// Ejemplo: "clean architecture", "MVC", "MVVM", "BLoC pattern"
  static Future<void> saveProjectArchitecture(String projectPath, String architecture) async {
    final memory = await getProjectMemory(projectPath);
    memory['architecture'] = architecture;
    await saveProjectMemory(projectPath, memory);
    print('✅ Arquitectura guardada: $architecture');
  }
  
  /// Obtener arquitectura del proyecto
  static Future<String?> getProjectArchitecture(String projectPath) async {
    final memory = await getProjectMemory(projectPath);
    return memory['architecture'] as String?;
  }
  
  // ========== CONTEXTO PARA LA IA ==========
  
  /// Generar contexto de reglas y memorias para la IA
  static Future<String> getContextForAI(String projectPath) async {
    final buffer = StringBuffer();
    
    // Reglas personalizadas
    final rules = await getRules();
    if (rules != null && rules.isNotEmpty) {
      buffer.writeln('=== REGLAS PERSONALIZADAS ===');
      buffer.writeln(rules);
      buffer.writeln();
    }
    
    // Estilo de código
    final codeStyle = await getCodeStyle();
    buffer.writeln('=== ESTILO DE CÓDIGO ===');
    buffer.writeln('Indentación: ${codeStyle['indentation']}');
    buffer.writeln('Naming: ${codeStyle['naming']}');
    buffer.writeln('Comentarios: ${codeStyle['comments']}');
    buffer.writeln('Longitud de línea: ${codeStyle['lineLength']}');
    buffer.writeln('Trailing commas: ${codeStyle['trailingCommas']}');
    buffer.writeln();
    
    // Memoria del proyecto
    final memory = await getProjectMemory(projectPath);
    if (memory.isNotEmpty) {
      buffer.writeln('=== MEMORIA DEL PROYECTO ===');
      
      if (memory['architecture'] != null) {
        buffer.writeln('Arquitectura: ${memory['architecture']}');
      }
      
      if (memory['frameworks'] != null) {
        final frameworks = List<String>.from(memory['frameworks']);
        buffer.writeln('Frameworks: ${frameworks.join(', ')}');
      }
      
      if (memory['patterns'] != null) {
        final patterns = List<String>.from(memory['patterns']);
        buffer.writeln('Patrones: ${patterns.join(', ')}');
      }
      
      buffer.writeln();
    }
    
    return buffer.toString();
  }
}

