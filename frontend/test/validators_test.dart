import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/utils/validators.dart';

void main() {
  test('amount validation', () {
    expect(validateAmount('3600'), isNull);
    expect(validateAmount('49.99'), isNull);
    expect(validateAmount('0'), isNotNull);
    expect(validateAmount('-5'), isNotNull);
    expect(validateAmount('abc'), isNotNull);
    expect(validateAmount('10.555'), isNotNull);
    expect(validateAmount(''), isNotNull);
  });

  test('email validation', () {
    expect(validateEmail('a@b.com'), isNull);
    expect(validateEmail('not-an-email'), isNotNull);
    expect(validateEmail(''), isNotNull);
  });

  test('paise conversion avoids float error', () {
    expect(toPaise(0.1 + 0.2), 30);
    expect(toPaise(33.33), 3333);
  });
}
