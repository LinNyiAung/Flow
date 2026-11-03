import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/services/localization_service.dart';

import 'voice_extraction.dart';

/// "Your recording was already read, so trying again does not use another
/// entry." Shown only while that is true, that is while the voice token of
/// [extraction] is still valid.
///
/// It decides when it is built and again when the token expires (a timer
/// rebuilds it then), so a screen left open on a failed extraction stops
/// making the promise once the token has run out.
class VoiceRetryHint extends StatefulWidget {
  const VoiceRetryHint({super.key, required this.extraction, this.clock = DateTime.now});

  final VoiceExtraction extraction;

  /// The current time; only tests pass it.
  final DateTime Function() clock;

  @override
  State<VoiceRetryHint> createState() => _VoiceRetryHintState();
}

class _VoiceRetryHintState extends State<VoiceRetryHint> {
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _armTimer();
  }

  @override
  void didUpdateWidget(VoiceRetryHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.extraction, widget.extraction)) _armTimer();
  }

  /// One shot, to just after the token's expiry. A timer that fires a touch
  /// early finds the token still valid and arms again.
  void _armTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final now = widget.clock();
    final expiry = VoiceExtraction.tokenExpiry(widget.extraction.voiceToken);
    if (expiry == null || !widget.extraction.retryIsFree(now: now)) return;
    _expiryTimer = Timer(expiry.difference(now) + const Duration(milliseconds: 50), () {
      if (!mounted) return;
      setState(() {});
      _armTimer();
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.extraction.retryIsFree(now: widget.clock())) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        AppLocalizations.of(context).voiceRetryHint,
        key: const ValueKey('voice-retry-hint'),
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}
