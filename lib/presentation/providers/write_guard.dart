import 'package:flutter/material.dart';

/// Runs a write and, if it fails, surfaces a SnackBar with a «Повторить» action.
///
/// Writes are pessimistic — the provider refetches after the repository call — so
/// a failure means nothing changed and retrying the same action is safe.
/// Returns `true` when the write eventually succeeded.
Future<bool> runWrite(
  BuildContext context,
  Future<void> Function() action, {
  String failureMessage = 'Не удалось сохранить',
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    return true;
  } catch (_) {
    if (messenger == null) return false;
    messenger.hideCurrentSnackBar();
    final retry = await messenger
        .showSnackBar(
          SnackBar(
            content: Text(failureMessage),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Повторить',
              // The closure's value is what `closed` reports, so tapping the action
              // is how the caller learns a retry was requested.
              onPressed: () {},
            ),
          ),
        )
        .closed;
    if (retry == SnackBarClosedReason.action && context.mounted) {
      return runWrite(context, action, failureMessage: failureMessage);
    }
    return false;
  }
}
