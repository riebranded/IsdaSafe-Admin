import 'package:flutter/material.dart';

import '../services/admin_auth_service.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_tour.dart';
import 'admins_view.dart';
import 'devices_view.dart';
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
  static const _map = 1;
  static const _devices = 2;
  static const _admins = 3;
  static const _settings = 4;

  static const List<_Destination> _destinations = [
    (
      icon: Icons.sensors_outlined,
      selected: Icons.sensors,
      label: 'Monitoring',
    ),
    (icon: Icons.map_outlined, selected: Icons.map, label: 'Map'),
    (
      icon: Icons.developer_board_outlined,
      selected: Icons.developer_board,
      label: 'Devices',
    ),
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

  /// What the guided tour spotlights. Each key sits on whichever variant
  /// (sidebar or bottom bar / app bar) the current layout shows.
  final _tourNavKeys = [
    for (final d in _destinations) GlobalKey(debugLabel: 'tour-${d.label}'),
  ];
  final _tourNavBarKey = GlobalKey(debugLabel: 'tour-nav');
  final _tourBrandKey = GlobalKey(debugLabel: 'tour-brand');
  final _tourAccountKey = GlobalKey(debugLabel: 'tour-account');
  final _tourTutorialKey = GlobalKey(debugLabel: 'tour-tutorial');

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
    // First sign-in on this device: walk the admin through the panel once.
    // It can be replayed any time from Settings.
    _autoStartTour();
  }

  Future<void> _autoStartTour() async {
    if (!await AppTour.shouldAutoStart()) return;
    // Give the dashboard a moment to settle into its final layout.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (mounted) _startTour();
  }

  /// The guided tour of every destination and what can be done there.
  void _startTour() {
    if (AppTour.isShowing) return;
    final isWide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;
    AppTour.start(context, [
      TourStep(
        target: _tourBrandKey,
        icon: Icons.waving_hand_outlined,
        title: 'Welcome to the Isda Safe admin panel',
        body:
            'From here you watch every pond and IsdaSafe device in the system, and manage who else can use this panel. This short tour shows where everything is.',
        onEnter: () => _select(_monitoring),
      ),
      TourStep(
        target: _tourNavBarKey,
        icon: Icons.explore_outlined,
        title: 'Getting around',
        body: isWide
            ? 'This sidebar takes you to every part of the panel. Collapse it with the menu button to make room, and tap the logo any time to come back to Monitoring.'
            : 'The bar at the bottom takes you to every part of the panel.',
      ),
      TourStep(
        target: _tourNavKeys[_monitoring],
        icon: Icons.sensors_outlined,
        title: 'Monitoring',
        body:
            'Every pond with a paired IsdaSafe device, its device connection and its latest water readings. It refreshes every minute.',
        points: const [
          'Search by pond, owner, email or device ID.',
          'Filter to the ponds that need attention, or to online or offline devices.',
          'Switch between cards and a list.',
          'Open a pond for its full page: overall status, latest readings, owner and device, trends over any timeframe, and the readings behind them.',
          'The badge counts the ponds that need attention.',
        ],
        onEnter: () => _select(_monitoring),
      ),
      TourStep(
        target: _tourNavKeys[_map],
        icon: Icons.map_outlined,
        title: 'Map',
        body:
            'Every monitored pond pinned on one map, colored by its water status, with its owner in the marker\'s bubble. Tap a pond to open its full page.',
        onEnter: () => _select(_map),
      ),
      TourStep(
        target: _tourNavKeys[_devices],
        icon: Icons.developer_board_outlined,
        title: 'Devices',
        body:
            'Every device IsdaSafe knows about: paired or not, whoever owns it now or did before, even ones that haven\'t sent a reading yet.',
        points: const [
          'Choose a device to see where it is and how much it has measured.',
          'Its map shows a numbered pin for every spot it has been, with the ponds it was in.',
          'Pick a pond to see the device\'s visits there and their complete readings.',
        ],
        onEnter: () => _select(_devices),
      ),
      TourStep(
        target: _tourNavKeys[_admins],
        icon: Icons.admin_panel_settings_outlined,
        title: 'Admins',
        body: 'Who can use this panel.',
        points: const [
          'Approve or decline new admin registrations.',
          'See every admin account, and remove someone\'s admin access.',
          'The badge counts the requests waiting for an answer.',
        ],
        onEnter: () => _select(_admins),
      ),
      TourStep(
        target: _tourNavKeys[_settings],
        icon: Icons.settings_outlined,
        title: 'Settings',
        body: 'Your own account and panel preferences.',
        points: const [
          'Edit your name, phone number, email and password.',
          'Pick a light or dark look.',
          'Read the legal documents and open-source licenses, or contact the IsdaSafe team.',
          'Sign out, or leave admin access.',
        ],
        onEnter: () => _select(_settings),
      ),
      TourStep(
        target: _tourAccountKey,
        icon: Icons.account_circle_outlined,
        title: 'Your account',
        body: isWide
            ? 'The admin you\'re signed in as. Sign out from here.'
            : 'Sign out from here.',
        onEnter: () => _select(_settings),
      ),
      TourStep(
        target: _tourTutorialKey,
        icon: Icons.celebration_outlined,
        title: 'You\'re all set!',
        body:
            'You can replay this tour any time from Settings → Help → Tutorial.',
        onEnter: () => _select(_settings),
      ),
    ], onFinish: () => _select(_monitoring));
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
    final width = MediaQuery.sizeOf(context).width;
    // Chrome briefly reports a viewport of about 1 px while the tab is hidden
    // or the window is resized (e.g. during a hot restart). Laying the page
    // out that narrow only throws layout errors, so wait for a real size.
    if (width < 120) return const Scaffold(body: SizedBox.shrink());
    final isWide = width >= kWideLayoutBreakpoint;
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
        DevicesView(active: _index == _devices),
        const AdminsView(),
        SettingsView(onStartTour: _startTour, tutorialKey: _tourTutorialKey),
      ],
    );

    if (!isWide) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_destinations[_index].label, key: _tourBrandKey),
          actions: [
            IconButton(
              key: _tourAccountKey,
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: _confirmSignOut,
            ),
          ],
        ),
        body: body,
        bottomNavigationBar: NavigationBar(
          key: _tourNavBarKey,
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            for (final (i, d) in _destinations.indexed)
              KeyedSubtree(
                key: _tourNavKeys[i],
                child: NavigationDestination(
                  icon: _BadgedIcon(icon: d.icon, count: _badgeFor(i)),
                  selectedIcon: _BadgedIcon(
                    icon: d.selected,
                    count: _badgeFor(i),
                  ),
                  label: d.label,
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            key: _tourNavBarKey,
            navKeys: _tourNavKeys,
            brandKey: _tourBrandKey,
            accountKey: _tourAccountKey,
            onHome: () => _select(_monitoring),
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
    super.key,
    required this.navKeys,
    required this.brandKey,
    required this.accountKey,
    required this.onHome,
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

  /// Spotlighted by the guided tour.
  final List<GlobalKey> navKeys;
  final GlobalKey brandKey;
  final GlobalKey accountKey;

  /// Back to Monitoring, from the logo.
  final VoidCallback onHome;

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
                  key: brandKey,
                  collapsed: collapsed,
                  onToggleCollapsed: onToggleCollapsed,
                  onHome: onHome,
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
                    key: navKeys[i],
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
                _AccountFooter(
                  key: accountKey,
                  collapsed: collapsed,
                  onSignOut: onSignOut,
                ),
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
    super.key,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onHome,
  });

  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  /// Tapping the logo or name goes back to Monitoring.
  final VoidCallback onHome;

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
    // Makes the logo (and, expanded, the name) a button back to Monitoring.
    Widget home(Widget child) => Tooltip(
      message: 'Go to Monitoring',
      child: InkWell(
        key: const ValueKey('brand-home'),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onHome,
        child: child,
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
          home(logo),
          const SizedBox(height: AppSpacing.sm),
          toggle,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs, top: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: home(
              Row(
                children: [
                  logo,
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Isda Safe',
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
                ],
              ),
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
    super.key,
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
  const _AccountFooter({
    super.key,
    required this.collapsed,
    required this.onSignOut,
  });

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
