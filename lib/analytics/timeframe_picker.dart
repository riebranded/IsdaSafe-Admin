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
///
/// For single readings (not trend steps) it can lead with an [allLabel]
/// chip (e.g. "Whole visit"), leave out "Group by" and describe itself
/// ([description]).
class TimeframePicker extends StatelessWidget {
  const TimeframePicker({
    super.key,
    required this.selection,
    required this.onChanged,
    this.lastPreset = TrendRange.hourly,
    this.allLabel,
    this.allSelected = false,
    this.onAll,
    this.showGroupBy = true,
    this.singleLabel,
    this.readingDays,
    this.description,
  });

  final TrendSelection selection;
  final ValueChanged<TrendSelection> onChanged;

  /// Where clearing a custom range goes back to.
  final TrendRange lastPreset;

  /// A chip before the presets for "no timeframe" (everything); selected
  /// instead of [selection] while [allSelected].
  final String? allLabel;
  final bool allSelected;
  final VoidCallback? onAll;

  /// The custom range's "Group by" choice, for trend steps only.
  final bool showGroupBy;

  /// For a custom range, offers every step (not only those that give a
  /// readable number of points) and, first, this choice for the readings
  /// themselves, ungrouped (e.g. "Whole visit").
  final String? singleLabel;

  /// The days that have readings: only those can be picked as custom dates.
  /// Null allows any day.
  final Future<Set<DateTime>?> Function()? readingDays;

  /// Replaces the "Last 24 hours · by hour" line.
  final String? description;

  /// The days with readings, or null (no limit) when unknown.
  Future<Set<DateTime>?> _readingDays() async {
    try {
      return await readingDays?.call();
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickDates(BuildContext context) async {
    // Only days the pond has readings can be picked.
    final days = await _readingDays();
    if (!context.mounted) return;
    if (days != null && days.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No readings yet for this pond')));
      return;
    }
    final picked = await showModalDateRangePicker(
      context,
      initial: selection.custom,
      days: days,
    );
    if (picked == null || !context.mounted) return;
    // Ask how to group the readings, when the range suits more than one way.
    final steps = _stepsFor(TrendSelection.dates(picked));
    if (steps.length < 2 && singleLabel == null) {
      onChanged(TrendSelection.dates(picked, customStep: selection.customStep));
      return;
    }
    final choice = await _askGrouping(context, steps, picked);
    final any = singleLabel != null;
    onChanged(
      choice == null
          ? TrendSelection.dates(picked, anyStep: any)
          : choice.single
          ? TrendSelection.dates(picked, single: true, anyStep: any)
          : TrendSelection.dates(picked, customStep: choice.step, anyStep: any),
    );
  }

  /// The steps a custom range can be grouped by.
  List<TrendStep> _stepsFor(TrendSelection selection) => singleLabel != null
      ? TrendStep.values
      : TrendSelection.stepsFor(selection.window().duration);

  /// "Show the readings as ...": each reading, or one average per 15 minutes,
  /// hour, day, ... Dismissing keeps the automatic choice.
  Future<({bool single, TrendStep? step})?> _askGrouping(
    BuildContext context,
    List<TrendStep> steps,
    DateTimeRange picked,
  ) {
    final auto = TrendSelection.dates(picked).step;
    Widget option(
      BuildContext context,
      String text,
      ({bool single, TrendStep? step}) value, {
      bool suggested = false,
      String? unavailable,
    }) => SimpleDialogOption(
      onPressed: unavailable == null
          ? () => Navigator.pop(context, value)
          : null,
      child: Row(
        children: [
          Expanded(
            child: Opacity(
              opacity: unavailable == null ? 1 : 0.45,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: Theme.of(context).textTheme.bodyLarge),
                  if (unavailable != null)
                    Text(
                      unavailable,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          if (suggested)
            Icon(
              Icons.thumb_up_alt_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
    return showDialog<({bool single, TrendStep? step})>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
          singleLabel == null
              ? 'Average the readings by'
              : 'Show the readings as',
        ),
        children: [
          if (singleLabel != null)
            option(context, singleLabel!, (single: true, step: null)),
          for (final step in TrendStep.values)
            option(
              context,
              _choiceNames[step]!,
              (single: false, step: step),
              suggested: singleLabel == null && step == auto,
              unavailable: singleLabel != null || steps.contains(step)
                  ? null
                  : steps.isEmpty || step.index < steps.first.index
                  ? 'Too many points for this range'
                  : 'Too few points for this range',
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final custom = allSelected ? null : selection.custom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (allLabel != null)
              ChoiceChip(
                label: Text(allLabel!, maxLines: 1, softWrap: false),
                selected: allSelected,
                showCheckmark: false,
                onSelected: (_) => onAll?.call(),
              ),
            for (final r in TrendRange.values)
              ChoiceChip(
                label: Text(r.label, maxLines: 1, softWrap: false),
                selected: !allSelected && selection.range == r,
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
          if (showGroupBy) ...[
            const SizedBox(height: AppSpacing.sm),
            _GroupBy(
              selection: selection,
              steps: _stepsFor(selection),
              singleLabel: singleLabel,
              onChanged: (choice) => onChanged(
                choice == null
                    ? TrendSelection.dates(
                        custom,
                        single: true,
                        anyStep: singleLabel != null,
                      )
                    : TrendSelection.dates(
                        custom,
                        customStep: choice,
                        anyStep: singleLabel != null,
                      ),
              ),
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Icon(Icons.schedule, size: 16, color: muted),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                description ?? selection.description,
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
/// give it a readable number of points (or all of them, after a
/// [singleLabel] chip for the readings themselves). [onChanged] gets null for
/// the single readings.
class _GroupBy extends StatelessWidget {
  const _GroupBy({
    required this.selection,
    required this.steps,
    required this.onChanged,
    this.singleLabel,
  });

  final TrendSelection selection;
  final List<TrendStep> steps;
  final String? singleLabel;
  final ValueChanged<TrendStep?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (steps.length < 2 && singleLabel == null) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Group by', style: theme.textTheme.labelLarge),
        if (singleLabel != null)
          ChoiceChip(
            label: Text(singleLabel!),
            selected: selection.single,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onChanged(null),
          ),
        for (final step in steps)
          ChoiceChip(
            label: Text(step.label),
            selected: !selection.single && selection.step == step,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onChanged(step),
          ),
      ],
    );
  }
}

const _choiceNames = {
  TrendStep.fifteenMinutes: 'Every 15 minutes',
  TrendStep.hour: 'Hourly',
  TrendStep.day: 'Daily',
  TrendStep.week: 'Weekly',
  TrendStep.month: 'Monthly',
  TrendStep.year: 'Yearly',
};

/// Picks a date range with two modal calendar dialogs (start, then end).
///
/// Flutter's `showDateRangePicker` always takes over the whole screen in
/// calendar mode; the single-date picker stays a centered modal, so the range
/// is built from two of them. Returns null if either is dismissed.
Future<DateTimeRange?> showModalDateRangePicker(
  BuildContext context, {
  DateTimeRange? initial,
  Set<DateTime>? days,
}) async {
  final now = DateTime.now();
  // With [days] (the days that have readings), only those can be picked.
  final sorted = days == null ? null : (days.toList()..sort());
  final firstDate = sorted?.first ?? DateTime(now.year - 2);
  final lastDate = sorted?.last ?? now;
  bool selectable(DateTime d) =>
      days == null || days.contains(DateUtils.dateOnly(d));

  /// [want], or the nearest pickable day (not before [from]).
  DateTime nearest(DateTime want, DateTime from) {
    final w = DateUtils.dateOnly(want);
    if (sorted == null) return w.isBefore(from) ? from : w;
    final options = sorted.where((d) => !d.isBefore(from)).toList();
    options.sort(
      (a, b) => (a.difference(w).inHours.abs()).compareTo(
        b.difference(w).inHours.abs(),
      ),
    );
    return options.first;
  }

  final fallbackStart = now.subtract(const Duration(days: 7));

  final start = await showDatePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    selectableDayPredicate: selectable,
    initialDate: nearest(initial?.start ?? fallbackStart, firstDate),
    helpText: 'Select start date',
  );
  if (start == null || !context.mounted) return null;

  final initialEnd = initial?.end ?? now;
  final end = await showDatePicker(
    context: context,
    firstDate: start,
    lastDate: lastDate,
    selectableDayPredicate: selectable,
    initialDate: nearest(initialEnd, start),
    helpText: 'Select end date',
  );
  if (end == null) return null;

  return DateTimeRange(start: start, end: end);
}
