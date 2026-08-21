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

  test('maps a recent nearby coordinate-check response', () {
    final refresh = VenueCoverageRefresh.fromJson({
      'triggered': false,
      'reason': 'nearby_recently_checked',
      'checkedAt': '2026-08-22T00:00:00Z',
    });

    expect(refresh.triggered, isFalse);
    expect(refresh.reason, 'nearby_recently_checked');
  });
}
