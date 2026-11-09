import 'package:alwaha_pricing/auth/distributor_auth.dart';
import 'package:alwaha_pricing/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows setup instructions before Supabase is configured',
      (tester) async {
    await tester.pumpWidget(
      const AlWahaApp(supabaseConfigured: false, mode: AppMode.staff),
    );

    expect(
      find.textContaining('SUPABASE_URL'),
      findsOneWidget,
    );
  });

  testWidgets('distributor app also shows setup instructions', (tester) async {
    await tester.pumpWidget(
      const AlWahaApp(supabaseConfigured: false, mode: AppMode.distributor),
    );

    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
  });

  test('phone numbers are normalized to local Egyptian format', () {
    expect(normalizePhone('+20 101 234 5678'), '01012345678');
    expect(normalizePhone('0020 101 234 5678'), '01012345678');
    expect(normalizePhone('٠١٠١٢٣٤٥٦٧٨'), '01012345678');
    expect(phoneToEmail('01012345678'), '01012345678@phone.alwaha.app');
    expect(isValidPhone('01012345678'), isTrue);
    expect(isValidPhone('12345'), isFalse);
  });
}
