import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_auth_service.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_controller.dart';
import '../widgets/name_fields.dart';
import '../widgets/password_strength_checklist.dart';
import 'legal/legal_screen.dart';

/// The admin's own account and panel preferences — the admin counterpart of
/// the farmer app's Settings screen: profile, password, appearance, legal,
/// sign out and leaving admin access.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late Future<AdminProfile?> _profileFuture =
      AdminAuthService.fetchOwnProfile();

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editName(AdminProfile profile) async {
    final current = profile.hasFirstAndLastName
        ? (first: profile.firstName!, last: profile.lastName!)
        : splitFullName(profile.fullName);
    final updated = await showDialog<({String first, String last})>(
      context: context,
      builder: (_) => _EditNameDialog(initial: current),
    );
    if (updated == null || updated == current || !mounted) return;
    try {
      await AdminAuthService.updateOwnName(
        firstName: updated.first,
        lastName: updated.last,
      );
      if (!mounted) return;
      setState(() => _profileFuture = AdminAuthService.fetchOwnProfile());
      _showMessage('Name updated.');
    } catch (e) {
      debugPrint('SettingsView: rename error $e');
      if (mounted) _showMessage('Couldn\'t update your name. Try again.');
    }
  }

  Future<void> _changePassword() async {
    final message = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (message != null && mounted) _showMessage(message);
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
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

  Widget _sectionTitle(ThemeData theme, String title) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = AdminAuthService.currentUser;

    return FutureBuilder<AdminProfile?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final fullName = profile?.fullName ?? AdminAuthService.currentUserName;
        final email = profile?.email ?? user?.email ?? '';
        final displayName = fullName.isNotEmpty ? fullName : email;
        final photoUrl = user?.userMetadata?['avatar_url'] as String?;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: theme.colorScheme.primary,
                          backgroundImage: photoUrl != null
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl == null
                              ? Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color: theme.colorScheme.onPrimary,
                                    fontSize: 20,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                displayName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (email.isNotEmpty && email != displayName)
                                Text(
                                  email,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              if (profile != null)
                                Text(
                                  'Admin since ${MaterialLocalizations.of(context).formatMediumDate(profile.createdAt)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit name',
                          onPressed: profile == null
                              ? null
                              : () => _editName(profile),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _sectionTitle(theme, 'Sign-in'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.email_outlined),
                        title: const Text('Email'),
                        subtitle: Text(email.isEmpty ? 'Not set' : email),
                      ),
                      const Divider(height: 1),
                      if (AdminAuthService.hasPasswordLogin)
                        ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: const Text('Password'),
                          subtitle: const Text('Change your password'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _changePassword,
                        )
                      else
                        const ListTile(
                          leading: Icon(Icons.lock_outline),
                          title: Text('Password'),
                          subtitle: Text(
                            'You sign in with Google, so there\'s no '
                            'password to change.',
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const _AppearanceCard(),
                const SizedBox(height: AppSpacing.lg),
                _sectionTitle(theme, 'Legal & about'),
                Card(
                  child: Column(
                    children: [
                      for (final document in LegalDocument.values) ...[
                        ListTile(
                          leading: Icon(document.icon),
                          title: Text(document.title),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => openLegalDocument(context, document),
                        ),
                        const Divider(height: 1),
                      ],
                      ListTile(
                        leading: const Icon(Icons.code),
                        title: const Text('Open-source licenses'),
                        subtitle: const Text(
                          'Fonts, packages and other software used here',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => showLicensePage(
                          context: context,
                          applicationName: 'IsdaSafe Admin',
                          applicationIcon: Padding(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            child: Image.asset(
                              'assets/branding/logo.png',
                              width: 48,
                              height: 48,
                              semanticLabel: 'IsdaSafe logo',
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      const ListTile(
                        leading: Icon(Icons.support_agent_outlined),
                        title: Text('Contact the IsdaSafe team'),
                        subtitle: SelectableText(kLegalContactEmail),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Sign out'),
                    onTap: _confirmSignOut,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Card(child: _LeaveAdminTile()),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({required this.initial});

  final ({String first, String last}) initial;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _firstName = TextEditingController(text: widget.initial.first);
  late final _lastName = TextEditingController(text: widget.initial.last);

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(
      context,
    ).pop((first: _firstName.text.trim(), last: _lastName.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit name'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: NameFields(
            firstName: _firstName,
            lastName: _lastName,
            autofocus: true,
            onSubmitted: _submit,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _emailCode = TextEditingController();
  var _obscure = true;
  var _needsEmailCode = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _emailCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!isStrongPassword(_password.text)) {
      setState(() => _error = 'Password doesn\'t meet all the requirements');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords don\'t match');
      return;
    }
    final nonce = _needsEmailCode ? _emailCode.text.trim() : null;
    if (_needsEmailCode && (nonce?.isEmpty ?? true)) {
      setState(() => _error = 'Enter the code we emailed you');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminAuthService.updatePassword(_password.text, nonce: nonce);
      if (mounted) Navigator.of(context).pop('Password updated.');
    } on AuthException catch (e) {
      if (AdminAuthService.needsReauthentication(e) && !_needsEmailCode) {
        try {
          await AdminAuthService.sendReauthenticationCode();
          if (mounted) setState(() => _needsEmailCode = true);
        } on AuthException catch (e2) {
          if (mounted) setState(() => _error = e2.message);
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      debugPrint('ChangePasswordDialog: error $e');
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Change password'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_needsEmailCode) ...[
                Text(
                  'For your security, we emailed you a code. Enter it to '
                  'confirm the change.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _emailCode,
                  autofocus: true,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Email code'),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextField(
                controller: _password,
                autofocus: !_needsEmailCode,
                enabled: !_busy,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'New password',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: AppSpacing.sm),
              PasswordStrengthChecklist(password: _password.text),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _confirm,
                enabled: !_busy,
                obscureText: _obscure,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Update'),
        ),
      ],
    );
  }
}

/// Light / Dark / System picker backed by [ThemeController].
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  static const _options = [
    (
      mode: ThemeMode.system,
      label: 'System default',
      description: 'Match your device\'s theme',
      icon: Icons.brightness_auto_outlined,
    ),
    (
      mode: ThemeMode.light,
      label: 'Light',
      description: 'Always use the light theme',
      icon: Icons.light_mode_outlined,
    ),
    (
      mode: ThemeMode.dark,
      label: 'Dark',
      description: 'Always use the dark theme',
      icon: Icons.dark_mode_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ThemeController.instance;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    'Appearance',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              RadioGroup<ThemeMode>(
                groupValue: controller.themeMode,
                onChanged: (mode) {
                  if (mode != null) controller.setThemeMode(mode);
                },
                child: Column(
                  children: [
                    for (final option in _options)
                      RadioListTile<ThemeMode>(
                        value: option.mode,
                        secondary: Icon(option.icon),
                        title: Text(option.label),
                        subtitle: Text(option.description),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gives up this account's admin access. Only the admin record goes: the
/// login is shared with the farmer app, which has its own Delete account.
class _LeaveAdminTile extends StatefulWidget {
  const _LeaveAdminTile();

  @override
  State<_LeaveAdminTile> createState() => _LeaveAdminTileState();
}

class _LeaveAdminTileState extends State<_LeaveAdminTile> {
  var _leaving = false;

  Future<void> _leave() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _LeaveAdminDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _leaving = true);
    try {
      await AdminAuthService.leaveAdminAccess();
      messenger.showSnackBar(
        const SnackBar(content: Text('You\'re no longer an admin.')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _leaving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      debugPrint('LeaveAdminTile: error $e');
      if (!mounted) return;
      setState(() => _leaving = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Couldn\'t remove your access. Check your connection and try '
            'again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return ListTile(
      leading: Icon(Icons.person_remove_outlined, color: error),
      title: Text('Leave admin access', style: TextStyle(color: error)),
      subtitle: const Text(
        'Delete your admin record and sign out. You\'d need a new approval '
        'to come back.',
      ),
      trailing: _leaving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _leaving ? null : _leave,
    );
  }
}

class _LeaveAdminDialog extends StatelessWidget {
  const _LeaveAdminDialog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.person_remove_outlined, color: scheme.error),
      title: const Text('Leave admin access?', textAlign: TextAlign.center),
      content: const SizedBox(
        width: 360,
        child: Text(
          'Your admin record is deleted and you\'re signed out. Your login '
          'stays, since it\'s shared with the IsdaSafe farmer app — delete it '
          'there under Settings > Delete account if you want it gone too.',
          textAlign: TextAlign.center,
        ),
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
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Leave'),
        ),
      ],
    );
  }
}
