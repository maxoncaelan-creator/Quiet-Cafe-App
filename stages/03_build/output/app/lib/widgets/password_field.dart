// Shared by every password field in the app (sign-in, create-account,
// change-password, reset-password) — an eye icon toggling obscureText, per
// Caelan (2026-08-18). Its own tiny StatefulWidget rather than each screen
// managing an obscured/visible bool itself, since every screen needs the
// exact same toggle behavior.

import 'package:flutter/material.dart';

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  const PasswordField({
    super.key,
    required this.controller,
    required this.labelText,
    this.autofocus = false,
    this.onSubmitted,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscured,
      autofocus: widget.autofocus,
      decoration: InputDecoration(
        labelText: widget.labelText,
        suffixIcon: IconButton(
          icon: Icon(_obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          tooltip: _obscured ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      ),
      onSubmitted: widget.onSubmitted,
    );
  }
}
