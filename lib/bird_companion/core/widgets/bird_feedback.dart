import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

abstract final class BirdFeedback {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();
  static const successDuration = Duration(milliseconds: 2000);
  static const undoDuration = Duration(milliseconds: 3200);
  static const queuedDuration = Duration(milliseconds: 3000);
  static const errorDuration = Duration(milliseconds: 4000);

  static void success(BuildContext context, String message) {
    _show(context, message: message, duration: successDuration);
  }

  static void queued(BuildContext context, String message) {
    _show(
      context,
      message: message,
      duration: queuedDuration,
      icon: Icons.cloud_upload_outlined,
    );
  }

  static void undo(
    BuildContext context,
    String message, {
    required VoidCallback onUndo,
  }) {
    _show(
      context,
      message: message,
      duration: undoDuration,
      actionLabel: '撤销',
      onAction: onUndo,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message: message,
      duration: errorDuration,
      icon: Icons.error_outline_rounded,
      backgroundColor: AppColors.danger,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void dismiss(BuildContext context) {
    (ScaffoldMessenger.maybeOf(context) ?? messengerKey.currentState)?.hideCurrentSnackBar(
      reason: SnackBarClosedReason.remove,
    );
  }

  static void dismissAll() {
    messengerKey.currentState?.hideCurrentSnackBar(
      reason: SnackBarClosedReason.remove,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required Duration duration,
    IconData? icon,
    Color? backgroundColor,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context) ?? messengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.remove);
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        persist: false,
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        action: actionLabel == null || onAction == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
  }
}

/// Prevents feedback from one page from following the user to another route.
class BirdFeedbackNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    BirdFeedback.dismissAll();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    BirdFeedback.dismissAll();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    BirdFeedback.dismissAll();
  }
}
