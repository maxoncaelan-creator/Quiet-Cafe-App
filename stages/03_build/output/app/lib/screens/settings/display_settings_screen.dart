import 'package:flutter/material.dart';

import '../../services/theme_service.dart';

class DisplaySettingsScreen extends StatelessWidget {
  const DisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display')),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeService.mode,
        builder: (context, mode, _) {
          return SwitchListTile(
            title: const Text('Dark mode'),
            subtitle: const Text('Uses the same teal palette, generated for dark surfaces'),
            value: mode == ThemeMode.dark,
            onChanged: (enabled) => ThemeService.setDarkMode(enabled),
          );
        },
      ),
    );
  }
}
