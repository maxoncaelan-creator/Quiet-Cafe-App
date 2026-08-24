import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/restaurant.dart';
import '../providers/favourites_provider.dart';
import '../services/supabase_service.dart';
import '../widgets/confidence_indicator.dart';
import '../widgets/loudness_vote_buttons.dart';
import '../widgets/max_width_content.dart';
import '../widgets/noise_level_bar.dart';
import '../widgets/venue_loudness_capture.dart';

class RestaurantDetailScreen extends ConsumerStatefulWidget {
  final Restaurant restaurant;

  const RestaurantDetailScreen({super.key, required this.restaurant});

  @override
  ConsumerState<RestaurantDetailScreen> createState() =>
      _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState
    extends ConsumerState<RestaurantDetailScreen> {
  final _supabaseService = SupabaseService();

  // Mutable (not just widget.restaurant) since 2026-08-20: a vote or mic
  // reading submitted from this screen changes the venue's score
  // server-side, and the screen needs to actually show that, not keep
  // rendering the static object it was first built with. See
  // _refreshRestaurant.
  late Restaurant _restaurant = widget.restaurant;
  Restaurant get restaurant => _restaurant;

  bool _favoriteBusy = false;
  bool _captureInProgress = false;

  @override
  void initState() {
    super.initState();
    // Favourite status is no longer fetched here. It comes from
    // favouriteIdsProvider, which loads the set once and shares it — the old
    // code fetched every favourite the user had, on every detail screen open,
    // purely to answer whether this one venue was among them.
  }

  /// Re-fetches this restaurant and updates the displayed score/confidence.
  /// Called after a vote or the in-place 10-second mic reading has triggered
  /// its server-side recompute. Best-effort — a failure here just leaves the
  /// screen showing what it already had, same as any other background refresh
  /// in this app.
  Future<void> _refreshRestaurant() async {
    try {
      final updated = await _supabaseService.fetchRestaurantByPlaceId(restaurant.placeId);
      if (mounted) setState(() => _restaurant = updated);
    } catch (_) {
      // Non-fatal — see doc comment above.
    }
  }


  Future<void> _toggleFavorite() async {
    if (!_supabaseService.isSignedIn) {
      final signedIn = await context.push<bool>('/sign-in');
      if (signedIn != true || !mounted) return;
    }
    setState(() => _favoriteBusy = true);
    try {
      // The provider owns the optimistic flip and the revert, so this screen no
      // longer keeps its own copy of the answer — which is what let the
      // favourites list go stale after unstarring from here.
      await ref.read(favouriteIdsProvider.notifier).toggle(restaurant.placeId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update favorite — try again.')),
      );
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  /// Same point-of-need sign-in prompt as favoriting, factored
  /// out so LoudnessVoteButtons (which doesn't know about this screen's
  /// SupabaseService instance) can reuse it.
  Future<bool> _ensureSignedIn(BuildContext context) async {
    if (_supabaseService.isSignedIn) return true;
    final signedIn = await context.push<bool>('/sign-in');
    return signedIn == true;
  }

  @override
  Widget build(BuildContext context) {
    // Watching the family provider means this screen rebuilds when *this*
    // venue's favourite state changes, not on every change to the whole set.
    final isFavourite = ref.watch(isFavouriteProvider(restaurant.placeId));

    // A 10-second sample has value only as a complete window. Blocking back
    // navigation prevents an accidental partial capture; Postgres separately
    // rejects any client that still tries to insert one.
    return PopScope(
      canPop: !_captureInProgress,
      child: Scaffold(
        appBar: AppBar(
          title: Text(restaurant.name),
          actions: [
            if (SupabaseService.isConfigured)
              IconButton(
                icon: Icon(
                  isFavourite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isFavourite ? Colors.amber.shade700 : null,
                ),
                onPressed: _favoriteBusy || _captureInProgress ? null : _toggleFavorite,
              ),
          ],
        ),
        body: MaxWidthContent(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (restaurant.address != null) Text(restaurant.address!),
              const SizedBox(height: 16),
              _ScoreHeader(restaurant: restaurant),
              const SizedBox(height: 24),
              LoudnessVoteButtons(
                placeId: restaurant.placeId,
                ensureSignedIn: _ensureSignedIn,
                onVoted: _refreshRestaurant,
                enabled: !_captureInProgress,
              ),
              const SizedBox(height: 24),
              VenueLoudnessCapture(
                placeId: restaurant.placeId,
                ensureSignedIn: _ensureSignedIn,
                onSubmitted: _refreshRestaurant,
                onRecordingChanged: (recording) => setState(() => _captureInProgress = recording),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  final Restaurant restaurant;

  const _ScoreHeader({required this.restaurant});

  @override
  Widget build(BuildContext context) {
    final score = restaurant.quietnessScore;
    return Center(
      child: Column(
        children: [
          NoiseLevelBar(quietnessScore: score),
          if (score != null) ...[
            const SizedBox(height: 10),
            ConfidenceIndicator(confidence: restaurant.confidence),
          ],
        ],
      ),
    );
  }
}

