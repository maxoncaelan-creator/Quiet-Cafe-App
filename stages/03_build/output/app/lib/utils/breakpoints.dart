import 'package:flutter/material.dart';

/// Material 3's "medium" window-class cutoff — above this, the app shows a
/// persistent NavigationRail instead of each screen's own Drawer.
const double kWideLayoutBreakpoint = 840;

bool isWideLayout(BuildContext context) => MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;
