// Bridges betaAccessProvider to GoRouter's refreshListenable, which wants a
// plain Listenable, not a Riverpod provider. See provider_container.dart's
// doc comment for why this has to exist at all: router.dart's redirect runs
// outside the widget tree, with no ref.watch it can call to be told when
// betaAccessProvider's state changes.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'beta_gate_provider.dart';

class BetaGateRouterRefresh extends ChangeNotifier {
  /// [container] must be the same [ProviderContainer] the widget tree reads
  /// from — see provider_container.dart. Listening to a different instance
  /// would watch state the app never actually renders from, and the
  /// redirect would silently never re-run.
  BetaGateRouterRefresh(ProviderContainer container) {
    // container.listen also performs betaAccessProvider's first read, which
    // is what starts the very first access check — the equivalent of
    // BetaGateNotifier's constructor calling `unawaited(refresh())`.
    _subscription = container.listen<AsyncValue<bool>>(
      betaAccessProvider,
      (_, __) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AsyncValue<bool>> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
