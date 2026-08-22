import 'package:flutter_test/flutter_test.dart';
import 'package:quiet_restaurant_finder/services/supabase_service.dart';

void main() {
  test('maps the search assistant 429 payload to its reset time', () {
    final rateLimit = searchAssistantRateLimitFromResponse(429, {
      'error': 'rate_limited',
      'resetAt': '2026-08-22T05:00:00Z',
    });

    expect(rateLimit, isNotNull);
    expect(rateLimit!.resetAt, DateTime.parse('2026-08-22T05:00:00Z'));
  });

  test('does not classify other function failures as a rate limit', () {
    expect(
      searchAssistantRateLimitFromResponse(500, {
        'error': 'assistant_unavailable',
        'resetAt': '2026-08-22T05:00:00Z',
      }),
      isNull,
    );
  });

  test('does not rate-limit on a malformed 429 response', () {
    expect(searchAssistantRateLimitFromResponse(429, const {}), isNull);
    expect(searchAssistantRateLimitFromResponse(429, const {'resetAt': 5}),
        isNull);
  });
}
