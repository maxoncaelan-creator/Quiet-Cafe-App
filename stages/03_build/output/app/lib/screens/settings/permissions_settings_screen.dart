// Both toggles reflect the real OS permission status via permission_handler
// (already a dependency — same package the noise-reading flow uses). An OS
// permission can't be revoked from inside the app once granted, only from
// system settings, so a granted toggle opens system settings rather than
// pretending to flip it off. Notifications has nothing to send yet (see
// ui-design-decisions.md) — the toggle still controls the real OS
// permission, ahead of that infrastructure existing.

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsSettingsScreen extends StatefulWidget {
  const PermissionsSettingsScreen({super.key});

  @override
  State<PermissionsSettingsScreen> createState() => _PermissionsSettingsScreenState();
}

class _PermissionsSettingsScreenState extends State<PermissionsSettingsScreen> with WidgetsBindingObserver {
  PermissionStatus? _micStatus;
  PermissionStatus? _notificationStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches a permission changed in system settings while the app was backgrounded.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final mic = await Permission.microphone.status;
    final notif = await Permission.notification.status;
    if (mounted) {
      setState(() {
        _micStatus = mic;
        _notificationStatus = notif;
      });
    }
  }

  Future<void> _handleToggle(Permission permission, bool requestEnable) async {
    final current = await permission.status;
    if (requestEnable) {
      if (current.isPermanentlyDenied) {
        await openAppSettings();
      } else {
        await permission.request();
      }
    } else {
      // Can't programmatically revoke — only the OS settings screen can.
      await openAppSettings();
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Notifications'),
            subtitle: const Text('Alerts about your submitted readings and new quiet spots nearby'),
            value: _notificationStatus?.isGranted ?? false,
            onChanged: _notificationStatus == null
                ? null
                : (v) => _handleToggle(Permission.notification, v),
          ),
          SwitchListTile(
            title: const Text('Microphone'),
            subtitle: const Text('Required to take a noise reading — off disables that feature only'),
            value: _micStatus?.isGranted ?? false,
            onChanged: _micStatus == null ? null : (v) => _handleToggle(Permission.microphone, v),
          ),
        ],
      ),
    );
  }
}
