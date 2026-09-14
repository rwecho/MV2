import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/session_once.dart';
import '../../../core/data/v2ex_providers.dart';
import '../data/auth_store.dart';
import '../domain/auth_session.dart';

/// Secure-storage backed session metadata (the cookie itself lives in the
/// `cookie_jar`, persisted by `SecureCookieStorage`).
final authStoreProvider = Provider<AuthStore>((ref) => AuthStore());

/// The signed-in session; `null` data means "signed out".
///
/// Loading state is meaningful: the UI shows the signed-out shell only after
/// storage has answered, so a restart does not flash the login CTA.
class AuthController extends AsyncNotifier<AuthSession> {
  static const String _origin = 'https://www.v2ex.com/';

  /// Set when the session ended for a reason the UI should surface.
  SignOutReason? lastSignOutReason;

  @override
  Future<AuthSession> build() async {
    final stored = await ref.read(authStoreProvider).read();
    return stored ?? const AuthSession.signedOut();
  }

  /// Called by the WebView login page once the site issued a session cookie.
  ///
  /// Cookies are copied into the Dio jar and the account is validated by
  /// fetching the home page — that way a half-finished login (e.g. the user
  /// closed the sheet before 2FA) never reports success.
  Future<void> signInWithCookies(Iterable<Cookie> cookies) async {
    state = const AsyncLoading<AuthSession>();
    final client = ref.read(httpClientProvider);
    for (final cookie in cookies) {
      await client.seedCookie(_origin, cookie);
    }
    await refreshAccount();
  }

  /// Re-reads the account from V2EX; signs out when the session is gone.
  Future<void> refreshAccount() async {
    try {
      final info = await ref.read(v2exApiProvider).currentUser();
      if (info == null) {
        await signOut(reason: SignOutReason.sessionExpired);
        return;
      }
      final session = AuthSession(
        user: info.user,
        notifications: info.notifications,
        moneyGold: info.moneyGold,
        moneySilver: info.moneySilver,
        moneyBronze: info.moneyBronze,
        signedInAt: DateTime.now(),
      );
      await ref.read(authStoreProvider).write(session);
      lastSignOutReason = null;
      state = AsyncData(session);
    } catch (error, stackTrace) {
      // Keep whatever we already had: a transient network error must not sign
      // the user out.
      if (state.hasValue && state.value!.isSignedIn) {
        state = AsyncData(state.value!);
        return;
      }
      state = AsyncError<AuthSession>(error, stackTrace);
    }
  }

  /// Clears the cookie jar (and therefore the server session on this device)
  /// and forgets the account.
  Future<void> signOut({
    SignOutReason reason = SignOutReason.userInitiated,
  }) async {
    await ref.read(httpClientProvider).clearCookies();
    await ref.read(authStoreProvider).clear();
    // The rotated `once` belongs to the old session; never reuse it.
    ref.read(sessionOnceProvider.notifier).reset();
    lastSignOutReason = reason;
    state = const AsyncData(AuthSession.signedOut());
  }

  /// Called by repositories when V2EX answers 401/403 mid-session.
  Future<void> handleAuthFailure() async {
    if (!(state.value?.isSignedIn ?? false)) return;
    await signOut(reason: SignOutReason.sessionExpired);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession>(AuthController.new);

/// Convenience selectors used by pages.
final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider).value?.isSignedIn ?? false,
);

final currentUsernameProvider = Provider<String?>(
  (ref) => ref.watch(authControllerProvider).value?.username,
);
