import 'package:flutter/material.dart';

import '../models/restaurant.dart';
import '../services/supabase_service.dart';
import 'auth_screen.dart';
import 'take_reading_screen.dart';

class RestaurantDetailScreen extends StatelessWidget {
  final Restaurant restaurant;

  const RestaurantDetailScreen({super.key, required this.restaurant});

  Future<void> _startReading(BuildContext context) async {
    final supabaseService = SupabaseService();

    // Browsing never requires an account — only submitting a reading does.
    // Prompt for sign-in/sign-up right here, at the point of need, rather
    // than gating the whole app behind auth.
    if (!supabaseService.isSignedIn) {
      final signedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      if (signedIn != true) return; // user backed out or sign-up needs email confirmation first
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TakeReadingScreen(placeId: restaurant.placeId, name: restaurant.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(restaurant.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (restaurant.address != null) Text(restaurant.address!),
          const SizedBox(height: 16),
          _ScoreHeader(restaurant: restaurant),
          const SizedBox(height: 24),
          const Text('Score breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          _SignalRow(
            label: 'Microphone readings',
            subscore: restaurant.mic.subscore,
            detail: '${restaurant.mic.totalReadings} reading(s) '
                '(${restaurant.mic.readingCountIos} iOS, ${restaurant.mic.readingCountAndroid} Android)',
          ),
          _SignalRow(
            label: 'Review mentions',
            subscore: restaurant.review.subscore,
            detail: restaurant.review.subscore == null
                ? 'Not enough review mentions yet'
                : null,
          ),
          _SignalRow(
            label: 'Popular times',
            subscore: restaurant.popular.subscore,
            detail: restaurant.popular.subscore == null ? 'No busyness data yet' : null,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.mic),
            label: const Text('Take a reading here'),
            onPressed: () => _startReading(context),
          ),
        ],
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
    if (score == null) {
      return const Text('Not enough data yet', style: TextStyle(fontSize: 20));
    }
    return Row(
      children: [
        Text(score.round().toString(), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
        const SizedBox(width: 12),
        Text('Confidence: ${restaurant.confidence ?? 'low'}'),
      ],
    );
  }
}

class _SignalRow extends StatelessWidget {
  final String label;
  final num? subscore;
  final String? detail;

  const _SignalRow({required this.label, required this.subscore, this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                if (detail != null)
                  Text(detail!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(subscore == null ? '—' : subscore!.round().toString()),
        ],
      ),
    );
  }
}
