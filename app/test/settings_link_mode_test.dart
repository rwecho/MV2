import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/features/settings/application/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lets the controller's fire-and-forget `_hydrate()` settle before the
/// container is disposed; disposing mid-hydration trips Riverpod.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('外链打开方式 defaults to 阅读模式', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();

    expect(container.read(settingsProvider).openLinkMode, Mv2LinkOpenMode.reader);

    await _settle();
    container.dispose();
  });

  test('setOpenLinkMode persists to mv2.linkOpenMode', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();

    await container
        .read(settingsProvider.notifier)
        .setOpenLinkMode(Mv2LinkOpenMode.original);

    expect(
      container.read(settingsProvider).openLinkMode,
      Mv2LinkOpenMode.original,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mv2.linkOpenMode'), 'original');

    await _settle();
    container.dispose();
  });

  test('hydrates a persisted mv2.linkOpenMode value', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mv2.linkOpenMode': 'original',
    });
    final container = ProviderContainer();

    // Instantiating the notifier kicks off async hydration; wait for it.
    for (var i = 0; i < 50; i++) {
      if (container.read(settingsProvider).openLinkMode ==
          Mv2LinkOpenMode.original) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(
      container.read(settingsProvider).openLinkMode,
      Mv2LinkOpenMode.original,
    );

    await _settle();
    container.dispose();
  });

  test('an unknown persisted value falls back to 阅读模式', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mv2.linkOpenMode': 'bogus',
    });
    final container = ProviderContainer();

    container.read(settingsProvider);
    await _settle();
    expect(container.read(settingsProvider).openLinkMode, Mv2LinkOpenMode.reader);

    container.dispose();
  });
}
