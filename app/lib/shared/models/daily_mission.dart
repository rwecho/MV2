import 'package:flutter/foundation.dart';

/// `/mission/daily` scraping result (`docs/12` §2.2).
@immutable
class V2DailyMission {
  const V2DailyMission({
    this.continuousDaysLabel,
    this.redeemPath,
    this.alreadyCheckedIn = false,
  });

  /// e.g. `已连续登录 12 天`.
  final String? continuousDaysLabel;

  /// `/mission/daily/redeem?once=...`; `null` once the bonus was claimed.
  final String? redeemPath;

  final bool alreadyCheckedIn;
}
