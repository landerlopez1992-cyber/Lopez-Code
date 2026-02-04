import 'package:shared_preferences/shared_preferences.dart';

/// Servicio para gestionar créditos/tokens del usuario
/// Similar a cómo Cursor maneja los créditos de API
class CreditService {
  static const String _balanceKey = 'user_balance';
  static const double _initialBalance = 20.0; // $20 iniciales
  static const double _marginMultiplier = 1.2; // 20% de margen (ejemplo: OpenAI cobra $5, nosotros $6)
  
  /// Obtiene el saldo actual del usuario
  static Future<double> getBalance() async {
    final prefs = await SharedPreferences.getInstance();
    final balance = prefs.getDouble(_balanceKey);
    
    // Si no existe, inicializar con saldo inicial
    if (balance == null) {
      await setBalance(_initialBalance);
      return _initialBalance;
    }
    
    return balance;
  }
  
  /// Establece el saldo del usuario
  static Future<void> setBalance(double balance) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_balanceKey, balance);
  }
  
  /// Calcula el costo de una solicitud basado en tokens usados
  /// 
  /// Parámetros:
  /// - tokensUsed: Número de tokens usados en la solicitud
  /// - costPerToken: Costo por token de la API (ejemplo: 0.00001 para GPT-4o-mini)
  /// 
  /// Retorna: Costo total con margen aplicado
  static double calculateCost(int tokensUsed, double costPerToken) {
    final baseCost = tokensUsed * costPerToken;
    final costWithMargin = baseCost * _marginMultiplier;
    return costWithMargin;
  }
  
  /// Descuenta créditos de una solicitud
  /// 
  /// Retorna: true si se pudo descontar, false si no hay suficiente saldo
  static Future<bool> deductCredits(int tokensUsed, double costPerToken) async {
    final currentBalance = await getBalance();
    final cost = calculateCost(tokensUsed, costPerToken);
    
    if (currentBalance < cost) {
      return false; // Saldo insuficiente
    }
    
    final newBalance = currentBalance - cost;
    await setBalance(newBalance);
    return true;
  }
  
  /// Verifica si hay suficiente saldo para una solicitud
  static Future<bool> hasEnoughBalance(int estimatedTokens, double costPerToken) async {
    final currentBalance = await getBalance();
    final estimatedCost = calculateCost(estimatedTokens, costPerToken);
    return currentBalance >= estimatedCost;
  }
  
  /// Obtiene el costo estimado de una solicitud sin descontar
  static double getEstimatedCost(int tokens, double costPerToken) {
    return calculateCost(tokens, costPerToken);
  }
  
  /// Reinicia el saldo al valor inicial (útil para testing)
  static Future<void> resetBalance() async {
    await setBalance(_initialBalance);
  }
  
  /// Agrega créditos al saldo (útil para recargas)
  static Future<void> addCredits(double amount) async {
    final currentBalance = await getBalance();
    await setBalance(currentBalance + amount);
  }
  
  /// Obtiene el multiplicador de margen actual
  static double getMarginMultiplier() => _marginMultiplier;
  
  /// Obtiene el saldo inicial
  static double getInitialBalance() => _initialBalance;
}
