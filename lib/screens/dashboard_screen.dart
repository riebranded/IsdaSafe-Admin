import 'package:flutter/material.dart';

import '../services/admin_auth_service.dart';
import '../theme/app_spacing.dart';
import 'admins_view.dart';
import 'monitoring_view.dart';
import 'pond_map_view.dart';
import 'settings_view.dart';

/// The signed-in admin's shell: a collapsible sidebar on wide screens (like
/// the farmer app's AppShell), a bottom bar on narrow ones. Both show how
/// many ponds need attention and how many admin requests are waiting.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

typedef _Destination = ({IconData icon, IconData selected, String label});

class _DashboardScreenState extends State<DashboardScreen> {
  static const _monitoring = 0;
  static const _admins = 2;

  static const List<_Destination> _destinations = [
    (
      icon: Icons.sensors_outlined,
      selected: Icons.sensors,
      label: 'Monitoring',
    ),
    (icon: Icons.map_outlined, selected: Icons.map, label: 'Map'),
    (
      icon: Icons.admin_panel_settings_outlined,
      selected: Icons.admin_panel_settings,
      label: 'Admins',
    ),
    (
      icon: Icons.settings_outlined,
      selected: Icons.settings,
      label: 'Settings',
    ),
  ];

  var _index = 0;
  var _collapsed = false;
  var _attentionCount = 0;
  var _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
  }

  Future<void> _loadPendingCount() async {
    try {
      final admins = await AdminAuthService.listAdmins();
      if (!mounted) return;
      setState(() {
        _pendingCount = admins
            .where((a) => a.status == AdminStatus.pending)
            .length;
      });
    } catch (e) {
      debugPrint('DashboardScreen: pending count failed $e');
    }
  }

  void _select(int index) {
    if (index == _index) return;
    // Leaving Admins may have approved/declined requests.
    if (_index == _admins || index == _admins) _loadPendingCount();
    setState(() => _index = index);
  }

  int _badgeFor(int index) => switch (index) {
    _monitoring => _attentionCount,
    _admins => _pendingCount,
    _ => 0,
  };

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.logout),
        title: const Text('Sign out?'),
        content: const Text(
          'You\'ll need to log in again to use the admin panel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await AdminAuthService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;
    final body = IndexedStack(
      index: _index,
      children: [
        MonitoringView(
          onAttentionCountChanged: (count) {
            if (mounted && count != _attentionCount) {
              setState(() => _attentionCount = count);
            }
          },
        ),
        const PondMapView(),
        const AdminsView(),
        const SettingsView(),
      ],
    );

    if (!isWide) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_destinations[_index].label),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: _confirmSignOut,
            ),
          ],
        ),
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            for (final (i, d) in _destinations.indexed)
              NavigationDestination(
                icon: _BadgedIcon(icon: d.icon, count: _badgeFor(i)),
                selectedIcon: _BadgedIcon(
                  icon: d.selected,
                  count: _badgeFor(i),
                ),
                label: d.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            collapsed: _collapsed,
            onToggleCollapsed: () => setState(() => _collapsed = !_collapsed),
            destinations: _destinations,
            selectedIndex: _index,
            badgeFor: _badgeFor,
            onSelected: _select,
            onSignOut: _confirmSignOut,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.destinations,
    required this.selectedIndex,
    required this.badgeFor,
    required this.onSelected,
    required this.onSignOut,
  });

  static const _expandedWidth = 256.0;
  static const _collapsedWidth = 80.0;

  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final List<_Destination> destinations;
  final int selectedIndex;
  final int Function(int index) badgeFor;
  final ValueChanged<int> onSelected;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: Curves.easeOutCubic,
      width: collapsed ? _collapsedWidth : _expandedWidth,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        right: false,
        // Lays out at the final width while the container animates, so the
        // labels never wrap mid-animation.
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          maxWidth: collapsed ? _collapsedWidth : _expandedWidth,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SidebarHeader(
                  collapsed: collapsed,
                  onToggleCollapsed: onToggleCollapsed,
                ),
                const SizedBox(height: AppSpacing.xl),
                if (!collapsed)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.md,
                      bottom: AppSpacing.sm,
                    ),
                    child: Text(
                      'MENU',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                for (final (i, d) in destinations.indexed) ...[
                  _SidebarButton(
                    icon: d.icon,
                    selectedIcon: d.selected,
                    label: d.label,
                    selected: i == selectedIndex,
                    badge: badgeFor(i),
                    collapsed: collapsed,
                    onTap: () => onSelected(i),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                const Spacer(),
                _AccountFooter(collapsed: collapsed, onSignOut: onSignOut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Image.asset(
        'assets/branding/logo.png',
        width: 40,
        height: 40,
        semanticLabel: 'IsdaSafe logo',
      ),
    );
    final toggle = IconButton(
      tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
      onPressed: onToggleCollapsed,
      icon: Icon(collapsed ? Icons.menu : Icons.menu_open),
    );

    if (collapsed) {
      return Column(
        children: [
          const SizedBox(height: AppSpacing.xs),
          logo,
          const SizedBox(height: AppSpacing.sm),
          toggle,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs, top: AppSpacing.xs),
      child: Row(
        children: [
          logo,
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'IsdaSafe',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Admin panel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          toggle,
        ],
      ),
    );
  }
}

/// A full-width sidebar entry: a tinted pill with an accent bar when
/// selected, a hover/focus highlight, and an optional count badge. Collapsed,
/// it's an icon with a tooltip.
class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.collapsed,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final int badge;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final iconWidget = Icon(
      selected ? selectedIcon : icon,
      color: selected ? scheme.primary : foreground,
    );

    final content = collapsed
        ? Center(child: _BadgedIcon.wrap(iconWidget, badge))
        : Row(
            children: [
              iconWidget,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge > 0) _CountBadge(count: badge),
            ],
          );

    final button = Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '$label, $badge' : label,
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          hoverColor: scheme.onSurface.withValues(alpha: 0.06),
          child: SizedBox(
            height: 48,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: AppMotion.fast,
                  left: 0,
                  top: selected ? 12 : 24,
                  bottom: selected ? 12 : 24,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: selected ? scheme.primary : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: collapsed ? 0 : AppSpacing.md,
                    ),
                    child: content,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return collapsed
        ? Tooltip(
            message: badge > 0 ? '$label ($badge)' : label,
            preferBelow: false,
            child: button,
          )
        : button;
  }
}

class _AccountFooter extends StatelessWidget {
  const _AccountFooter({required this.collapsed, required this.onSignOut});

  final bool collapsed;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: AdminAuthService.ownProfile,
      builder: (context, _, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final email = AdminAuthService.currentUser?.email ?? '';
    final firstName = AdminAuthService.ownFirstName;
    final name = firstName.isNotEmpty ? firstName : email;
    final avatar = CircleAvatar(
      radius: 18,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: theme.textTheme.titleSmall?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
    final signOut = IconButton(
      tooltip: 'Sign out',
      onPressed: onSignOut,
      icon: const Icon(Icons.logout),
      color: scheme.onSurfaceVariant,
    );

    if (collapsed) {
      return Column(
        children: [
          Tooltip(message: '$name\n$email', child: avatar),
          const SizedBox(height: AppSpacing.sm),
          signOut,
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Tooltip(message: email, child: avatar),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Admin',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          signOut,
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onError,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// An icon with a small count badge (none when [count] is 0).
class _BadgedIcon extends StatelessWidget {
  const _BadgedIcon({required this.icon, required this.count});

  final IconData icon;
  final int count;

  static Widget wrap(Widget icon, int count) =>
      count > 0 ? Badge.count(count: count, child: icon) : icon;

  @override
  Widget build(BuildContext context) => wrap(Icon(icon), count);
}
