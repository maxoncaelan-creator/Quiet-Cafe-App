// UI only for now — v1 is hardcoded to Sydney, NSW per the PRD, and
// nothing in the app does proximity filtering yet, so the GPS toggle has
// no real geo query behind it. See ui-design-decisions.md.

import 'package:flutter/material.dart';

import '../../widgets/max_width_content.dart';

class LocationSettingsScreen extends StatefulWidget {
  const LocationSettingsScreen({super.key});

  @override
  State<LocationSettingsScreen> createState() => _LocationSettingsScreenState();
}

class _LocationSettingsScreenState extends State<LocationSettingsScreen> {
  bool _useGps = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Location')),
      body: MaxWidthContent(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('City', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: InputDecorator(
                decoration: InputDecoration(border: OutlineInputBorder()),
                child: Text('Sydney, NSW'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'v1 only supports Sydney, NSW — more cities are on the roadmap.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            SwitchListTile(
              title: const Text('Use GPS'),
              subtitle: const Text("Automatically detect which suburb you're in"),
              value: _useGps,
              onChanged: (v) => setState(() => _useGps = v),
            ),
          ],
        ),
      ),
    );
  }
}
