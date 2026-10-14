import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// Where admins can reach the IsdaSafe team about privacy or these terms.
/// Same contact as the farmer app's legal pages.
const kLegalContactEmail = 'sanchezdoreenjoymarait@gmail.com';

/// Shown at the top of both documents. Bump whenever either one changes.
const _lastUpdated = 'October 13, 2026';

/// The admin panel's own legal documents. They cover the admin's account and
/// their duties toward the farmer data the panel shows; farmers have their
/// own Privacy Policy and Terms in the IsdaSafe app.
enum LegalDocument {
  privacyNotice('Admin Privacy Notice', Icons.privacy_tip_outlined),
  termsOfUse('Admin Terms of Use', Icons.description_outlined);

  const LegalDocument(this.title, this.icon);

  final String title;
  final IconData icon;

  List<({String heading, String body})> get sections => switch (this) {
    LegalDocument.privacyNotice => _privacySections,
    LegalDocument.termsOfUse => _termsSections,
  };
}

/// Opens [document] as a full page.
void openLegalDocument(BuildContext context, LegalDocument document) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => LegalScreen(document: document)));
}

/// Read-only page showing a [LegalDocument]. Reachable before sign-in (from
/// Login, Register and the access request) and after (from Settings).
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Text(
                  document.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('Last updated: $_lastUpdated', style: mutedStyle),
                const SizedBox(height: AppSpacing.lg),
                for (final section in document.sections) ...[
                  Text(
                    section.heading,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SelectableText(
                    section.body.replaceAll('{email}', kLegalContactEmail),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Terms of Use · Privacy Notice" links, for the Login footer.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkStyle = TextButton.styleFrom(
      textStyle: theme.textTheme.bodySmall,
      visualDensity: VisualDensity.compact,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          style: linkStyle,
          onPressed: () => openLegalDocument(context, LegalDocument.termsOfUse),
          child: const Text('Terms of Use'),
        ),
        Text('·', style: theme.textTheme.bodySmall),
        TextButton(
          style: linkStyle,
          onPressed: () =>
              openLegalDocument(context, LegalDocument.privacyNotice),
          child: const Text('Privacy Notice'),
        ),
      ],
    );
  }
}

/// Required "I agree" checkbox before requesting admin access, with links to
/// both documents so they can be read first.
class LegalConsentCheckbox extends StatelessWidget {
  const LegalConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;

  /// Null disables the checkbox (e.g. while the form is submitting).
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    return Row(
      children: [
        Checkbox(
          value: value,
          semanticLabel:
              'I agree to the Admin Terms of Use and Admin Privacy Notice',
          onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
        ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('I agree to the', style: theme.textTheme.bodySmall),
              TextButton(
                style: linkStyle,
                onPressed: () =>
                    openLegalDocument(context, LegalDocument.termsOfUse),
                child: const Text('Terms of Use'),
              ),
              Text('and', style: theme.textTheme.bodySmall),
              TextButton(
                style: linkStyle,
                onPressed: () =>
                    openLegalDocument(context, LegalDocument.privacyNotice),
                child: const Text('Privacy Notice'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

const _privacySections = <({String heading, String body})>[
  (
    heading: '1. About this notice',
    body:
        'This notice covers the IsdaSafe admin panel and the personal data of '
        'the people who use it as administrators. Farmers using the IsdaSafe '
        'app are covered by its own Privacy Policy. We follow the Philippine '
        'Data Privacy Act of 2012 (Republic Act No. 10173).',
  ),
  (
    heading: '2. What we collect about admins',
    body:
        '• Account details: your full name, email address and password (stored '
        'only in hashed form by our authentication provider). If you sign in '
        'with Google, we receive your Google name, email address and profile '
        'picture.\n'
        '• Admin record: whether your access is pending, approved or declined, '
        'when you requested it, and which admin reviewed it and when.\n'
        '• Preferences: your theme choice, saved only in your browser or '
        'device.\n'
        "On the web, the panel uses your browser's local storage only to keep "
        'you signed in and remember your theme. We do not use advertising or '
        'tracking cookies, so there is nothing to opt in to.',
  ),
  (
    heading: '3. Why we use it',
    body:
        '• To sign you in and decide whether you may use the panel.\n'
        '• To let approved admins review and approve or decline access '
        'requests. Approved admins can see the name, email, status and dates '
        'of every admin account and request.\n'
        '• To keep the panel secure and fix problems.\n'
        'We do not sell your data or use it for advertising.',
  ),
  (
    heading: '4. Services we use',
    body:
        '• Supabase: sign-in and database.\n'
        '• Google: Google Sign-In, and Google Fonts (your browser downloads the '
        "panel's fonts from Google's servers, which see your IP address).\n"
        '• Cloudflare Turnstile: bot protection on sign-in, registration and '
        'password reset.',
  ),
  (
    heading: '5. How long we keep it',
    body:
        'We keep your admin record while you have admin access. You can give '
        'up your access at any time in Settings > Leave admin access, which '
        "deletes your admin record. Your login itself is shared with the "
        'IsdaSafe farmer app; to delete it entirely, use Settings > Delete '
        'account in that app or contact us. A declined request is kept so it '
        "can't simply be filed again.",
  ),
  (
    heading: '6. Your rights',
    body:
        'You have the right to be informed, to access, correct and erase your '
        'data, to object to its processing, to data portability, and to file a '
        'complaint with the National Privacy Commission. You can change your '
        'name and password in Settings. For anything else, email {email}.',
  ),
  (
    heading: '7. Changes and contact',
    body:
        'We will change the "Last updated" date above when this notice '
        'changes. Questions can be sent to {email}.',
  ),
];

const _termsSections = <({String heading, String body})>[
  (
    heading: '1. Who may use the panel',
    body:
        'The admin panel is for people authorised by the IsdaSafe team to '
        'monitor ponds and devices. You must be at least 18 years old. '
        'Registering only files a request: an existing admin must approve it, '
        'and access can be declined or withdrawn at any time.',
  ),
  (
    heading: '2. Your account',
    body:
        'Give accurate details, keep your password private, and do not share '
        'your account. Tell us right away at {email} if you think someone else '
        'has used it.',
  ),
  (
    heading: '3. Farmer data',
    body:
        "The panel shows farmers' personal data: names, email addresses, "
        'mobile numbers, pond locations and water readings. You may use it only '
        'to monitor ponds and devices and to support those farmers. You must '
        'not:\n'
        '• copy, export, share or sell it, or use it for marketing;\n'
        '• contact farmers for reasons unrelated to IsdaSafe;\n'
        '• look up people or ponds without a work reason.\n'
        'Handle it as personal information under the Data Privacy Act. Report '
        'any suspected leak or misuse to {email} immediately.',
  ),
  (
    heading: '4. Approving admins',
    body:
        'Only approve people you know are authorised. Approving someone gives '
        'them the same access to farmer data that you have.',
  ),
  (
    heading: '5. Readings and statuses',
    body:
        'Readings come from field sensors that can drift, fail or go offline, '
        'and water statuses are calculated automatically. They are a '
        'monitoring aid, not a guarantee of water quality.',
  ),
  (
    heading: '6. Availability',
    body:
        'We work to keep the panel running but do not guarantee it is always '
        'available or error-free, and we may change or suspend it.',
  ),
  (
    heading: '7. Ending access',
    body:
        'You can leave at any time in Settings > Leave admin access. We may '
        'remove access that breaks these terms. Your duty to keep farmer data '
        'confidential continues after your access ends.',
  ),
  (
    heading: '8. Governing law and contact',
    body:
        'These terms are governed by the laws of the Republic of the '
        'Philippines. Questions can be sent to {email}.',
  ),
];
