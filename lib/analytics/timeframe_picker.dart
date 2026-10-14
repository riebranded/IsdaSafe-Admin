import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'trend_range.dart';

/// Picks what a trend shows, shared by the Analytics page and a reading's
/// detail view:
///  * the presets (15 min, Hourly, Daily, Weekly, Monthly, Yearly) as chips
///    that wrap onto a second line on a phone instead of scrolling out of
///    view;
///  * "Custom" after them, opening a date range picker; while a custom range
///    is in use the dates show on their own line instead (tap to change, x to
///    go back to [lastPreset]), with a "Group by" choice of the steps that
///    suit it;
///  * a line saying what's shown, e.g. "Last 24 hours · by hour".
class TimeframePicker extends StatelessWidget {
  const TimeframePicker({
    super.key,
    required this.selection,
    required this.onChanged,
    this.lastPreset = TrendRange.hourly,
  });

  final TrendSelection selection;
  final ValueChanged<TrendSelection> onChanged;

  /// Where clearing a custom range goes back to.
  final TrendRange lastPreset;

  Future<void> _pickDates(BuildContext context) async {
    final picked = await showModalDateRangePicker(
      context,
      initial: selection.custom,
    );
    if (picked == null) return;
    onChanged(TrendSelection.dates(picked, customStep: selection.customStep));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final custom = selection.custom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final r in TrendRange.values)
              ChoiceChip(
                label: Text(r.label, maxLines: 1, softWrap: false),
                selected: selection.range == r,
                showCheckmark: false,
                onSelected: (_) => onChanged(TrendSelection.preset(r)),
              ),
            if (custom == null)
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text('Custom'),
                tooltip: 'Pick your own dates',
                onPressed: () => _pickDates(context),
              ),
          ],
        ),
        if (custom != null) ...[
          const SizedBox(height: AppSpacing.sm),
          InputChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(
              selection.customLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            selected: true,
            showCheckmark: false,
            tooltip: 'Change dates',
            onPressed: () => _pickDates(context),
            deleteButtonTooltipMessage: 'Clear custom timeframe',
            onDeleted: () => onChanged(TrendSelection.preset(lastPreset)),
          ),
          const SizedBox(height: AppSpacing.sm),
          _GroupBy(
            selection: selection,
            onChanged: (step) =>
                onChanged(TrendSelection.dates(custom, customStep: step)),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Icon(Icons.schedule, size: 16, color: muted),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                selection.description,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Group by: Hour Day Week Month" for a custom range: only the steps that
/// give it a readable number of points.
class _GroupBy extends StatelessWidget {
  const _GroupBy({required this.selection, required this.onChanged});

  final TrendSelection selection;
  final ValueChanged<TrendStep> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = TrendSelection.stepsFor(selection.window().duration);
    if (steps.length < 2) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Group by', style: theme.textTheme.labelLarge),
        for (final step in steps)
          ChoiceChip(
            label: Text(step.label),
            selected: selection.step == step,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onChanged(step),
          ),
      ],
    );
  }
}

/// Picks a date range with two modal calendar dialogs (start, then end).
///
/// Flutter's `showDateRangePicker` always takes over the whole screen in
/// calendar mode; the single-date picker stays a centered modal, so the range
/// is built from two of them. Returns null if either is dismissed.
Future<DateTimeRange?> showModalDateRangePicker(
  BuildContext context, {
  DateTimeRange? initial,
}) async {
  final now = DateTime.now();
  final firstDate = DateTime(now.year - 2);
  final fallbackStart = now.subtract(const Duration(days: 7));

  final start = await showDatePicker(
    context: context,
    firstDate: firstDate,
    lastDate: now,
    initialDate: initial?.start ?? fallbackStart,
    helpText: 'Select start date',
  );
  if (start == null || !context.mounted) return null;

  final initialEnd = initial?.end ?? now;
  final end = await showDatePicker(
    context: context,
    firstDate: start,
    lastDate: now,
    initialDate: initialEnd.isBefore(start) ? start : initialEnd,
    helpText: 'Select end date',
  );
  if (end == null) return null;

  return DateTimeRange(start: start, end: end);
}
