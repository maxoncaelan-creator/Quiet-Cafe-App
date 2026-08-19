import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/restaurant.dart';
import '../services/supabase_service.dart';
import '../widgets/confidence_indicator.dart';
import '../widgets/loudness_vote_buttons.dart';
import '../widgets/max_width_content.dart';
import '../widgets/noise_level_bar.dart';

class RestaurantDetailScreen extends StatefulWidget {
  final Restaurant restaurant;

  const RestaurantDetailScreen({super.key, required this.restaurant});

  @override
  State<RestaurantDetailScreen> createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State<RestaurantDetailScreen> {
  final _supabaseService = SupabaseService();
  Restaurant get restaurant => widget.restaurant;

  bool _isFavorite = false;
  bool _favoriteBusy = false;

  @override
  void initState() {
    super.initState();
    _loadFavoriteStatus();
  }

  Future<void> _loadFavoriteStatus() async {
    if (!_supabaseService.isSignedIn) return;
    // No dedicated "is this one favorited" check yet — fetches the whole
    // set, same as the List screen. Fine at today's scale; worth a
    // dedicated query later if a user's favorites list gets large.
    final ids = await _supabaseService.fetchFavoritePlaceIds();
    if (mounted) setState(() => _isFavorite = ids.contains(restaurant.placeId));
  }

  Future<void> _toggleFavorite() async {
    if (!_supabaseService.isSignedIn) {
      final signedIn = await context.push<bool>('/sign-in');
      if (signedIn != true || !mounted) return;
    }
    setState(() {
      _isFavorite = !_isFavorite;
      _favoriteBusy = true;
    });
    try {
      if (_isFavorite) {
        await _supabaseService.addFavorite(restaurant.placeId);
      } else {
        await _supabaseService.removeFavorite(restaurant.placeId);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFavorite = !_isFavorite); // revert on failure
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update favorite — try again.')),
      );
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  Future<void> _startReading(BuildContext context) async {
    // Browsing never requires an account — only submitting a reading does.
    // Prompt for sign-in/sign-up right here, at the point of need, rather
    // than gating the whole app behind auth.
    if (!_supabaseService.isSignedIn) {
      final signedIn = await context.push<bool>('/sign-in');
      if (signedIn != true) return; // user backed out or sign-up needs email confirmation first
    }

    if (!context.mounted) return;
    context.push('/restaurant/${restaurant.placeId}/reading', extra: restaurant.name);
  }

  /// Same point-of-need sign-in prompt as _startReading/favoriting, factored
  /// out so LoudnessVoteButtons (which doesn't know about this screen's
  /// SupabaseService instance) can reuse it.
  Future<bool> _ensureSignedIn(BuildContext context) async {
    if (_supabaseService.isSignedIn) return true;
    final signedIn = await context.push<bool>('/sign-in');
    return signedIn == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(restaurant.name),
        actions: [
          if (SupabaseService.isConfigured)
            IconButton(
              icon: Icon(
                _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: _isFavorite ? Colors.amber.shade700 : null,
              ),
              onPressed: _favoriteBusy ? null : _toggleFavorite,
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
          LoudnessVoteButtons(placeId: restaurant.placeId, ensureSignedIn: _ensureSignedIn),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.mic),
            label: const Text('Take a reading here'),
            onPressed: () => _startReading(context),
          ),
        ],
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

