// Step 2 of creating an account (see create_account_screen.dart) — set a
// password and type it again to confirm, then actually call
// Supabase's signUp. Kept as its own screen rather than folded back into
// CreateAccountScreen so the email step stays a single field, per Caelan.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/oauth_service.dart';
import '../widgets/centered_scroll_form.dart';

class CreateAccountPasswordScreen extends StatefulWidget {
  final String email;
  final ValueChanged<String> onPendingConfirmation;

  const CreateAccountPasswordScreen({super.key, required this.email, required this.onPendingConfirmation});

  @override
  State<CreateAccountPasswordScreen> createState() => _CreateAccountPasswordScreenState();
}

class _CreateAccountPasswordScreenState extends State<CreateAccountPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;
  String? _error;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (password != _confirmController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final response = await _client.auth.signUp(
        email: widget.email,
        password: password,
        // Routes the confirmation link back into the app via the same
        // redirect used for OAuth, instead of Supabase's generic hosted
        // confirmation page. Ignored on web, where there's no app to
        // redirect back into.
        emailRedirectTo: kIsWeb ? null : oauthRedirectUrl,
      );
      if (!mounted) return;
      // Supabase requires email confirmation by default — signUp does not
      // return an active session in that case. Don't assume success means
      // "signed in"; tell CreateAccountScreen/AuthScreen what actually
      // needs to happen next rather than popping as if signed in.
      if (response.session == null) {
        widget.onPendingConfirmation('Check ${widget.email} for a confirmation link, then sign in.');
        Navigator.of(context).pop(false);
      } else {
        Navigator.of(context).pop(true);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set a password')),
      body: SafeArea(
        child: CenteredScrollForm(
          children: [
              Text('Choose a password for ${widget.email}.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextField(
                controller: _passwordController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm password'),
                onSubmitted: (_) => _submitting ? null : _submit(),
              ),
              const SizedBox(height: 20),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting ? 'Please wait…' : 'Create account'),
              ),
          ],
        ),
      ),
    );
  }
}
