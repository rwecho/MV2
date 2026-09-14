import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/features/auth/application/auth_controller.dart';
import 'package:mv2/features/auth/domain/auth_session.dart';
import 'package:mv2/features/notifications/application/notifications_providers.dart';

/// The tab-bar badge must show the real unread count scraped from the home
/// page sidebar — not a hardcoded number.
class _FakeAuth extends AuthController {
  _FakeAuth(this.session);

  final AuthSession session;

  @override
  Future<AuthSession> build() async => session;
}

void main() {
  group('AuthSession.unreadCount', () {
    test('extracts the digits from the sidebar text', () {
      expect(const AuthSession(notifications: '3').unreadCount, 3);
      expect(const AuthSession(notifications: '3 条未读提醒').unreadCount, 3);
      expect(const AuthSession(notifications: '12').unreadCount, 12);
    });

    test('is null when the sidebar carried no count', () {
      expect(const AuthSession(notifications: '提醒').unreadCount, isNull);
      expect(const AuthSession().unreadCount, isNull);
    });
  });

  test('the badge mirrors the session count', () async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FakeAuth(const AuthSession(notifications: '5')),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    expect(container.read(notificationUnreadProvider), 5);
  });

  test('the badge is 0 while signed out', () async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FakeAuth(const AuthSession.signedOut()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    expect(container.read(notificationUnreadProvider), 0);
  });
}
