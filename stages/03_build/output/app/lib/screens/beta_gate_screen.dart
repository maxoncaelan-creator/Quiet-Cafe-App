// Shown before anything else in the app until a valid referral code is
// redeemed — the closed-beta gate Caelan asked for 2026-08-20. Everything
// else in the app (browsing included) sits behind this; there is no way
// past it without a code emailed after Caelan approves a request made on
// the marketing site. See build-log.md "Referral-code gate."
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/beta_gate_service.dart';
import '../services/supabase_service.dart';

class BetaGateScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const BetaGateScreen({super.key, required this.onUnlocked});

  @override
  State<BetaGateScreen> createState() => _BetaGateScreenState();
}

class _BetaGateScreenState extends State<BetaGateScreen> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final deviceId = await BetaGateService.deviceId();
    final result = await SupabaseService().redeemBetaCode(code, deviceId);
    if (!mounted) return;

    if (result == BetaCodeResult.ok) {
      await BetaGateService.markUnlocked();
      widget.onUnlocked();
      return;
    }

    setState(() {
      _submitting = false;
      _error = switch (result) {
        BetaCodeResult.expired => 'That code has expired. Request a new one on our website.',
        BetaCodeResult.alreadyRedeemed => 'That code has already been used.',
        BetaCodeResult.invalid => "That code isn't valid. Check it and try again.",
        BetaCodeResult.ok => null, // unreachable, handled above
        BetaCodeResult.error => 'Something went wrong. Try again in a moment.',
      };
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Closed beta', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text(
                    "You'll need a referral code to get in. Enter it below, or "
                    'request access on our website.',
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.characters,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Referral code',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: Text(_submitting ? 'Checking…' : 'Unlock'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse('https://cafequiet.com')),
                    child: const Text('Request access'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
