// Keeps pushed screens (restaurant detail, take-a-reading, account,
// settings sub-screens) from stretching edge-to-edge inside the AppShell's
// wide Expanded slot. Auth-flow screens use CenteredScrollForm's own
// maxWidth instead — this one's for everything else.
import 'package:flutter/material.dart';

class MaxWidthContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const MaxWidthContent({super.key, required this.child, this.maxWidth = 640});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
