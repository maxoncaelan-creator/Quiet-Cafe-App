// Replaces an inline email (and, for sign-in, password) field on the
// chooser screen — tapping this navigates to a dedicated page for actually
// typing it in. Styled after cal.com's "Sign up with email >" secondary
// button, per Caelan (2026-08-18).

import 'package:flutter/material.dart';

class EmailOptionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const EmailOptionButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
  }
}
