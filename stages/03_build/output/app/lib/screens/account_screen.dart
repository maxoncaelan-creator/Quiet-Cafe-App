// Real account management — added 2026-08-18. Replaces a real bug found
// live: the drawer's "Account" item (shown once signed in) still navigated
// to AuthScreen, the sign-in form, instead of anywhere a signed-in user
// could actually manage anything. Account now lives under Settings and is
// scoped to what the app genuinely stores about a user — Supabase Auth's
// email and their own submitted mic readings — not invented profile fields
// this app has no data for.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/mic_reading.dart';
import '../services/observability_service.dart';
import '../services/supabase_service.dart';
import '../widgets/max_width_content.dart';
import '../widgets/skeleton_loader.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _supabaseService = SupabaseService();
  List<MyReading>? _readings;
  Object? _readingsError;

  @override
  void initState() {
    super.initState();
    _loadReadings();
  }

  Future<void> _loadReadings() async {
    try {
      final readings = await _supabaseService.fetchMyReadings();
      if (mounted) setState(() => _readings = readings);
    } catch (e, st) {
      unawaited(ObservabilityService.captureError(e, st,
          context: 'account.fetch_readings'));
      if (mounted) setState(() => _readingsError = e);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
            "You'll need to sign in again to submit readings or manage favourites."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _supabaseService.signOut();
    if (mounted) context.pop();
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final email = _supabaseService.currentUserEmail ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: MaxWidthContent(
        child: ListView(
          children: [
            const _SectionHeader('Personal details'),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Email'),
              subtitle: Text(email),
            ),
            const Divider(height: 32),
            const _SectionHeader('Your activity'),
            _ActivitySection(
                readings: _readings,
                error: _readingsError,
                formatDate: _formatDate),
            const Divider(height: 32),
            ListTile(
              leading: Icon(Icons.logout, color: scheme.error),
              title: Text('Log out', style: TextStyle(color: scheme.error)),
              onTap: _confirmLogout,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  final List<MyReading>? readings;
  final Object? error;
  final String Function(DateTime) formatDate;

  const _ActivitySection(
      {required this.readings, required this.error, required this.formatDate});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (error != null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('Could not load your reading history.'),
      );
    }
    if (readings == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: SkeletonBox(width: double.infinity, height: 72),
      );
    }
    if (readings!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          "You haven't submitted any noise readings yet.",
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      children: [
        for (final reading in readings!)
          ListTile(
            leading: const Icon(Icons.mic_none),
            title: Text(reading.restaurantName),
            subtitle: Text(
                '${reading.decibelValue.round()} dB · ${formatDate(reading.recordedAt)}'),
          ),
      ],
    );
  }
}
