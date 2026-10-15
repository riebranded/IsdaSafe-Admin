import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// An "Are you sure?" for something that can't be undone with a tap, like the
/// farmer app's Delete account: the destructive button only enables once the
/// admin has typed [phrase], so it can't happen by a stray tap.
///
/// Returns true when confirmed.
Future<bool> showTypedConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String phrase,
  required String confirmLabel,
  IconData icon = Icons.delete_forever_outlined,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _TypedConfirmDialog(
      title: title,
      message: message,
      phrase: phrase,
      confirmLabel: confirmLabel,
      icon: icon,
    ),
  );
  return confirmed == true;
}

class _TypedConfirmDialog extends StatefulWidget {
  const _TypedConfirmDialog({
    required this.title,
    required this.message,
    required this.phrase,
    required this.confirmLabel,
    required this.icon,
  });

  final String title;
  final String message;
  final String phrase;
  final String confirmLabel;
  final IconData icon;

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final _controller = TextEditingController();

  bool get _matches =>
      _controller.text.trim().toUpperCase() == widget.phrase.toUpperCase();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      icon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(widget.icon, color: scheme.error),
      ),
      title: Text(widget.title, textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'To confirm, type '),
                  TextSpan(
                    text: widget.phrase,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' below.'),
                ],
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(hintText: widget.phrase),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_matches) Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
