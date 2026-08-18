// The restaurant detail screen's call to action to take a reading — a
// circular mic button with two staggered ripple rings that continuously
// expand and fade, like sound (or a raindrop) spreading outward. Purely
// decorative animation; the tap target is the solid circle itself.

import 'package:flutter/material.dart';

class PulsingMicButton extends StatefulWidget {
  final VoidCallback onPressed;

  const PulsingMicButton({super.key, required this.onPressed});

  @override
  State<PulsingMicButton> createState() => _PulsingMicButtonState();
}

class _PulsingMicButtonState extends State<PulsingMicButton> with SingleTickerProviderStateMixin {
  static const _buttonSize = 88.0;
  static const _maxRingSize = 168.0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: _maxRingSize,
      height: _maxRingSize,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              _ring(scheme, _controller.value),
              // Second ring offset half a cycle behind the first, so a new
              // ripple starts as the previous one is half faded — otherwise
              // there'd be a dead gap with nothing rippling.
              _ring(scheme, (_controller.value + 0.5) % 1.0),
              child!,
            ],
          );
        },
        child: Material(
          color: scheme.primary,
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onPressed,
            child: SizedBox(
              width: _buttonSize,
              height: _buttonSize,
              child: Icon(Icons.mic, color: scheme.onPrimary, size: 40),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ring(ColorScheme scheme, double t) {
    final size = _buttonSize + (_maxRingSize - _buttonSize) * t;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primary.withValues(alpha: (1 - t) * 0.35),
      ),
    );
  }
}
