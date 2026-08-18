// Its own page, not a dialog on top of AuthScreen — Caelan's call
// (2026-08-18), replacing the first version's showDialog approach. Opens
// with a brief skeleton placeholder before the real form appears, purely as
// a deliberate visual separation from the sign-in page Caelan asked for —
// there's no real data being fetched here, so the delay is cosmetic, not
// masking latency.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/oauth_service.dart' show oauthRedirectUrl;

const _skeletonDuration = Duration(milliseconds: 500);

class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _emailController = TextEditingController(text: widget.initialEmail);
  bool _showSkeleton = true;
  bool _submitting = false;
  String? _error;
  String? _info;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    Future.delayed(_skeletonDuration, () {
      if (mounted) setState(() => _showSkeleton = false);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// Doesn't reveal whether the address has an account — Supabase's API
  /// itself returns success regardless, so there's nothing more specific to
  /// tell the user either way.
  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your account email first.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _info = null;
    });
    try {
      await _client.auth.resetPasswordForEmail(email, redirectTo: kIsWeb ? null : oauthRedirectUrl);
      if (!mounted) return;
      setState(() => _info = 'If $email has an account, a password reset link is on its way.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not send reset link: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _showSkeleton ? const _ForgotPasswordSkeleton() : _buildForm(context),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return SingleChildScrollView(child: _buildFormColumn(context));
  }

  Widget _buildFormColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Enter your account's email and we'll send you a link to reset your password.",
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: widget.initialEmail.isEmpty,
          decoration: const InputDecoration(labelText: 'Email'),
          onSubmitted: (_) => _submitting ? null : _submit(),
        ),
        const SizedBox(height: 20),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_info != null) Text(_info!, style: const TextStyle(color: Colors.green)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Please wait…' : 'Send reset link'),
        ),
      ],
    );
  }
}

/// Placeholder shapes mirroring the real form's layout (description, email
/// field, button), pulsing to read clearly as "loading" rather than
/// finished content.
class _ForgotPasswordSkeleton extends StatefulWidget {
  const _ForgotPasswordSkeleton();

  @override
  State<_ForgotPasswordSkeleton> createState() => _ForgotPasswordSkeletonState();
}

class _ForgotPasswordSkeletonState extends State<_ForgotPasswordSkeleton>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);
  late final _opacity = Tween<double>(begin: 0.35, end: 0.8).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget block({required double width, required double height}) {
      return FadeTransition(
        opacity: _opacity,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: scheme.onSurface,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        block(width: double.infinity, height: 16),
        const SizedBox(height: 8),
        Center(child: block(width: 220, height: 16)),
        const SizedBox(height: 24),
        block(width: double.infinity, height: 56),
        const SizedBox(height: 32),
        block(width: double.infinity, height: 48),
      ],
    );
  }
}
