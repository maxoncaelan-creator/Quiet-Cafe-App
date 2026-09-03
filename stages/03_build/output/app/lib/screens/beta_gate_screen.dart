// Shown to a signed-in account that hasn't redeemed a beta code yet —
// reached only after sign-in now (router.dart's redirect enforces that
// ordering), per Caelan's 2026-08-21 correction: codes attach to the
// account, not the device, so this screen's only job is asking for a code
// and telling betaAccessProvider to recheck once one redeems successfully.
// See 0015_beta_code_account_binding.sql for why this replaced the earlier
// device-bound version — that one locked Caelan himself out on a second
// browser using his own real code.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/beta_gate_provider.dart';
import '../providers/supabase_service_provider.dart';
import '../services/supabase_service.dart';

class BetaGateScreen extends ConsumerStatefulWidget {
  const BetaGateScreen({super.key});

  @override
  ConsumerState<BetaGateScreen> createState() => _BetaGateScreenState();
}

class _BetaGateScreenState extends ConsumerState<BetaGateScreen> {
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

    final result =
        await ref.read(supabaseServiceProvider).redeemBetaCode(code);
    if (!mounted) return;

    if (result == BetaCodeResult.ok) {
      // Invalidating goes through AsyncNotifier's normal rebuild path
      // rather than a bespoke reload()/refresh() method — that's what
      // safely cancels a still-in-flight check instead of leaving it to
      // race the new one (see beta_gate_provider.dart). router.dart's
      // refreshListenable (beta_gate_router_refresh.dart) reacts to the
      // resulting state change on its own, so nothing here navigates
      // manually.
      ref.invalidate(betaAccessProvider);
      await ref.read(betaAccessProvider.future);
      return;
    }

    setState(() {
      _submitting = false;
      _error = switch (result) {
        BetaCodeResult.expired => 'That code has expired. Request a new one on our website.',
        BetaCodeResult.alreadyRedeemed => 'That code has already been used by another account.',
        BetaCodeResult.invalid => "That code isn't valid. Check it and try again.",
        BetaCodeResult.ok => null, // unreachable, handled above
        BetaCodeResult.error => 'Something went wrong. Try again in a moment.',
      };
    });
  }

  Future<void> _signOut() async {
    await ref.read(supabaseServiceProvider).signOut();
    // authStateChanges fires from this, which betaAccessProvider already
    // listens to and rebuilds from — the redirect sends them to /sign-in
    // on its own once hasAccess resets.
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserEmail = ref.read(supabaseServiceProvider).currentUserEmail;
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
                  Text(
                    "You're signed in as ${currentUserEmail ?? 'this account'}, "
                    "but it doesn't have beta access yet. Enter a referral code below, or "
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
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: _submitting ? null : _signOut,
                    child: const Text('Not you? Sign out'),
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
