// Deliberately styled to stand out from the other sign-in options, per
// Caelan (2026-08-18) — reference was cal.com's solid black "Sign up with
// Google" button. Literal color match rather than deriving from the app's
// teal theme, since the whole point is contrast against the Apple/Facebook/
// email buttons on the same screen. Uses Google's actual four-color "G"
// mark (assets/icons/google_logo.svg), not a generic Material icon.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class GoogleSignInButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const GoogleSignInButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF131314),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      icon: SvgPicture.asset('assets/icons/google_logo.svg', width: 20, height: 20),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      onPressed: onPressed,
    );
  }
}
