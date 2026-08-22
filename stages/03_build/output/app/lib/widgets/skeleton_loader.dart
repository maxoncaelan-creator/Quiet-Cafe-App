import 'package:flutter/material.dart';

/// A lightweight content-shaped placeholder used while a screen fetches data.
/// It intentionally stays still: a loading state should not be mistaken for a
/// progress control or compete with the content that is about to appear.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: borderRadius,
      ),
    );
  }
}

/// Generic card-shaped page placeholder for list and detail loading states.
class PageSkeleton extends StatelessWidget {
  final int itemCount;

  const PageSkeleton({super.key, this.itemCount = 4});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const _SkeletonCard(),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 180, height: 18),
            SizedBox(height: 12),
            SkeletonBox(width: 120, height: 14),
            SizedBox(height: 20),
            SkeletonBox(width: double.infinity, height: 36),
          ],
        ),
      ),
    );
  }
}
