import 'package:shared_preferences/shared_preferences.dart';

class RuleService {
  static const String _rulesKey = 'ai_rules';

  // Guardar reglas
  static Future<void> saveRules(String rules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rulesKey, rules);
  }

  // Obtener reglas
  static Future<String?> getRules() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rulesKey);
  }

  // Verificar si hay reglas guardadas
  static Future<bool> hasRules() async {
    final rules = await getRules();
    return rules != null && rules.isNotEmpty;
  }
}
