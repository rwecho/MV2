import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/features/settings/application/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认回复排序 persists to mv2.replySort and hydrates back', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final first = ProviderContainer();
    await first.read(settingsProvider.notifier).setReplySort(Mv2ReplySort.likes);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mv2.replySort'), 'likes');

    await Future<void>.delayed(const Duration(milliseconds: 20));
    first.dispose();

    final second = ProviderContainer();
    for (var i = 0; i < 50; i++) {
      if (second.read(settingsProvider).replySort == Mv2ReplySort.likes) break;
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(second.read(settingsProvider).replySort, Mv2ReplySort.likes);
    second.dispose();
  });

  test('a change made before hydration wins over the stored value', () async {
    // Storage says 热度; the user picks 时间 before it answers. The late
    // hydration must not silently revert them.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mv2.replySort': 'likes',
    });
    final container = ProviderContainer();

    unawaited(
      container
          .read(settingsProvider.notifier)
          .setReplySort(Mv2ReplySort.time),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(container.read(settingsProvider).replySort, Mv2ReplySort.time);
    container.dispose();
  });

  test('内容宽度 persists so the reading column keeps its cap', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();

    await container
        .read(settingsProvider.notifier)
        .setContentWidth(Mv2ContentWidth.wide);

    expect(container.read(settingsProvider).contentWidth.maxWidth, 760);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mv2.contentWidth'), 'wide');

    await Future<void>.delayed(const Duration(milliseconds: 20));
    container.dispose();
  });
}
