import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import '../models/credit_transaction.dart';
import 'auth_service.dart';

/// Saldo + transacciones en Firestore vía **REST** (sin `cloud_firestore`).
/// Así macOS no compila gRPC/BoringSSL y Run/Debug vuelve a ser rápido.
///
/// Docs: `users/{uid}` + `users/{uid}/transactions/{txId}`
class WalletCloudService {
  WalletCloudService._();

  static bool get isAvailable {
    final auth = AuthService.instance;
    return auth.usesFirebase &&
        auth.isSignedIn &&
        (auth.currentUser?.isFirebase ?? false) &&
        DefaultFirebaseOptions.isConfigured;
  }

  static String get _projectId => DefaultFirebaseOptions.macos.projectId;

  static String get _platformLabel {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isMacOS) return 'macos';
      if (Platform.isIOS) return 'ios';
      if (Platform.isAndroid) return 'android';
      if (Platform.isWindows) return 'windows';
      if (Platform.isLinux) return 'linux';
    } catch (_) {}
    return 'unknown';
  }

  static Uri _userDocUri(String uid) => Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId/'
        'databases/(default)/documents/users/$uid',
      );

  static Uri _txDocUri(String uid, String txId) => Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId/'
        'databases/(default)/documents/users/$uid/transactions/$txId',
      );

  static Uri _txListUri(String uid, {int limit = 80}) => Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId/'
        'databases/(default)/documents/users/$uid/transactions'
        '?pageSize=$limit&orderBy=date%20desc',
      );

  static Future<String?> _idToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (e) {
      debugPrint('⚠️ WalletCloud idToken: $e');
      return null;
    }
  }

  static String? get _uid => AuthService.instance.currentUser?.uid;

  static Map<String, dynamic> _fields(Map<String, dynamic> data) {
    final fields = <String, dynamic>{};
    data.forEach((k, v) {
      if (v == null) return;
      if (v is String) {
        fields[k] = {'stringValue': v};
      } else if (v is bool) {
        fields[k] = {'booleanValue': v};
      } else if (v is int) {
        fields[k] = {'integerValue': '$v'};
      } else if (v is num) {
        fields[k] = {'doubleValue': v.toDouble()};
      } else {
        fields[k] = {'stringValue': v.toString()};
      }
    });
    return fields;
  }

  static Map<String, dynamic> _decodeFields(Map<String, dynamic>? fields) {
    if (fields == null) return {};
    final out = <String, dynamic>{};
    fields.forEach((k, raw) {
      if (raw is! Map) return;
      final m = Map<String, dynamic>.from(raw);
      if (m.containsKey('stringValue')) {
        out[k] = m['stringValue'];
      } else if (m.containsKey('doubleValue')) {
        out[k] = (m['doubleValue'] as num).toDouble();
      } else if (m.containsKey('integerValue')) {
        out[k] = int.tryParse('${m['integerValue']}') ?? 0;
      } else if (m.containsKey('booleanValue')) {
        out[k] = m['booleanValue'] == true;
      }
    });
    return out;
  }

  static Future<http.Response?> _patchMerge(
    Uri uri,
    Map<String, dynamic> data,
  ) async {
    final token = await _idToken();
    final uid = _uid;
    if (token == null || uid == null) return null;
    final keys = data.keys.toList();
    final qp = <String>[];
    for (final k in keys) {
      qp.add('updateMask.fieldPaths=$k');
    }
    final url = uri.replace(query: qp.join('&'));
    return http.patch(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'fields': _fields(data)}),
    );
  }

  /// Lee saldo remoto. `null` = no hay cloud / error / doc inexistente.
  static Future<double?> fetchBalance() async {
    final token = await _idToken();
    final uid = _uid;
    if (token == null || uid == null || !isAvailable) return null;
    try {
      final res = await http.get(
        _userDocUri(uid),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) {
        debugPrint('⚠️ WalletCloud fetchBalance HTTP ${res.statusCode}');
        return null;
      }
      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      final decoded = _decodeFields(
        (body['fields'] as Map?)?.cast<String, dynamic>(),
      );
      final bal = decoded['balance'];
      if (bal is num) return bal.toDouble();
      return null;
    } catch (e) {
      debugPrint('⚠️ WalletCloud fetchBalance: $e');
      return null;
    }
  }

  /// Heartbeat para el panel admin (usuarios activos).
  static Future<void> touchPresence({
    String? email,
    String appVersion = '1.5.1',
  }) async {
    if (!isAvailable) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final uid = _uid;
    if (uid == null) return;
    try {
      final res = await _patchMerge(_userDocUri(uid), {
        if (email != null && email.isNotEmpty) 'email': email,
        'status': 'active',
        'role': 'user',
        'platform': _platformLabel,
        'appVersion': appVersion,
        'lastActiveAtIso': nowIso,
        'updatedAtIso': nowIso,
      });
      if (res != null && res.statusCode >= 300) {
        debugPrint('⚠️ WalletCloud touchPresence HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ WalletCloud touchPresence: $e');
    }
  }

  /// Crea/actualiza el doc del usuario con saldo + email.
  static Future<void> pushBalance(
    double balance, {
    String? email,
  }) async {
    if (!isAvailable) return;
    final uid = _uid;
    if (uid == null) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      final res = await _patchMerge(_userDocUri(uid), {
        'balance': balance,
        if (email != null && email.isNotEmpty) 'email': email,
        'status': 'active',
        'platform': _platformLabel,
        'lastActiveAtIso': nowIso,
        'updatedAtIso': nowIso,
      });
      if (res != null && res.statusCode >= 300) {
        debugPrint(
          '⚠️ WalletCloud pushBalance HTTP ${res.statusCode}: ${res.body}',
        );
      }
    } catch (e) {
      debugPrint('⚠️ WalletCloud pushBalance: $e');
    }
  }

  static Future<void> appendTransaction(CreditTransaction tx) async {
    if (!isAvailable) return;
    final uid = _uid;
    if (uid == null) return;
    try {
      final data = {
        ...tx.toJson(),
        'syncedAtIso': DateTime.now().toUtc().toIso8601String(),
      };
      final res = await _patchMerge(_txDocUri(uid, tx.id), data);
      if (res != null && res.statusCode >= 300) {
        debugPrint(
          '⚠️ WalletCloud appendTransaction HTTP ${res.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('⚠️ WalletCloud appendTransaction: $e');
    }
  }

  static Future<List<CreditTransaction>> fetchTransactions({
    int limit = 80,
  }) async {
    final token = await _idToken();
    final uid = _uid;
    if (token == null || uid == null || !isAvailable) return const [];
    try {
      final res = await http.get(
        _txListUri(uid, limit: limit),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 404) return const [];
      if (res.statusCode != 200) {
        debugPrint('⚠️ WalletCloud fetchTransactions HTTP ${res.statusCode}');
        return const [];
      }
      final body = jsonDecode(res.body);
      if (body is! Map) return const [];
      final docs = body['documents'];
      if (docs is! List) return const [];
      final items = <CreditTransaction>[];
      for (final d in docs) {
        if (d is! Map) continue;
        try {
          final decoded = _decodeFields(
            (d['fields'] as Map?)?.cast<String, dynamic>(),
          );
          items.add(CreditTransaction.fromJson(decoded));
        } catch (_) {}
      }
      return items;
    } catch (e) {
      debugPrint('⚠️ WalletCloud fetchTransactions: $e');
      return const [];
    }
  }

  /// Al login: si cloud tiene saldo, gana; si no, sube el local.
  static Future<double?> reconcileWithLocal(double localBalance) async {
    if (!isAvailable) return null;
    final remote = await fetchBalance();
    final email = AuthService.instance.currentUser?.email;
    if (remote == null) {
      await pushBalance(localBalance, email: email);
      return localBalance;
    }
    await pushBalance(remote, email: email);
    return remote;
  }
}
