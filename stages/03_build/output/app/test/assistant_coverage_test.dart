import 'package:flutter_test/flutter_test.dart';
import 'package:quiet_restaurant_finder/services/supabase_service.dart';

// The `coverage` field is additive: the Edge Function and this app can deploy
// in either order, and an older Function simply omits it. These tests pin that
// tolerance down, because the failure mode — an exception thrown while parsing
// an optional field — would break a perfectly good answer.

void main() {
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
