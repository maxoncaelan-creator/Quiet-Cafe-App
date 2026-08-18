// The restaurant detail screen's circular mic button. Purely presentational
// — the caller drives its color and whether it's pulsing; this widget only
// owns the ripple animation itself. Idle (pulsing, primary-colored) invites
// a tap; a caller stops the pulse and swaps the color to show recording or
// finished states without this widget needing to know what those mean.

import 'package:flutter/material.dart';

class PulsingMicButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool pulsing;
  final Color color;

  const PulsingMicButton({
    super.key,
    required this.onPressed,
    required this.color,
    this.pulsing = true,
  });

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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    if (widget.pulsing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant PulsingMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing != oldWidget.pulsing) {
      if (widget.pulsing) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _maxRingSize,
      height: _maxRingSize,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Staggered so a new ripple starts as the previous one is half
              // faded, instead of a dead gap with nothing rippling.
              if (widget.pulsing) _ring(_controller.value),
              if (widget.pulsing) _ring((_controller.value + 0.5) % 1.0),
              child!,
            ],
          );
        },
        child: Material(
          color: widget.color,
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onPressed,
            child: const SizedBox(
              width: _buttonSize,
              height: _buttonSize,
              child: Icon(Icons.mic, color: Colors.white, size: 40),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ring(double t) {
    final size = _buttonSize + (_maxRingSize - _buttonSize) * t;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.color.withValues(alpha: (1 - t) * 0.35),
      ),
    );
  }
}
