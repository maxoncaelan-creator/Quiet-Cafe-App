// Shown when the app detects AuthChangeEvent.passwordRecovery (see
// main.dart) — i.e. the user tapped the "reset your password" link from
// _forgotPassword() in auth_screen.dart and Supabase has already exchanged
// it for a temporary recovery session. That session is enough on its own
// to call updateUser with a new password; the old password is never asked
// for or checked here, which is how Supabase's recovery flow is designed
// to work (the emailed link itself is the proof of ownership).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/supabase_service.dart';
import '../utils/friendly_auth_error.dart';
import '../widgets/centered_scroll_form.dart';
import '../widgets/password_field.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _supabaseService = SupabaseService();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;
  String? _error;

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
      await _supabaseService.updatePassword(password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated. You can sign in with it from now on.')),
      );
      // Equivalent of "pop to the root of the stack" under go_router — this
      // screen is reached from a global deep-link push (main.dart), not
      // user navigation, so there's no meaningful "back" to return to.
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyPasswordPolicyError(e) ?? 'Could not update password: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password'), automaticallyImplyLeading: false),
      body: CenteredScrollForm(
        children: [
            const Text('Choose a new password for your account.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            PasswordField(
              controller: _passwordController,
              labelText: 'New password',
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _confirmController,
              labelText: 'Confirm new password',
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
              child: Text(_submitting ? 'Please wait…' : 'Save new password'),
            ),
        ],
      ),
    );
  }
}
