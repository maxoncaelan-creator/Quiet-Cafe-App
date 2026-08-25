import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';

/// The app's [SupabaseService], injected rather than constructed in place.
///
/// This is the dependency seam the incremental Riverpod migration needs. Step 3a
/// shipped `favouriteIdsProvider` with **no unit test at all**, because the
/// notifier built its own `SupabaseService()` and nothing could stand in for it —
/// the one behaviour worth testing, two screens staying in sync, was verifiable
/// only by hand on a device.
///
/// Overriding this in a `ProviderContainer` is now the supported way to test any
/// provider that talks to the backend:
///
/// ```dart
/// ProviderContainer(overrides: [
///   supabaseServiceProvider.overrideWithValue(FakeSupabaseService()),
/// ]);
/// ```
///
/// `SupabaseService` holds no state of its own — it reads `Supabase.instance` on
/// demand — so returning a fresh instance is cheap and carries nothing between
/// callers.
final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});
