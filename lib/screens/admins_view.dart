import 'package:flutter/material.dart';

import '../services/admin_auth_service.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/birth_date_field.dart';
import '../widgets/status_badge.dart';
import '../widgets/typed_confirm_dialog.dart';

/// Admin accounts and pending requests; approved admins approve or decline
/// new registrations here.
class AdminsView extends StatefulWidget {
  const AdminsView({super.key});

  @override
  State<AdminsView> createState() => _AdminsViewState();
}

class _AdminsViewState extends State<AdminsView> {
  late Future<List<AdminProfile>> _future = AdminAuthService.listAdmins();
  final _busy = <String>{};

  void _reload() => setState(() => _future = AdminAuthService.listAdmins());

  Future<void> _setStatus(AdminProfile admin, AdminStatus status) async {
    setState(() => _busy.add(admin.userId));
    try {
      await AdminAuthService.setStatus(admin.userId, status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == AdminStatus.approved
                ? '${admin.fullName} can now use the admin panel.'
                : '${admin.fullName}\'s access was declined.',
          ),
        ),
      );
      _reload();
    } catch (e) {
      debugPrint('AdminsView: setStatus failed $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t update access. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(admin.userId));
    }
  }

  /// Revoking an approved admin takes their access away at once, so it asks
  /// for a typed confirmation first. Declining a pending request doesn't.
  Future<void> _revokeOrDecline(AdminProfile admin) async {
    if (admin.status == AdminStatus.approved) {
      final confirmed = await showTypedConfirmDialog(
        context,
        icon: Icons.person_remove_outlined,
        title: "Revoke ${admin.fullName}'s access?",
        message:
            '${admin.fullName} will be signed out of the admin panel and '
            "can't use it again unless an admin approves them again.",
        phrase: 'REVOKE ACCESS',
        confirmLabel: 'Revoke access',
      );
      if (!confirmed || !mounted) return;
    }
    await _setStatus(admin, AdminStatus.rejected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final myId = AdminAuthService.currentUser?.id;

    return FutureBuilder<List<AdminProfile>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Couldn\'t load admins.'),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final admins = snapshot.data!;
        final pending = admins
            .where((a) => a.status == AdminStatus.pending)
            .toList();
        final others = admins
            .where((a) => a.status != AdminStatus.pending)
            .toList();

        Widget tile(AdminProfile admin) {
          final busy = _busy.contains(admin.userId);
          final isMe = admin.userId == myId;
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  admin.fullName.isEmpty
                      ? '?'
                      : admin.fullName[0].toUpperCase(),
                ),
              ),
              title: Text(isMe ? '${admin.fullName} (you)' : admin.fullName),
              subtitle: Text(
                '${admin.email}'
                '${admin.phone == null ? '' : ' · ${admin.phone}${admin.phoneVerified ? '' : ' (unverified)'}'}'
                '${admin.birthDate == null ? '' : ' · ${ageOn(admin.birthDate!, DateTime.now())} years old'}'
                '\nRequested '
                '${MaterialLocalizations.of(context).formatMediumDate(admin.createdAt)}',
              ),
              isThreeLine: true,
              trailing: busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Wrap(
                      spacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusLabel(status: admin.status),
                        if (!isMe && admin.status != AdminStatus.approved)
                          IconButton.filledTonal(
                            tooltip: 'Approve',
                            onPressed: () =>
                                _setStatus(admin, AdminStatus.approved),
                            icon: const Icon(Icons.check),
                          ),
                        if (!isMe && admin.status != AdminStatus.rejected)
                          IconButton(
                            tooltip: admin.status == AdminStatus.approved
                                ? 'Revoke access'
                                : 'Decline',
                            onPressed: () => _revokeOrDecline(admin),
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Text('Admins', style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Approve new admin registrations before they can sign in.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Pending requests (${pending.length})',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (pending.isEmpty)
                Text(
                  'No pending requests.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              for (final a in pending) ...[
                tile(a),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.xl),
              Text('All admins', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              for (final a in others) ...[
                tile(a),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});

  final AdminStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    return switch (status) {
      AdminStatus.approved => StatusPill(
        label: 'Approved',
        icon: Icons.check_circle,
        color: colors.good,
      ),
      AdminStatus.pending => StatusPill(
        label: 'Pending',
        icon: Icons.hourglass_top,
        color: colors.warning,
      ),
      _ => StatusPill(
        label: 'Declined',
        icon: Icons.block,
        color: colors.critical,
      ),
    };
  }
}
