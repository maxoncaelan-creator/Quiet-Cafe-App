// Its own page, not a dialog — Caelan's call (2026-08-18), replacing the
// original showDialog approach in account_screen.dart. Asks for the
// current password too, not just the new one: Supabase's updateUser()
// doesn't check the existing password on its own (it works off the current
// session), so this screen re-verifies it explicitly first via a real
// sign-in call — otherwise anyone with the device unlocked and this app
// already signed in could change the password without knowing it.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/observability_service.dart';
import '../services/supabase_service.dart';
import '../utils/friendly_auth_error.dart';
import '../widgets/centered_scroll_form.dart';
import '../widgets/password_field.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _supabaseService = SupabaseService();
  bool _submitting = false;
  String? _error;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    if (currentPassword.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (newPassword.length < 6) {
      setState(() => _error = 'New password must be at least 6 characters.');
      return;
    }

    final email = _supabaseService.currentUserEmail;
    if (email == null) {
      // Not reachable in practice — this screen is only ever opened from
      // AccountScreen, itself only reachable while signed in.
      setState(() => _error = 'No signed-in account.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // Re-verify the current password via a real sign-in — see the file
      // header. A wrong current password fails right here, before touching
      // the actual new-password update.
      await _client.auth.signInWithPassword(email: email, password: currentPassword);
    } on AuthException {
      // Wrong current password — the person re-entering it incorrectly, not
      // a bug.
      if (mounted) setState(() => _error = 'Current password is incorrect.');
      if (mounted) setState(() => _submitting = false);
      return;
    } catch (e, st) {
      // Not Supabase's own auth-rejection type, so this is a genuine failure
      // (network, unexpected error) verifying the password, not a wrong one.
      await ObservabilityService.captureError(e, st,
          context: 'change_password.verify_current');
      if (mounted) setState(() => _error = 'Could not verify current password: $e');
      if (mounted) setState(() => _submitting = false);
      return;
    }

    try {
      await _supabaseService.updatePassword(newPassword);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated.')));
      context.pop();
    } catch (e, st) {
      // AuthException here is Supabase's own password-policy rejection
      // (friendlyPasswordPolicyError's case) or a similar business-rule
      // response — expected. Anything else is not.
      if (e is! AuthException) {
        await ObservabilityService.captureError(e, st,
            context: 'change_password.update');
      }
      if (!mounted) return;
      setState(() => _error = friendlyPasswordPolicyError(e) ?? 'Could not update password: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: CenteredScrollForm(
          children: [
            PasswordField(
              controller: _currentPasswordController,
              labelText: 'Current password',
              autofocus: true,
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _newPasswordController,
              labelText: 'New password',
              onSubmitted: (_) => _submitting ? null : _submit(),
            ),
            const SizedBox(height: 8),
            Text(
              'Must include an uppercase letter, a lowercase letter, a number, and a symbol.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Please wait…' : 'Change password'),
            ),
          ],
        ),
      ),
    );
  }
}
