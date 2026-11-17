import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'credit_service.dart';
import 'wallet_cloud_service.dart';

/// Usuario autenticado (Firebase o fallback local).
class VoryxelUser {
  final String uid;
  final String email;
  final bool isFirebase;

  const VoryxelUser({
    required this.uid,
    required this.email,
    required this.isFirebase,
  });
}

/// Auth de la app: Firebase cuando está configurado; si no, cuentas locales
/// (misma UX) hasta que corras `flutterfire configure`.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _localUsersKey = 'voryxel_local_users_v1';
  static const _localSessionKey = 'voryxel_local_session_uid';

  bool _ready = false;
  bool _firebaseReady = false;
  VoryxelUser? _user;

  bool get isReady => _ready;
  bool get usesFirebase => _firebaseReady;
  VoryxelUser? get currentUser => _user;
  bool get isSignedIn => _user != null;

  Future<void> initialize() async {
    if (_ready) return;
    try {
      if (DefaultFirebaseOptions.isConfigured) {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          ).timeout(const Duration(seconds: 6));
        }
        _firebaseReady = true;
        final fbUser = FirebaseAuth.instance.currentUser;
        if (fbUser != null && fbUser.email != null) {
          _user = VoryxelUser(
            uid: fbUser.uid,
            email: fbUser.email!,
            isFirebase: true,
          );
          // No await: no bloquear arranque; trae saldo de Firestore.
          // ignore: unawaited_futures
          CreditService.syncFromCloudAfterLogin();
          // ignore: unawaited_futures
          WalletCloudService.touchPresence(email: fbUser.email);
        }
        FirebaseAuth.instance.authStateChanges().listen((u) async {
          if (u != null && u.email != null) {
            _user = VoryxelUser(
              uid: u.uid,
              email: u.email!,
              isFirebase: true,
            );
            notifyListeners();
            await CreditService.syncFromCloudAfterLogin();
            await WalletCloudService.touchPresence(email: u.email);
          } else if (_firebaseReady) {
            _user = null;
            notifyListeners();
          }
        });
      } else {
        debugPrint(
          'ℹ️ Firebase no configurado — Auth local activo. '
          'Corre: dart pub global activate flutterfire_cli && flutterfire configure',
        );
        await _restoreLocalSession();
      }
    } catch (e) {
      debugPrint('⚠️ Firebase init falló, usando Auth local: $e');
      _firebaseReady = false;
      try {
        await _restoreLocalSession();
      } catch (_) {}
    }
    _ready = true;
    notifyListeners();
  }

  Future<VoryxelUser> register({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    _validateCredentials(normalized, password);

    if (_firebaseReady) {
      try {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: normalized,
          password: password,
        );
        final u = cred.user;
        if (u == null || u.email == null) {
          throw AuthException('No se pudo crear la cuenta');
        }
        _user = VoryxelUser(uid: u.uid, email: u.email!, isFirebase: true);
        notifyListeners();
        try {
          await CreditService.syncFromCloudAfterLogin();
        } catch (e) {
          debugPrint('⚠️ Sync billetera tras registro: $e');
        }
        return _user!;
      } on FirebaseAuthException catch (e) {
        debugPrint('🔥 Auth register error: code=${e.code} message=${e.message}');
        throw AuthException(_mapFirebaseAuthError(e, registering: true));
      } catch (e) {
        debugPrint('🔥 Auth register unexpected: $e');
        throw AuthException(
          'No se pudo crear la cuenta. Revisa conexión o Firebase Auth.',
        );
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final users = await _loadLocalUsers(prefs);
    if (users.any((u) => u['email'] == normalized)) {
      throw AuthException('Ya existe una cuenta con ese email');
    }
    final uid = 'local_${DateTime.now().millisecondsSinceEpoch}';
    users.add({
      'uid': uid,
      'email': normalized,
      'passwordHash': _hashPassword(normalized, password),
    });
    await prefs.setString(_localUsersKey, jsonEncode(users));
    await prefs.setString(_localSessionKey, uid);
    _user = VoryxelUser(uid: uid, email: normalized, isFirebase: false);
    notifyListeners();
    return _user!;
  }

  Future<VoryxelUser> signIn({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    _validateCredentials(normalized, password);

    if (_firebaseReady) {
      try {
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: normalized,
          password: password,
        );
        final u = cred.user;
        if (u == null || u.email == null) {
          throw AuthException('No se pudo iniciar sesión');
        }
        _user = VoryxelUser(uid: u.uid, email: u.email!, isFirebase: true);
        notifyListeners();
        try {
          await CreditService.syncFromCloudAfterLogin();
        } catch (e) {
          debugPrint('⚠️ Sync billetera tras login: $e');
        }
        return _user!;
      } on FirebaseAuthException catch (e) {
        debugPrint('🔥 Auth signIn error: code=${e.code} message=${e.message}');
        throw AuthException(_mapFirebaseAuthError(e, registering: false));
      } catch (e) {
        debugPrint('🔥 Auth signIn unexpected: $e');
        throw AuthException(
          'No se pudo iniciar sesión. Revisa conexión o Firebase Auth.',
        );
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final users = await _loadLocalUsers(prefs);
    final match = users.cast<Map<String, dynamic>?>().firstWhere(
      (u) =>
          u != null &&
          u['email'] == normalized &&
          u['passwordHash'] == _hashPassword(normalized, password),
      orElse: () => null,
    );
    if (match == null) {
      throw AuthException('Email o contraseña incorrectos');
    }
    final uid = match['uid'] as String;
    await prefs.setString(_localSessionKey, uid);
    _user = VoryxelUser(uid: uid, email: normalized, isFirebase: false);
    notifyListeners();
    return _user!;
  }

  Future<void> signOut() async {
    if (_firebaseReady) {
      await FirebaseAuth.instance.signOut();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localSessionKey);
    _user = null;
    notifyListeners();
  }

  /// Elimina la cuenta del usuario actual (pide contraseña para confirmar).
  Future<void> deleteAccount({required String password}) async {
    final user = _user;
    if (user == null) throw AuthException('No hay sesión activa');

    if (_firebaseReady && user.isFirebase) {
      try {
        final fb = FirebaseAuth.instance.currentUser;
        if (fb == null || fb.email == null) {
          throw AuthException('Sesión Firebase inválida');
        }
        final cred = EmailAuthProvider.credential(
          email: fb.email!,
          password: password,
        );
        await fb.reauthenticateWithCredential(cred);
        await fb.delete();
        _user = null;
        notifyListeners();
        return;
      } on FirebaseAuthException catch (e) {
        debugPrint('🔥 Auth delete error: code=${e.code} message=${e.message}');
        throw AuthException(_mapFirebaseAuthError(e));
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final users = await _loadLocalUsers(prefs);
    final hash = _hashPassword(user.email, password);
    final idx = users.indexWhere(
      (u) => u['uid'] == user.uid && u['passwordHash'] == hash,
    );
    if (idx < 0) {
      throw AuthException('Contraseña incorrecta');
    }
    users.removeAt(idx);
    await prefs.setString(_localUsersKey, jsonEncode(users));
    await prefs.remove(_localSessionKey);
    _user = null;
    notifyListeners();
  }

  void _validateCredentials(String email, String password) {
    if (!email.contains('@') || email.length < 5) {
      throw AuthException('Email inválido');
    }
    if (password.length < 6) {
      throw AuthException('La contraseña debe tener al menos 6 caracteres');
    }
  }

  /// Mensajes claros en español (no códigos crudos de Firebase).
  static String _mapFirebaseAuthError(
    FirebaseAuthException e, {
    bool registering = false,
  }) {
    final code = e.code.trim();
    final rawMsg = (e.message ?? '').toUpperCase();

    // A veces el plugin trae el código REST en message (EMAIL_EXISTS, etc.).
    if (rawMsg.contains('EMAIL_EXISTS') || code == 'email-already-in-use') {
      return 'Ya existe una cuenta con ese email. Usa «Iniciar sesión»';
    }
    if (rawMsg.contains('INVALID_LOGIN_CREDENTIALS') ||
        rawMsg.contains('INVALID_PASSWORD') ||
        rawMsg.contains('EMAIL_NOT_FOUND')) {
      return 'Email o contraseña incorrectos. Si no tienes cuenta, usa «Crear cuenta nueva»';
    }

    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'INVALID_LOGIN_CREDENTIALS':
        return registering
            ? 'Ya existe una cuenta con ese email o los datos no son válidos. '
                'Prueba «Iniciar sesión»'
            : 'Email o contraseña incorrectos. Si no tienes cuenta, usa «Crear cuenta nueva»';
      case 'email-already-in-use':
        return 'Ya existe una cuenta con ese email. Usa «Iniciar sesión»';
      case 'invalid-email':
        return 'Email inválido';
      case 'weak-password':
        return 'La contraseña es demasiado débil (mín. 6 caracteres)';
      case 'user-disabled':
        return 'Esta cuenta está deshabilitada';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera un momento e inténtalo de nuevo';
      case 'network-request-failed':
        return 'Sin conexión. Revisa tu internet e inténtalo de nuevo';
      case 'operation-not-allowed':
      case 'CONFIGURATION_NOT_FOUND':
      case 'configuration-not-found':
        return 'Email/contraseña no está habilitado en Firebase Console '
            '(Authentication → Sign-in method → Email/Password)';
      case 'requires-recent-login':
        return 'Por seguridad, vuelve a iniciar sesión e inténtalo de nuevo';
      case 'internal-error':
      case 'unknown':
        if (registering) {
          return 'No se pudo crear la cuenta. Si ya te registraste antes, '
              'usa «Iniciar sesión» con la misma contraseña';
        }
        return 'No se pudo iniciar sesión. Revisa la contraseña '
            '(el email ya está registrado en Firebase)';
      case 'app-not-authorized':
      case 'admin-restricted-operation':
        return 'Esta app no está autorizada en el proyecto Firebase';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Firebase no respondió a tiempo. Inténtalo de nuevo';
      default:
        final hint = (e.message != null && e.message!.trim().isNotEmpty)
            ? e.message!.trim()
            : code;
        return registering
            ? 'No se pudo crear la cuenta ($hint)'
            : 'No se pudo iniciar sesión ($hint)';
    }
  }

  String _hashPassword(String email, String password) {
    final bytes = utf8.encode('$email::$password::voryxel');
    return sha256.convert(bytes).toString();
  }

  Future<List<Map<String, dynamic>>> _loadLocalUsers(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_localUsersKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _restoreLocalSession() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_localSessionKey);
    if (uid == null || uid.isEmpty) return;
    final users = await _loadLocalUsers(prefs);
    final match = users.cast<Map<String, dynamic>?>().firstWhere(
      (u) => u != null && u['uid'] == uid,
      orElse: () => null,
    );
    if (match == null) {
      await prefs.remove(_localSessionKey);
      return;
    }
    _user = VoryxelUser(
      uid: match['uid'] as String,
      email: match['email'] as String,
      isFirebase: false,
    );
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}
