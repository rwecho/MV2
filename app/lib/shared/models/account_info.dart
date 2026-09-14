import 'package:flutter/foundation.dart';

import 'models.dart';

/// The signed-in account as scraped from the V2EX home page's right sidebar.
///
/// There is no JSON endpoint for "who am I" without a Personal Access Token, so
/// this comes from `#Rightbar` on a session-cookie page (`docs/12` §UserInfo).
@immutable
class V2AccountInfo {
  const V2AccountInfo({
    required this.user,
    this.notifications,
    this.moneyGold,
    this.moneySilver,
    this.moneyBronze,
  });

  final V2User user;
  final String? notifications;
  final String? moneyGold;
  final String? moneySilver;
  final String? moneyBronze;
}
