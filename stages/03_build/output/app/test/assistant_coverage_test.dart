import 'package:flutter_test/flutter_test.dart';
import 'package:quiet_restaurant_finder/services/supabase_service.dart';

// The `coverage` field is additive: the Edge Function and this app can deploy
// in either order, and an older Function simply omits it. These tests pin that
// tolerance down, because the failure mode — an exception thrown while parsing
// an optional field — would break a perfectly good answer.

void main() {
  _betaAccessTests();
  _budgetExhaustedTests();

  group('assistantCoverageFromResponse', () {
    test('reads a queued refresh with its next-eligible time', () {
      final coverage = assistantCoverageFromResponse({
        'status': 'refresh_queued',
        'suburb': 'Crows Nest',
        'nextEligibleAt': '2026-08-24T01:00:00.000Z',
      });

      expect(coverage, isNotNull);
      expect(coverage!.status, AssistantCoverageStatus.refreshQueued);
      expect(coverage.suburb, 'Crows Nest');
      expect(coverage.nextEligibleAt, DateTime.parse('2026-08-24T01:00:00.000Z'));
    });

    test('reads a sweep already in progress', () {
      final coverage = assistantCoverageFromResponse({
        'status': 'refresh_pending',
        'suburb': 'Newtown',
        'nextEligibleAt': null,
      });

      expect(coverage!.status, AssistantCoverageStatus.refreshPending);
      expect(coverage.nextEligibleAt, isNull);
    });

    test('reads an up-to-date suburb', () {
      final coverage = assistantCoverageFromResponse({
        'status': 'up_to_date',
        'suburb': 'Mortdale',
      });

      expect(coverage!.status, AssistantCoverageStatus.upToDate);
      expect(coverage.suburb, 'Mortdale');
    });

    test('returns null when the backend sends no coverage at all', () {
      // An older Edge Function version. Must be ordinary, never an error.
      expect(assistantCoverageFromResponse(null), isNull);
    });

    test('returns null for a status this build does not know', () {
      // A newer backend adding a status must not break an older app.
      expect(
        assistantCoverageFromResponse(
            {'status': 'something_new', 'suburb': 'Balmain'}),
        isNull,
      );
    });

    test('returns null when the suburb is missing or empty', () {
      expect(
        assistantCoverageFromResponse({'status': 'refresh_queued'}),
        isNull,
      );
      expect(
        assistantCoverageFromResponse(
            {'status': 'refresh_queued', 'suburb': ''}),
        isNull,
      );
    });

    test('survives malformed shapes rather than throwing', () {
      expect(assistantCoverageFromResponse('not a map'), isNull);
      expect(assistantCoverageFromResponse(42), isNull);
      expect(assistantCoverageFromResponse([]), isNull);
      expect(
        assistantCoverageFromResponse({'status': 123, 'suburb': 456}),
        isNull,
      );
    });

    test('keeps the suburb when nextEligibleAt is unparseable', () {
      // A bad timestamp should cost us the timestamp, not the whole message.
      final coverage = assistantCoverageFromResponse({
        'status': 'refresh_queued',
        'suburb': 'Kiama',
        'nextEligibleAt': 'not-a-date',
      });

      expect(coverage, isNotNull);
      expect(coverage!.suburb, 'Kiama');
      expect(coverage.nextEligibleAt, isNull);
    });
  });
}

// The beta gate became a server-side check on 2026-08-24. Before that,
// search-assistant only verified sign-in, so the Flutter router was the whole
// gate and any signed-in account could call the Function directly.
void _betaAccessTests() {
  group('searchAssistantAccessDeniedFromResponse', () {
    test('recognises the documented 403 payload', () {
      final denied = searchAssistantAccessDeniedFromResponse(403, {
        'error': 'beta_access_required',
        'message': 'Redeem your beta code to use Search Assistant.',
      });

      expect(denied, isNotNull);
      expect(denied!.message, contains('beta code'));
    });

    test('falls back to a usable message when the backend sends none', () {
      final denied = searchAssistantAccessDeniedFromResponse(
          403, {'error': 'beta_access_required'});

      expect(denied, isNotNull);
      expect(denied!.message, isNotEmpty);
    });

    test('leaves an unrelated 403 as a generic failure', () {
      // Mislabelling this would send someone hunting for a code they hold.
      expect(
        searchAssistantAccessDeniedFromResponse(403, {'error': 'forbidden'}),
        isNull,
      );
    });

    test('ignores non-403 statuses and malformed bodies', () {
      expect(
        searchAssistantAccessDeniedFromResponse(
            429, {'error': 'beta_access_required'}),
        isNull,
      );
      expect(searchAssistantAccessDeniedFromResponse(403, null), isNull);
      expect(searchAssistantAccessDeniedFromResponse(403, 'nope'), isNull);
    });
  });
}

// A global ceiling must never borrow the per-account rate-limit wording. The
// two mean different things to the person reading them.
void _budgetExhaustedTests() {
  group('searchAssistantBudgetExhaustedFromResponse', () {
    test('recognises the documented 503 payload', () {
      final exhausted = searchAssistantBudgetExhaustedFromResponse(503, {
        'error': 'assistant_budget_exhausted',
        'resetAt': '2026-09-01T00:00:00.000Z',
      });

      expect(exhausted, isNotNull);
      expect(exhausted!.resetAt, DateTime.parse('2026-09-01T00:00:00.000Z'));
    });

    test('leaves an unrelated 503 as a generic failure', () {
      expect(
        searchAssistantBudgetExhaustedFromResponse(503, {'error': 'upstream'}),
        isNull,
      );
    });

    test('does not fire on the per-account 429', () {
      // The two must stay separate: 429 is "you", 503 is "the app".
      expect(
        searchAssistantBudgetExhaustedFromResponse(
            429, {'error': 'rate_limited', 'resetAt': '2026-09-01T00:00:00.000Z'}),
        isNull,
      );
    });

    test('returns null without a usable resetAt', () {
      expect(
        searchAssistantBudgetExhaustedFromResponse(
            503, {'error': 'assistant_budget_exhausted'}),
        isNull,
      );
      expect(
        searchAssistantBudgetExhaustedFromResponse(503,
            {'error': 'assistant_budget_exhausted', 'resetAt': 'not-a-date'}),
        isNull,
      );
    });

    test('survives malformed shapes', () {
      expect(searchAssistantBudgetExhaustedFromResponse(503, null), isNull);
      expect(searchAssistantBudgetExhaustedFromResponse(503, 'nope'), isNull);
    });
  });
}
