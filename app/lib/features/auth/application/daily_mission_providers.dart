import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../shared/models/daily_mission.dart';
import 'auth_controller.dart';

/// `/mission/daily` state (每日签到).
///
/// Anonymous sessions get an "unavailable" mission without any network call —
/// `/mission/daily` is login-only and would otherwise answer `302 → /signin`.
final dailyMissionProvider = FutureProvider<V2DailyMission>((ref) {
  if (!ref.watch(isSignedInProvider)) {
    return const V2DailyMission();
  }
  return ref.watch(v2exApiProvider).dailyMission();
});

/// Claims the daily bonus and refreshes [dailyMissionProvider].
class CheckInController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Throws on failure so the caller can surface the outcome; errors are also
  /// kept in [state] for widgets that prefer to watch.
  Future<void> checkIn() async {
    state = const AsyncLoading<void>();
    try {
      await ref.read(v2exApiProvider).checkIn();
      ref.invalidate(dailyMissionProvider);
      state = const AsyncData<void>(null);
    } catch (error, stackTrace) {
      state = AsyncError<void>(error, stackTrace);
      rethrow;
    }
  }
}

final checkInProvider = AsyncNotifierProvider<CheckInController, void>(
  CheckInController.new,
);
