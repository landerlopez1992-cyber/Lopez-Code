import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lopez_code_ai/screens/wallet_screen.dart';
import 'package:lopez_code_ai/services/auth_service.dart';
import 'package:lopez_code_ai/services/credit_service.dart';

Future<void> _signInForTests() async {
  await AuthService.instance.initialize();
  if (AuthService.instance.isSignedIn) return;
  final email =
      'test_${DateTime.now().microsecondsSinceEpoch}@voryxel.local';
  try {
    await AuthService.instance.register(email: email, password: 'test1234');
  } catch (_) {
    await AuthService.instance.signIn(email: email, password: 'test1234');
  }
}

Future<void> _disposeWallet(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WalletScreen anónimo muestra \$0 y pide login', (tester) async {
    SharedPreferences.setMockInitialValues({'user_balance': 20.0});
    await AuthService.instance.initialize();
    await AuthService.instance.signOut();
    await tester.pumpWidget(
      const MaterialApp(home: WalletScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Billetera'), findsOneWidget);
    expect(find.textContaining('\$0.00'), findsWidgets);
    expect(find.text('+ \$5'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    await _disposeWallet(tester);
  });

  testWidgets('recarga +\$5 con sesión actualiza saldo', (tester) async {
    SharedPreferences.setMockInitialValues({
      'credit_migrated_to_uid_v1': true,
    });
    await _signInForTests();
    await CreditService.setBalance(20);
    await tester.pumpWidget(
      const MaterialApp(home: WalletScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('+ \$5'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('\$25.00'), findsWidgets);
    final txs = await CreditService.getTransactions();
    expect(txs, isNotEmpty);
    expect(txs.first.typeLabel, 'Recarga');
    expect(txs.first.cost, 5.0);
    await _disposeWallet(tester);
  });

  test('anónimo inicia en 0 y no ve saldo legado; login migra', () async {
    SharedPreferences.setMockInitialValues({'user_balance': 19.01});
    await AuthService.instance.initialize();
    await AuthService.instance.signOut();
    expect(await CreditService.getBalance(), 0.0);
    expect(
      () => CreditService.addCredits(5),
      throwsA(isA<AuthException>()),
    );

    await _signInForTests();
    // Primera sesión hereda el saldo legado una sola vez.
    expect(await CreditService.getBalance(), 19.01);
  });

  test('CreditService addCredits con sesión registra recarga', () async {
    SharedPreferences.setMockInitialValues({
      'credit_migrated_to_uid_v1': true,
    });
    await _signInForTests();
    await CreditService.setBalance(0);
    await CreditService.addCredits(5);
    expect(await CreditService.getBalance(), 5.0);
    final txs = await CreditService.getTransactions();
    expect(txs, isNotEmpty);
    expect(txs.first.typeLabel, 'Recarga');
  });

  test('CreditService deductCredits registra uso con tokens', () async {
    SharedPreferences.setMockInitialValues({
      'credit_migrated_to_uid_v1': true,
    });
    await _signInForTests();
    await CreditService.setBalance(20);
    final ok = await CreditService.deductCredits(
      1000,
      0.00001,
      model: 'gpt-4.1',
    );
    expect(ok, isTrue);
    final txs = await CreditService.getTransactions();
    expect(txs.first.tokens, 1000);
    expect(txs.first.model, 'gpt-4.1');
  });

  test('cerrar sesión oculta el saldo de la cuenta', () async {
    SharedPreferences.setMockInitialValues({
      'credit_migrated_to_uid_v1': true,
    });
    await _signInForTests();
    await CreditService.setBalance(12.5);
    expect(await CreditService.getBalance(), 12.5);
    await AuthService.instance.signOut();
    expect(await CreditService.getBalance(), 0.0);
  });
}
