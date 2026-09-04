import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The single [ProviderContainer] for the whole app.
///
/// `main.dart`'s `ProviderScope` would normally create and own its own
/// container, invisible to anything outside the widget tree it wraps. That's
/// fine for a provider only ever read via `ref` inside a widget — but
/// `appRouter` in router.dart is a top-level global, built once at import
/// time, and GoRouter's `redirect` callback runs outside the widget tree
/// entirely: it has no `BuildContext` it can trust to carry a `ProviderScope`
/// ancestor, and no `ref.watch` it can call. Riverpod state has to be
/// reachable from a plain global too, or the router literally cannot see it.
///
/// So this container is created here instead, and `main.dart` hands this
/// exact instance to `UncontrolledProviderScope` rather than letting
/// `ProviderScope` build its own — the widget tree and the router then read
/// and write the *same* state, instead of silently diverging copies of it.
/// See `beta_gate_provider.dart` and `beta_gate_router_refresh.dart` for the
/// first thing built on top of this.
final providerContainer = ProviderContainer();
