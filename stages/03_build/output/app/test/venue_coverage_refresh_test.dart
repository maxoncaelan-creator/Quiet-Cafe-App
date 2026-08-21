import 'package:flutter_test/flutter_test.dart';
import 'package:quiet_restaurant_finder/services/supabase_service.dart';

void main() {
  test('maps a triggered venue refresh response', () {
    final refresh = VenueCoverageRefresh.fromJson({
      'triggered': true,
      'placesFound': 3,
      'reason': 'No venues are currently listed for this search scope.',
    });

    expect(refresh.triggered, isTrue);
    expect(refresh.placesFound, 3);
    expect(refresh.resultCount, isNull);
  });

  test('maps a guarded no-refresh response', () {
    final refresh = VenueCoverageRefresh.fromJson({
      'triggered': false,
      'resultCount': 26,
      'reason': 'coverage_sufficient',
    });

    expect(refresh.triggered, isFalse);
    expect(refresh.placesFound, isNull);
    expect(refresh.resultCount, 26);
    expect(refresh.reason, 'coverage_sufficient');
  });
}
