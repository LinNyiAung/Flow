import 'package:flutter/material.dart';

/// The filled "Save" pill at the right of the New entry / Edit transaction
/// top bars. Shows a spinner (and ignores taps) while [saving].
class AppBarSaveButton extends StatelessWidget {
  const AppBarSaveButton({
    super.key,
    required this.label,
    required this.saving,
    required this.onPressed,
  });

  final String label;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 12),
      child: Center(
        child: Semantics(
          button: true,
          enabled: !saving,
          child: GestureDetector(
            onTap: saving ? null : onPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: saving ? scheme.outline : scheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
