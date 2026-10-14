import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Ported from the farmer app (IsdaSafeV2 `widgets/lazy_load_footer.dart`).
///
/// The end of a list shown a page at a time: while [remaining] items are
/// hidden, it calls [onLoadMore] by itself once it's scrolled into view. A
/// "Load more" button stays as a fallback (e.g. for screen readers). Works
/// inside an outer scroll view, so the list can sit under the charts.
class LazyLoadFooter extends StatefulWidget {
  const LazyLoadFooter({
    super.key,
    required this.remaining,
    required this.onLoadMore,
  });

  final int remaining;
  final VoidCallback onLoadMore;

  /// How far into view (in pixels) the footer must come before the next
  /// page loads.
  static const loadWhenVisible = 24.0;

  @override
  State<LazyLoadFooter> createState() => _LazyLoadFooterState();
}

class _LazyLoadFooterState extends State<LazyLoadFooter> {
  ScrollPosition? _position;
  var _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_maybeLoad);
      _position = position;
      position?.addListener(_maybeLoad);
    }
    _checkAfterFrame();
  }

  @override
  void didUpdateWidget(LazyLoadFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A page just loaded: if it didn't fill the screen, load another.
    _checkAfterFrame();
  }

  @override
  void dispose() {
    _position?.removeListener(_maybeLoad);
    super.dispose();
  }

  void _checkAfterFrame() {
    if (_scheduled || widget.remaining <= 0) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _maybeLoad();
    });
  }

  void _maybeLoad() {
    if (widget.remaining <= 0 || !mounted) return;
    final position = _position;
    if (position == null || !position.hasContentDimensions) return;
    final box = context.findRenderObject() as RenderBox?;
    final viewport = position.context.notificationContext?.findRenderObject();
    if (box == null || !box.attached || viewport is! RenderBox) return;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    if (top <= viewport.size.height - LazyLoadFooter.loadWhenVisible) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.remaining <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Center(
        child: TextButton.icon(
          onPressed: widget.onLoadMore,
          icon: const Icon(Icons.expand_more),
          label: const Text('Load more'),
        ),
      ),
    );
  }
}
