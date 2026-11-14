import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lopez_code_ai/screens/wallet_screen.dart';
import 'package:lopez_code_ai/services/credit_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WalletScreen muestra saldo y botones de recarga', (tester) async {
    SharedPreferences.setMockInitialValues({'user_balance': 20.0});
    await tester.pumpWidget(
      const MaterialApp(home: WalletScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Billetera'), findsOneWidget);
    expect(find.textContaining('\$20.00'), findsWidgets);
    expect(find.text('+ \$5'), findsOneWidget);
    expect(find.text('+ \$10'), findsOneWidget);
    expect(find.text('+ \$25'), findsOneWidget);
    expect(find.text('TRANSACCIONES'), findsOneWidget);
  });

  testWidgets('recarga +\$5 actualiza saldo y aparece en transacciones',
      (tester) async {
    SharedPreferences.setMockInitialValues({'user_balance': 20.0});
    await tester.pumpWidget(
      const MaterialApp(home: WalletScreen()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ \$5'));
    await tester.pump(); // snackbar + reload
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('\$25.00'), findsWidgets);
    final txs = await CreditService.getTransactions();
    expect(txs, isNotEmpty);
    expect(txs.first.typeLabel, 'Recarga');
    expect(txs.first.cost, 5.0);
  });

  test('CreditService get/add balance y registra transacción', () async {
    SharedPreferences.setMockInitialValues({});
    final b = await CreditService.getBalance();
    expect(b, 20.0);
    await CreditService.addCredits(5);
    expect(await CreditService.getBalance(), 25.0);
    final txs = await CreditService.getTransactions();
    expect(txs, isNotEmpty);
    expect(txs.first.typeLabel, 'Recarga');
  });

  test('CreditService deductCredits registra uso con tokens', () async {
    SharedPreferences.setMockInitialValues({'user_balance': 20.0});
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
}
