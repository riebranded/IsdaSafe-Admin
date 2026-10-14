import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where an admin account stands, from its `public.admins` row.
enum AdminStatus {
  approved,
  pending,
  rejected,

  /// Signed in, but the account has no admin row — a farmer account from the
  /// IsdaSafe app.
  notAdmin,
}

class AdminProfile {
  const AdminProfile({
    required this.userId,
    required this.fullName,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.phoneVerified,
    required this.status,
    required this.createdAt,
  });

  factory AdminProfile.fromRow(Map<String, dynamic> row) => AdminProfile(
    userId: row['user_id'] as String,
    fullName: row['full_name'] as String,
    firstName: row['first_name'] as String?,
    lastName: row['last_name'] as String?,
    email: row['email'] as String,
    phone: row['phone'] as String?,
    phoneVerified: row['phone_verified'] as bool? ?? false,
    status: switch (row['status']) {
      'approved' => AdminStatus.approved,
      'rejected' => AdminStatus.rejected,
      _ => AdminStatus.pending,
    },
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
  );

  final String userId;
  final String fullName;

  /// Null for admins from before first/last names were asked; AdminGate
  /// asks them at their next login.
  final String? firstName;
  final String? lastName;

  bool get hasFirstAndLastName =>
      (firstName?.trim().isNotEmpty ?? false) &&
      (lastName?.trim().isNotEmpty ?? false);
  final String email;

  /// E.164 mobile number for OTP codes. Kept on the admin row rather than
  /// `auth.users.phone`, so it may match a farmer account's number.
  final String? phone;
  final bool phoneVerified;
  final AdminStatus status;
  final DateTime createdAt;
}

/// Admin sign-in/sign-up against the same Supabase project as the farmer
/// app. Being signed in isn't enough to use the panel: the account also
/// needs an approved `public.admins` row (see
/// supabase/migrations/20261013120000_admin_panel.sql).
class AdminAuthService {
  const AdminAuthService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static GoTrueClient get _auth => _client.auth;

  static Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;
  static Session? get currentSession => _auth.currentSession;
  static User? get currentUser => _auth.currentUser;

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
    required String captchaToken,
  }) {
    return _auth.signInWithPassword(
      email: email,
      password: password,
      captchaToken: captchaToken,
    );
  }

  /// Creates the account; the database turns it into a pending admin request
  /// because of `admin_signup` (the very first admin is approved outright).
  static Future<AuthResponse> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String phone,
    required String captchaToken,
  }) {
    return _auth.signUp(
      email: email,
      password: password,
      captchaToken: captchaToken,
      data: {
        'first_name': firstName,
        'last_name': lastName,
        'full_name': '$firstName $lastName',
        'admin_signup': true,
        'admin_phone': phone,
      },
    );
  }

  /// Google sign-in is offered on web (Supabase OAuth redirect) and Android
  /// (native account picker). The plugin has no Windows/Linux support, and
  /// iOS would need its own OAuth client.
  static bool get isGoogleSignInSupported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  static var _googleInitialized = false;

  /// Signs in (or up) with Google. A first-time Google account has no admin
  /// row yet; AdminGate then offers [requestAdminAccess].
  ///
  /// Returns false when the user backs out of Google's account picker.
  static Future<bool> signInWithGoogle() async {
    if (kIsWeb) {
      // Redirects back to this page, which must be in Supabase's
      // Authentication → URL Configuration → Redirect URLs allow-list
      // (`http://localhost:*` covers every dev port).
      await _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Uri.base.removeFragment().toString(),
        queryParams: {'prompt': 'select_account'},
      );
      return true;
    }

    final googleSignIn = GoogleSignIn.instance;
    if (!_googleInitialized) {
      final serverClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
      await googleSignIn.initialize(
        serverClientId: serverClientId.isEmpty ? null : serverClientId,
      );
      _googleInitialized = true;
    }

    final GoogleSignInAccount googleUser;
    try {
      googleUser = await googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }

    const scopes = ['email', 'profile'];
    final authorization =
        await googleUser.authorizationClient.authorizationForScopes(scopes) ??
        await googleUser.authorizationClient.authorizeScopes(scopes);
    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('No ID token returned by Google.');
    }
    await _auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: authorization.accessToken,
    );
    return true;
  }

  /// Files an admin request for the signed-in account (one that has no
  /// admin row, e.g. a first-time Google sign-in), with the [phone] its OTP
  /// codes go to (verified next, by AdminGate). Returns the new status.
  static Future<AdminStatus> requestAdminAccess({
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    final status = await _client.rpc(
      'request_admin_access',
      params: {
        'p_first_name': firstName,
        'p_last_name': lastName,
        'p_phone': phone,
      },
    );
    return status == 'approved' ? AdminStatus.approved : AdminStatus.pending;
  }

  /// Name from the signed-in account's metadata (Google fills `full_name`).
  static String get currentUserName {
    final meta = currentUser?.userMetadata;
    return (meta?['full_name'] as String?) ?? (meta?['name'] as String?) ?? '';
  }

  /// Emails a password-reset code (the shared IsdaSafe "Reset password"
  /// template includes `{{ .Token }}`). On web the email's link also leads
  /// back to this page.
  static Future<void> sendPasswordResetCode(
    String email, {
    required String captchaToken,
  }) {
    return _auth.resetPasswordForEmail(
      email,
      captchaToken: captchaToken,
      redirectTo: kIsWeb ? Uri.base.removeFragment().toString() : null,
    );
  }

  /// Checks the code from the reset email. On success Supabase opens a
  /// recovery session and emits `passwordRecovery`, which
  /// [listenForPasswordRecovery] turns into the set-new-password screen.
  static Future<void> verifyRecoveryCode(String email, String code) async {
    await _auth.verifyOTP(email: email, token: code, type: OtpType.recovery);
  }

  /// True from the moment a recovery session opens until the new password is
  /// saved (or the reset is cancelled); AdminGate shows the set-new-password
  /// screen meanwhile instead of the dashboard. Call
  /// [listenForPasswordRecovery] once at startup.
  static final ValueNotifier<bool> recoveryPending = ValueNotifier(false);

  static void listenForPasswordRecovery() {
    onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        recoveryPending.value = true;
      }
    });
    // The event can fire while Supabase initialises, before anything
    // listens — on web the reset link's own URL still says what it was.
    if (kIsWeb) {
      final base = Uri.base;
      if (base.fragment.contains('type=recovery') ||
          base.queryParameters['type'] == 'recovery') {
        recoveryPending.value = true;
      }
    }
  }

  /// Sets a new password. Outside a fresh sign-in Supabase may refuse with
  /// [needsReauthentication]; call [sendReauthenticationCode] and retry with
  /// the emailed [nonce].
  static Future<void> updatePassword(String password, {String? nonce}) =>
      _auth.updateUser(UserAttributes(password: password, nonce: nonce));

  static bool needsReauthentication(AuthException e) =>
      e.code == 'reauthentication_needed' ||
      e.message.toLowerCase().contains('reauthentication');

  static Future<void> sendReauthenticationCode() => _auth.reauthenticate();

  /// Whether the account can sign in with a password (as opposed to Google
  /// only), i.e. whether "Change password" makes sense for it.
  static bool get hasPasswordLogin {
    final providers = currentUser?.appMetadata['providers'];
    if (providers is List && providers.isNotEmpty) {
      return providers.contains('email');
    }
    return currentUser?.appMetadata['provider'] != 'google';
  }

  /// Saves [phone] as the signed-in admin's (unverified) number and texts it
  /// a code. Fails if another verified admin has the number; a farmer
  /// account with it is fine. The SMS goes through the farmer app's
  /// `send-semaphore-otp` Edge Function, which only stores the hashed code.
  static Future<void> sendPhoneOtp(String phone) async {
    await _client.rpc('admin_set_own_phone', params: {'p_phone': phone});
    try {
      await _client.functions.invoke(
        'send-semaphore-otp',
        body: {'phone': phone},
      );
    } on FunctionException catch (e) {
      debugPrint(
        'AdminAuthService: send-semaphore-otp ${e.status} ${e.details}',
      );
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      throw AuthException(message ?? 'Couldn\'t send the code. Try again.');
    }
  }

  /// Checks the texted code and marks the admin's number verified. Unlike
  /// the farmer app's `verify-semaphore-otp`, this never touches
  /// `auth.users.phone`.
  static Future<void> verifyPhoneOtp(String code) async {
    final error = await _client.rpc(
      'admin_verify_phone_otp',
      params: {'p_code': code},
    );
    if (error is String) throw AuthException(error);
  }

  /// The signed-in admin's own row (null if it has none).
  static Future<AdminProfile?> fetchOwnProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final row = await _client
        .from('admins')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();
    final profile = row == null ? null : AdminProfile.fromRow(row);
    ownProfile.value = profile;
    return profile;
  }

  /// The signed-in admin's row as last fetched by [fetchOwnProfile] (AdminGate
  /// fetches it at login, Settings after a rename), for the sidebar and the
  /// greeting to follow.
  static final ValueNotifier<AdminProfile?> ownProfile = ValueNotifier(null);

  /// The signed-in admin's first name ('' if unknown).
  static String get ownFirstName {
    final profile = ownProfile.value;
    if (profile == null) return '';
    final first = profile.firstName?.trim() ?? '';
    if (first.isNotEmpty) return first;
    return profile.fullName.contains('@')
        ? ''
        : profile.fullName.trim().split(RegExp(r'\s+')).first;
  }

  /// Sets the signed-in admin's first and last name (full_name follows).
  static Future<void> updateOwnName({
    required String firstName,
    required String lastName,
  }) => _client.rpc(
    'admin_set_own_name',
    params: {'p_first_name': firstName, 'p_last_name': lastName},
  );

  /// Gives up this account's admin access (deletes its `public.admins` row)
  /// and signs out. The login itself stays: it's shared with the farmer app.
  /// Fails for the last approved admin.
  static Future<void> leaveAdminAccess() async {
    await _client.rpc('admin_leave');
    await signOut();
  }

  static Future<void> signOut() async {
    recoveryPending.value = false;
    ownProfile.value = null;
    // Only initialized after a native Google sign-in; on web it would await
    // an initialize() that never comes.
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint('AdminAuthService: GoogleSignIn.signOut error $e');
      }
    }
    await _auth.signOut();
  }

  /// Every admin account and request, newest first (approved admins only).
  static Future<List<AdminProfile>> listAdmins() async {
    final rows = await _client.rpc('admin_list_admins') as List<dynamic>;
    return [
      for (final row in rows) AdminProfile.fromRow(row as Map<String, dynamic>),
    ];
  }

  static Future<void> setStatus(String userId, AdminStatus status) {
    assert(status == AdminStatus.approved || status == AdminStatus.rejected);
    return _client.rpc(
      'admin_set_status',
      params: {'p_user_id': userId, 'p_status': status.name},
    );
  }
}
