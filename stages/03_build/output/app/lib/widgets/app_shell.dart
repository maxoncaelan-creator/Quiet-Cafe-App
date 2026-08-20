// The router's root ShellRoute builder. Used to also show a persistent
// NavigationRail on wide layouts alongside each screen's own hamburger
// Drawer — that duplicated the same destinations in two places at once on
// desktop (Caelan, 2026-08-20). Each screen already manages its own
// Scaffold/Drawer, so the single hamburger menu is the only nav surface now,
// at every width.
import 'package:flutter/material.dart';

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
