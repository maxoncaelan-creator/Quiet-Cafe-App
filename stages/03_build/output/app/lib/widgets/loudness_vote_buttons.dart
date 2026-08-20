// Three-way "Quiet / Normal / Loud" vote — a lighter-weight alternative to
// a mic reading, added 2026-08-19 per Caelan, replacing the detail
// screen's old "Score breakdown" section. Feeds the same quietness score
// in the data pipeline (scoring.js's voteSubscore); a decibel reading from
// the same account within 5 minutes of a vote takes precedence there, but
// the vote itself is always recorded regardless — see
// filterVotesSupersededByMic and supabase/migrations/0008_loudness_votes.sql.
//
// Ported from feature/loudness-votes-and-venue-guess (2026-08-18), which
// built this but never got merged — the backend (migration, scoring) was
// already live; only this widget and its wiring were missing.
//
// onVoted added 2026-08-20: SupabaseService.submitLoudnessVote now
// recomputes the venue's score server-side, but this widget has no
// Restaurant object of its own to update — the parent screen owns that, so
// it refetches and updates its state once this callback fires. Before this,
// a vote landed correctly in loudness_votes but the visible score/
// confidence on screen never changed, which is what Caelan reported.

import 'package:flutter/material.dart';

import '../services/supabase_service.dart';

class LoudnessVoteButtons extends StatefulWidget {
  final String placeId;

  /// Same sign-in gate MicReadingControl/detail-screen actions use — voting
  /// needs a real account so the pipeline can tell whose vote this is (and
  /// whether a mic reading from that same account supersedes it).
  final Future<bool> Function(BuildContext context) ensureSignedIn;

  /// Called after a vote is successfully recorded (and the server-side
  /// score recompute has been kicked off) — see file header comment.
  final VoidCallback onVoted;

  const LoudnessVoteButtons({
    super.key,
    required this.placeId,
    required this.ensureSignedIn,
    required this.onVoted,
  });

  @override
  State<LoudnessVoteButtons> createState() => _LoudnessVoteButtonsState();
}

class _LoudnessVoteButtonsState extends State<LoudnessVoteButtons> {
  final _supabaseService = SupabaseService();
  bool _submitting = false;

  Future<void> _vote(String vote) async {
    if (_submitting) return;

    final signedIn = await widget.ensureSignedIn(context);
    if (!signedIn || !mounted) return;

    setState(() => _submitting = true);
    try {
      await _supabaseService.submitLoudnessVote(widget.placeId, vote);
      if (!mounted) return;
      widget.onVoted();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for your vote!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not record your vote: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('How loud is this venue?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            _VoteButton(
              label: 'Quiet',
              icon: Icons.volume_down_rounded,
              onPressed: _submitting ? null : () => _vote('quiet'),
            ),
            const SizedBox(width: 8),
            _VoteButton(
              label: 'Normal',
              icon: Icons.volume_up_rounded,
              onPressed: _submitting ? null : () => _vote('normal'),
            ),
            const SizedBox(width: 8),
            _VoteButton(
              label: 'Loud',
              icon: Icons.campaign_rounded,
              onPressed: _submitting ? null : () => _vote('loud'),
            ),
          ],
        ),
      ],
    );
  }
}

class _VoteButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _VoteButton({required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}
