import 'package:flutter/material.dart';
import 'package:frontend/providers/app_control_provider.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:frontend/utils/date_format.dart';
import 'package:frontend/utils/date_locale.dart';
import 'package:provider/provider.dart';

/// Full-screen block shown while the owner has maintenance on and this person
/// may not get in. Shows the owner's message (as given), when it should be
/// over (in the person's own time zone), a Retry button that reads the config
/// again, and, when signed out, a small "Sign in" link so a tester can get in.
class MaintenanceScreen extends StatelessWidget {
  /// Opens the sign-in screen; null (no link) when somebody is signed in.
  final VoidCallback? onSignIn;

  const MaintenanceScreen({super.key, this.onSignIn});

  @override
  Widget build(BuildContext context) {
    final control = context.watch<AppControlProvider>();
    final config = control.config;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strings = AppLocalizations.of(context);
    final backBy = config.backBy;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(Icons.build_circle_outlined, size: 48, color: scheme.primary),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    strings.maintenanceTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    config.maintenanceMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                  if (backBy != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      strings.maintenanceBackBy(
                        AppDates.dateTimeIn(backBy.toLocal(), locale: dateLocaleOf(context)),
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: control.isLoading ? null : control.refresh,
                      child: control.isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : Text(strings.maintenanceRetry),
                    ),
                  ),
                  if (onSignIn != null) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: onSignIn,
                      child: Text(strings.maintenanceSignIn),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
