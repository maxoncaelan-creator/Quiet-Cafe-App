// Shared row: name, Google rating, cuisine/suburb, quietness gauge, and the
// favorite star. Used by both the List and Favourites screens so the two
// stay visually identical rather than drifting into two near-copies.

import 'package:flutter/material.dart';

import '../models/restaurant.dart';
import '../screens/restaurant_detail_screen.dart';
import 'confidence_indicator.dart';
import 'noise_level_bar.dart';

class RestaurantTile extends StatelessWidget {
  final Restaurant restaurant;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const RestaurantTile({
    super.key,
    required this.restaurant,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final rating = restaurant.googleRating;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurant: restaurant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(restaurant.name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  if (rating != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, size: 15, color: Colors.amber.shade700),
                        const SizedBox(width: 4),
                        Text(rating.toStringAsFixed(1), style: Theme.of(context).textTheme.bodySmall),
                      ],
                    )
                  else
                    Text(
                      'New listing · no rating yet',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                    ),
                  Text(
                    [restaurant.cuisine, restaurant.suburb].whereType<String>().join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NoiseLevelBar(quietnessScore: restaurant.quietnessScore, compact: true),
                if (restaurant.confidence != null) ...[
                  const SizedBox(height: 4),
                  ConfidenceIndicator(confidence: restaurant.confidence, showLabel: false, dotSize: 4),
                ],
              ],
            ),
            IconButton(
              icon: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: isFavorite ? Colors.amber.shade700 : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              onPressed: onToggleFavorite,
            ),
          ],
        ),
      ),
    );
  }
}
