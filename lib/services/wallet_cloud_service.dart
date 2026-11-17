import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/credit_transaction.dart';
import 'auth_service.dart';

/// Saldo + transacciones en Firestore: `users/{uid}`.
///
/// Reglas sugeridas (Firebase Console → Firestore → Rules):
/// ```
/// rules_version = '2';
/// service cloud.firestore {
///   match /databases/{database}/documents {
///     match /users/{userId} {
///       allow read, write: if request.auth != null && request.auth.uid == userId;
///       match /transactions/{txId} {
///         allow read, write: if request.auth != null && request.auth.uid == userId;
///       }
///     }
///   }
/// }
/// ```
class WalletCloudService {
  WalletCloudService._();

  static bool get isAvailable {
    final auth = AuthService.instance;
    return auth.usesFirebase &&
        auth.isSignedIn &&
        (auth.currentUser?.isFirebase ?? false);
  }

  static DocumentReference<Map<String, dynamic>>? _userDoc() {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || !isAvailable) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  /// Lee saldo remoto. `null` = no hay cloud / error / doc inexistente.
  static Future<double?> fetchBalance() async {
    final doc = _userDoc();
    if (doc == null) return null;
    try {
      final snap = await doc.get();
      if (!snap.exists) return null;
      final data = snap.data();
      final bal = data?['balance'];
      if (bal is num) return bal.toDouble();
      return null;
    } catch (e) {
      debugPrint('⚠️ WalletCloud fetchBalance: $e');
      return null;
    }
  }

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

  /// Heartbeat para el panel admin (usuarios activos).
  static Future<void> touchPresence({
    String? email,
    String appVersion = '1.5.1',
  }) async {
    final doc = _userDoc();
    if (doc == null) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      await doc.set(
        {
          if (email != null && email.isNotEmpty) 'email': email,
          'status': 'active',
          'role': 'user',
          'platform': _platformLabel,
          'appVersion': appVersion,
          'lastActiveAt': FieldValue.serverTimestamp(),
          'lastActiveAtIso': nowIso,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('⚠️ WalletCloud touchPresence: $e');
    }
  }

  /// Crea/actualiza el doc del usuario con saldo + email.
  static Future<void> pushBalance(
    double balance, {
    String? email,
  }) async {
    final doc = _userDoc();
    if (doc == null) return;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      await doc.set(
        {
          'balance': balance,
          if (email != null && email.isNotEmpty) 'email': email,
          'status': 'active',
          'platform': _platformLabel,
          'lastActiveAt': FieldValue.serverTimestamp(),
          'lastActiveAtIso': nowIso,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('⚠️ WalletCloud pushBalance: $e');
    }
  }

  static Future<void> appendTransaction(CreditTransaction tx) async {
    final doc = _userDoc();
    if (doc == null) return;
    try {
      await doc.collection('transactions').doc(tx.id).set({
        ...tx.toJson(),
        'syncedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ WalletCloud appendTransaction: $e');
    }
  }

  static Future<List<CreditTransaction>> fetchTransactions({
    int limit = 80,
  }) async {
    final doc = _userDoc();
    if (doc == null) return const [];
    try {
      final qs = await doc
          .collection('transactions')
          .orderBy('date', descending: true)
          .limit(limit)
          .get();
      final items = <CreditTransaction>[];
      for (final d in qs.docs) {
        try {
          items.add(CreditTransaction.fromJson(d.data()));
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
    // Cloud es fuente de verdad entre dispositivos.
    await pushBalance(remote, email: email);
    return remote;
  }
}
