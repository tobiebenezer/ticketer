import 'dart:async';
import 'package:flutter/material.dart';
import 'package:myapp/core/services/app_settings_service.dart';
import 'package:myapp/core/services/offline_validation_service.dart';
import 'package:myapp/core/services/validation_sound_service.dart';

/// A lightweight, non-blocking validation result overlay
///
/// Shows validation results inline without navigating away from the scanner.
/// - Auto-dismisses after configured timeout (from settings)
/// - Shows "Scan Another" button for all results
/// - Displays countdown timer
/// - Designed for rapid scanning workflows
///
/// Usage:
/// ```dart
/// showValidationOverlay(
///   context: context,
///   result: validationResult,
///   onDismiss: () { /* resume scanning */ },
/// );
/// ```

/// Displays a validation result overlay that auto-dismisses after configured timeout
void showValidationOverlay({
  required BuildContext context,
  required ValidationResult result,
  required VoidCallback onDismiss,
}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (context) => ValidationResultOverlay(
      result: result,
      onDismiss: () {
        Navigator.of(context).pop();
        onDismiss();
      },
    ),
  );
}

/// Non-blocking validation result overlay widget
class ValidationResultOverlay extends StatefulWidget {
  final ValidationResult result;
  final VoidCallback onDismiss;

  const ValidationResultOverlay({
    super.key,
    required this.result,
    required this.onDismiss,
  });

  @override
  State<ValidationResultOverlay> createState() =>
      _ValidationResultOverlayState();
}

class _ValidationResultOverlayState extends State<ValidationResultOverlay>
    with SingleTickerProviderStateMixin {
  final AppSettingsService _settingsService = AppSettingsService();
  final ValidationSoundService _soundService = ValidationSoundService.instance;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  Timer? _autoDismissTimer;
  Timer? _countdownTimer;
  int _timeoutSeconds = 5;
  int _remainingSeconds = 5;

  @override
  void initState() {
    super.initState();

    // Setup entrance animation
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );

    // Start animation
    _animationController.forward();

    _soundService.playForStatus(widget.result.status);

    // Load timeout and start auto-dismiss timer
    _loadTimeoutAndStartTimer();
  }

  Future<void> _loadTimeoutAndStartTimer() async {
    _timeoutSeconds = await _settingsService.getValidationPopupTimeoutSeconds();
    _remainingSeconds = _timeoutSeconds;
    if (mounted) {
      setState(() {});
    }

    // Start countdown timer to update UI every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      }
    });

    // Auto-dismiss after configured timeout
    _autoDismissTimer = Timer(Duration(seconds: _timeoutSeconds), () {
      if (mounted) {
        _dismissWithAnimation();
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _countdownTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _dismissWithAnimation() async {
    await _animationController.reverse();
    if (mounted) {
      widget.onDismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uiState = _getUIState(widget.result);

    return GestureDetector(
      onTap: _dismissWithAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: uiState.color.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status header with color bar
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: uiState.color,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Animated icon
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.elasticOut,
                          builder: (context, value, child) {
                            return Transform.scale(
                              scale: value,
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: uiState.color.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  uiState.icon,
                                  size: 48,
                                  color: uiState.color,
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 20),

                        // Status title
                        Text(
                          uiState.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: uiState.color,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 8),

                        // Message
                        Text(
                          widget.result.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        // Ticket ID if available
                        if (widget.result.ticketId != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Ticket ID',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.result.ticketId!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Already used warning
                        if (widget.result.isAlreadyUsed &&
                            widget.result.previousValidationTime != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.warning_amber,
                                      size: 16,
                                      color: Colors.orange.shade700,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Previously Validated',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: Colors.orange.shade700,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.result.previousValidationTime!
                                      .toLocal()
                                      .toString(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.orange.shade900,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Action button - always visible
                        FilledButton.icon(
                          onPressed: _dismissWithAnimation,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan Another'),
                          style: FilledButton.styleFrom(
                            backgroundColor: uiState.color,
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Countdown progress indicator
                        Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: _timeoutSeconds > 0
                                    ? _remainingSeconds / _timeoutSeconds
                                    : null,
                                backgroundColor: uiState.color.withValues(
                                  alpha: 0.1,
                                ),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  uiState.color,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Auto-dismiss in $_remainingSeconds seconds',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ValidationUIState _getUIState(ValidationResult result) {
    switch (result.status) {
      case ValidationStatus.valid:
        return ValidationUIState(
          icon: Icons.check_circle,
          color: Colors.green.shade600,
          title: 'ENTRY GRANTED',
        );
      case ValidationStatus.alreadyUsed:
        return ValidationUIState(
          icon: Icons.cancel,
          color: Colors.red.shade600,
          title: 'ENTRY DENIED',
        );
      case ValidationStatus.invalid:
        return ValidationUIState(
          icon: Icons.error,
          color: Colors.red.shade600,
          title: 'INVALID TICKET',
        );
      case ValidationStatus.eventNotCached:
        return ValidationUIState(
          icon: Icons.cloud_off,
          color: Colors.orange.shade600,
          title: 'SYNC REQUIRED',
        );
      case ValidationStatus.invalidConfig:
      case ValidationStatus.systemError:
        return ValidationUIState(
          icon: Icons.error_outline,
          color: Colors.red.shade600,
          title: 'ERROR',
        );
    }
  }
}

/// UI state configuration for different validation results
class ValidationUIState {
  final IconData icon;
  final Color color;
  final String title;

  const ValidationUIState({
    required this.icon,
    required this.color,
    required this.title,
  });
}
