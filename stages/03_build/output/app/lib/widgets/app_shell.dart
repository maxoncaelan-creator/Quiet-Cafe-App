// The router's root ShellRoute builder — wraps every screen, not just the
// nav-bearing ones, so the persistent rail shows up everywhere on wide
// layouts (Caelan's call: a real shell, not a per-screen patch). On narrow
// layouts this is a no-op passthrough — each screen keeps managing its own
// Scaffold/Drawer exactly as before, so mobile/native visuals are unchanged.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/breakpoints.dart';
import 'app_nav_destinations.dart';
import 'app_nav_rail.dart';

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!isWideLayout(context)) return child;

    final location = GoRouterState.of(context).uri.toString();
    final currentRoute = appRouteForLocation(location);

    return Row(
      children: [
        AppNavRail(currentRoute: currentRoute),
        const VerticalDivider(width: 1),
        Expanded(child: child),
      ],
    );
  }
}
