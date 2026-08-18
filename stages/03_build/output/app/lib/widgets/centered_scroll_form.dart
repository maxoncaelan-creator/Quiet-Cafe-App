// Shared by every auth screen's body. Plain SingleChildScrollView content
// sits at the top of the screen once wrapped in scroll — mainAxisAlignment
// does nothing there, since the Column just sizes to its content. This
// gives the same scroll-to-avoid-the-keyboard behavior (see the overflow
// fix, 2026-08-18) while still vertically centering the form when there's
// slack — the LayoutBuilder reports the actual available viewport height
// (already keyboard-shrunk by the Scaffold), so the ConstrainedBox only
// forces centering when the content doesn't need the full height, and
// content that does overflow it still scrolls normally.
import 'package:flutter/material.dart';

class CenteredScrollForm extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;

  const CenteredScrollForm({super.key, required this.children, this.padding = const EdgeInsets.all(24)});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - padding.vertical),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        );
      },
    );
  }
}
