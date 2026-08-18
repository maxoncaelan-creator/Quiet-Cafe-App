// The actual email field, split out of CreateAccountScreen (2026-08-18) so
// that screen can be a pure chooser (Google/Facebook buttons + a "Sign up
// with email" button) matching the cal.com reference Caelan gave.
// Continuing pushes CreateAccountPasswordScreen, where the password is
// actually set (and confirmed).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/centered_scroll_form.dart';

class CreateAccountEmailScreen extends StatefulWidget {
  /// Threaded through from AuthScreen via CreateAccountScreen — see
  /// create_account_screen.dart's doc comment. Fired from
  /// CreateAccountPasswordScreen if the account needs email confirmation.
  final ValueChanged<String> onPendingConfirmation;

  const CreateAccountEmailScreen({super.key, required this.onPendingConfirmation});

  @override
  State<CreateAccountEmailScreen> createState() => _CreateAccountEmailScreenState();
}

class _CreateAccountEmailScreenState extends State<CreateAccountEmailScreen> {
  final _emailController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// Only checks for an "@" — not full RFC validation, since Supabase
  /// itself is the real authority on whether an address is usable and will
  /// reject it on the next screen if not. This just catches an obviously
  /// empty or malformed entry before making the user set a password for it.
  Future<void> _continue() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });

    final result = await context.push<bool>(
      '/sign-up/password',
      extra: (email: email, onPendingConfirmation: widget.onPendingConfirmation),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result != null) context.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: CenteredScrollForm(
          children: [
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Email'),
                onSubmitted: (_) => _submitting ? null : _continue(),
              ),
              const SizedBox(height: 20),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submitting ? null : _continue,
                child: Text(_submitting ? 'Please wait…' : 'Continue'),
              ),
          ],
        ),
      ),
    );
  }
}
