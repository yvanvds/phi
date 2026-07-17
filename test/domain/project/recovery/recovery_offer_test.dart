import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/recovery/recovery_offer.dart';

void main() {
  test('offers compare by value', () {
    expect(
      const RecoveryOffer(entryCount: 3, crashLoop: false),
      const RecoveryOffer(entryCount: 3, crashLoop: false),
    );
    expect(
      const RecoveryOffer(entryCount: 3, crashLoop: false),
      isNot(const RecoveryOffer(entryCount: 3, crashLoop: true)),
    );
    expect(
      const RecoveryOffer(entryCount: 3, crashLoop: false).hashCode,
      const RecoveryOffer(entryCount: 3, crashLoop: false).hashCode,
    );
  });

  test('every choice is distinct', () {
    expect(RecoveryChoice.values, hasLength(3));
    expect(RecoveryChoice.values.toSet(), hasLength(3));
  });
}
