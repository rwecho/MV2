import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/telemetry/mv2_telemetry.dart';

/// Firebase is not registered in `flutter test`, so booting telemetry exercises
/// the "no config" branch. What matters is that it degrades quietly and never
/// becomes a crash source itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start() degrades quietly when Firebase is unavailable', () async {
    await Mv2Telemetry.start();

    expect(Mv2Telemetry.isReady, isFalse);
  });

  test('recording a non-fatal is a no-op while telemetry is off', () {
    expect(
      () => Mv2Telemetry.recordNonFatal(
        StateError('boom'),
        StackTrace.current,
        reason: 'test',
      ),
      returnsNormally,
    );
  });
}
