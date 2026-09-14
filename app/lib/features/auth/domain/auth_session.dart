import 'package:flutter/foundation.dart';

import '../../../shared/models/models.dart';

/// The signed-in V2EX session.
///
/// The session cookie itself lives in the `cookie_jar` (persisted through
/// `SecureCookieStorage`); this object only carries the profile bits the UI
/// needs plus the sign-in timestamp used for diagnostics.
@immutable
class AuthSession {
  const AuthSession({
    this.user,
    this.notifications,
    this.moneyGold,
    this.moneySilver,
    this.moneyBronze,
    this.signedInAt,
  });

  const AuthSession.signedOut() : this();

  final V2User? user;

  /// Unread notification count from the right sidebar (`docs/12` §UserInfo).
  final String? notifications;
  final String? moneyGold;
  final String? moneySilver;
  final String? moneyBronze;
  final DateTime? signedInAt;

  bool get isSignedIn => user != null;

  String? get username => user?.username;

  int? get memberId => user?.id;

  /// Digits of [notifications] — V2EX renders the unread count inside the
  /// sidebar's notification link. `null` when the sidebar did not carry one.
  int? get unreadCount {
    final raw = notifications;
    if (raw == null) return null;
    final match = RegExp(r'\d+').firstMatch(raw);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  AuthSession copyWith({
    V2User? user,
    String? notifications,
    String? moneyGold,
    String? moneySilver,
    String? moneyBronze,
    DateTime? signedInAt,
  }) {
    return AuthSession(
      user: user ?? this.user,
      notifications: notifications ?? this.notifications,
      moneyGold: moneyGold ?? this.moneyGold,
      moneySilver: moneySilver ?? this.moneySilver,
      moneyBronze: moneyBronze ?? this.moneyBronze,
      signedInAt: signedInAt ?? this.signedInAt,
    );
  }

  /// Persisted form. Deliberately tiny — no credentials, no cookies.
  Map<String, String> toStorage() => <String, String>{
    if (user != null) 'username': user!.username,
    if (user?.id != null) 'memberId': '${user!.id}',
    if (user?.avatarUrl != null) 'avatar': user!.avatarUrl!,
    if (signedInAt != null) 'signedInAt': signedInAt!.toIso8601String(),
  };

  static AuthSession? fromStorage(Map<String, String?> raw) {
    final username = raw['username'];
    if (username == null || username.isEmpty) return null;
    return AuthSession(
      user: V2User(
        username: username,
        id: int.tryParse(raw['memberId'] ?? ''),
        avatarUrl: raw['avatar'],
      ),
      signedInAt: DateTime.tryParse(raw['signedInAt'] ?? ''),
    );
  }
}

/// Why the session ended, so the UI can explain it instead of silently
/// switching to the signed-out shell.
enum SignOutReason { userInitiated, sessionExpired }
