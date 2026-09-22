import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/v2ex_api.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/topic/application/topic_providers.dart';
import 'package:mv2/features/topic/presentation/topic_detail_page.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/shared/models/topic_detail.dart';
import 'package:mv2/shared/models/write_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records 感谢 calls so the reply like button can be observed.
class _RecordingThanksApi extends FixtureV2exApi {
  _RecordingThanksApi() : super(latency: Duration.zero);

  final List<String> thanked = <String>[];

  @override
  Future<V2WriteResult> thankReply(String replyId, String once) async {
    thanked.add(replyId);
    return const V2WriteResult(success: true);
  }
}

/// Reading the replies down should dock the topic title into the top bar and
/// slide the floating reply bar away; scrolling back restores both.
void main() {
  /// Pumps the topic page and waits for the fixture to resolve.
  ///
  /// [signedIn] overrides the detail with a `once` token so write actions run
  /// (the bundled fixture is the anonymous page, which has none).
  Future<void> pumpTopic(
    WidgetTester tester, {
    V2exApi? api,
    bool signedIn = false,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final resolved = api ?? FixtureV2exApi(latency: Duration.zero);
    final container = ProviderContainer(
      overrides: [
        // Zero latency so pagination cannot leave a pending timer behind.
        v2exApiProvider.overrideWithValue(resolved),
        if (signedIn)
          topicDetailProvider.overrideWith(
            (ref, args) async =>
                (await resolved.topicDetail(args.topicId))
                    .copyWith(once: 'token'),
          ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: Mv2ThemeData.light(),
          home: const TopicDetailPage(topicId: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Scrolls the article until the 分享 action is on screen, then taps it.
  Future<void> tapShare(WidgetTester tester) async {
    final share = find.text('分享');
    await tester.scrollUntilVisible(
      share,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(share);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('reading down docks the title and hides the reply bar', (
    tester,
  ) async {
    // Short but wide viewport: scrollable without squeezing `_AuthorRow`.
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: Mv2ThemeData.light(),
          home: const TopicDetailPage(topicId: 1),
        ),
      ),
    );
    await tester.pump();
    // Fixture latency + skeleton.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final title = container
        .read(topicDetailProvider(const TopicDetailArgs(1)))
        .value!
        .topic
        .title;

    // The top-bar copy of the title is the one wrapped in an AnimatedOpacity;
    // the article renders the same string as a plain Text.
    final titleOpacity = find.ancestor(
      of: find.text(title),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(titleOpacity).opacity, 0);
    expect(
      tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
      Offset.zero,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.widget<AnimatedOpacity>(titleOpacity).opacity, 1);
    expect(
      tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
      isNot(Offset.zero),
    );

    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.widget<AnimatedOpacity>(titleOpacity).opacity, 0);
    expect(
      tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset,
      Offset.zero,
    );
  });

  testWidgets('long-pressing a reply opens 回复 / 复制 / 举报', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: Mv2ThemeData.light(),
          home: const TopicDetailPage(topicId: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // Bring the first reply into view (the article precedes it).
    final authors = find.text('@sentinelK');
    await tester.scrollUntilVisible(
      authors,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    await tester.longPress(authors.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('回复'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('举报'), findsOneWidget);
  });

  group('分享', () {
    const channel = MethodChannel('dev.fluttercommunity.plus/share');

    testWidgets('tapping 分享 invokes the platform share channel', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls.add(call);
            return 'success';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await pumpTopic(tester);
      await tapShare(tester);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'share');
      expect(
        calls.single.arguments['text'],
        contains('https://www.v2ex.com/t/1'),
      );
    });

    testWidgets('a failing share channel falls back to the clipboard', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            throw PlatformException(code: 'error', message: 'unavailable');
          });
      // The clipboard fallback writes through the platform channel.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (MethodCall call) async => null,
          );
      addTearDown(() {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await pumpTopic(tester);
      await tapShare(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('无法打开分享面板，链接已复制到剪贴板'), findsOneWidget);
    });
  });

  testWidgets('the reply row offers 感谢 / 引用 but no like', (tester) async {
    final api = _RecordingThanksApi();
    await pumpTopic(tester, api: api, signedIn: true);

    // Scroll the first reply into view.
    final author = find.text('@sentinelK');
    await tester.scrollUntilVisible(
      author,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    // V2EX has no reply like, so the dead 👍 was removed.
    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
    expect(find.byIcon(Icons.thumb_up_rounded), findsNothing);
    expect(find.text('感谢'), findsWidgets);
    expect(api.thanked, isEmpty);
  });

  testWidgets('tapping a #N reference jumps to that reply', (tester) async {
    tester.view.physicalSize = const Size(600, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final base = await FixtureV2exApi(latency: Duration.zero).topicDetail(1);
    // The last floor references floor 1 with the V2EX `@<a>user</a> #N` form.
    // Pinned to one page so scrolling never appends the fixture replies.
    final detail = base.copyWith(
      pagination: const V2Pagination(current: 1, maximum: 1),
      replies: <V2Reply>[
        for (var floor = 1; floor <= 30; floor++)
          V2Reply(
            id: 'r_$floor',
            floor: floor,
            author: V2User(username: floor == 1 ? 'sentinelK' : 'member$floor'),
            content: '第 $floor 楼的内容',
            contentHtml: floor == 30
                ? '@<a href="/member/sentinelK">sentinelK</a> #1 引用一下'
                : '<p>第 $floor 楼的内容</p>',
            createdAtLabel: '1 小时前',
          ),
      ],
    );

    final container = ProviderContainer(
      overrides: [
        v2exApiProvider.overrideWithValue(
          FixtureV2exApi(latency: Duration.zero),
        ),
        topicDetailProvider.overrideWith((ref, args) async => detail),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: Mv2ThemeData.light(),
          home: const TopicDetailPage(topicId: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final chip = find.text('#1');
    await tester.scrollUntilVisible(
      chip,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    final controller = tester
        .widget<ListView>(find.byType(ListView).first)
        .controller!;
    final before = controller.offset;
    expect(before, greaterThan(0));
    expect(find.text('@sentinelK'), findsNothing);

    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // Scrolled back up to floor 1, which is now on screen.
    expect(controller.offset, lessThan(before));
    expect(find.text('@sentinelK'), findsOneWidget);
  });

  testWidgets('initialFloor opens the topic at that reply', (tester) async {
    tester.view.physicalSize = const Size(600, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final base = await FixtureV2exApi(latency: Duration.zero).topicDetail(1);
    final detail = base.copyWith(
      pagination: const V2Pagination(current: 1, maximum: 1),
      replies: <V2Reply>[
        for (var floor = 1; floor <= 30; floor++)
          V2Reply(
            id: 'r_$floor',
            floor: floor,
            author: V2User(username: 'member$floor'),
            content: '第 $floor 楼的内容',
            contentHtml: '<p>第 $floor 楼的内容</p>',
            createdAtLabel: '1 小时前',
          ),
      ],
    );

    final container = ProviderContainer(
      overrides: [
        v2exApiProvider.overrideWithValue(
          FixtureV2exApi(latency: Duration.zero),
        ),
        topicDetailProvider.overrideWith((ref, args) async => detail),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: Mv2ThemeData.light(),
          // `/topic/1?floor=30` from a `#reply30` link.
          home: const TopicDetailPage(topicId: 1, initialFloor: 30),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    final controller = tester
        .widget<ListView>(find.byType(ListView).first)
        .controller!;
    expect(controller.offset, greaterThan(0));
    expect(find.text('@member30'), findsOneWidget);
  });

  group('mv2ReplyFloorPrefill', () {
    test('always seeds the @user #floor reference', () {
      // The mention is what fires V2EX's notification, so every reply opened
      // from a comment carries it — not just the ambiguous-author case.
      expect(mv2ReplyFloorPrefill(author: 'alice', floor: 1), '@alice #1 ');
      expect(mv2ReplyFloorPrefill(author: 'bob', floor: 33), '@bob #33 ');
    });

    test('anonymous replies seed the bare floor marker', () {
      expect(mv2ReplyFloorPrefill(author: '匿名', floor: 3), '#3 ');
      expect(mv2ReplyFloorPrefill(author: '', floor: 3), '#3 ');
    });
  });

  group('mv2ResolveMentionTarget', () {
    V2Reply reply(int floor, String author) => V2Reply(
      floor: floor,
      author: V2User(username: author),
      content: '内容',
      createdAtLabel: '1 小时前',
    );

    test('picks the nearest earlier reply by that member', () {
      final replies = <V2Reply>[
        reply(1, 'alice'),
        reply(2, 'bob'),
        reply(3, 'alice'),
        reply(4, 'carol'),
        reply(5, 'alice'),
      ];
      // From floor 6, alice's latest earlier reply is floor 5.
      expect(
        mv2ResolveMentionTarget(
          sourceFloor: 6,
          username: 'alice',
          replies: replies,
        )?.floor,
        5,
      );
      // From floor 3, only floors < 3 count → floor 1.
      expect(
        mv2ResolveMentionTarget(
          sourceFloor: 3,
          username: 'alice',
          replies: replies,
        )?.floor,
        1,
      );
      // A member who never replied earlier has no target.
      expect(
        mv2ResolveMentionTarget(
          sourceFloor: 6,
          username: 'dave',
          replies: replies,
        ),
        isNull,
      );
      // Self/forward references are not targets.
      expect(
        mv2ResolveMentionTarget(
          sourceFloor: 1,
          username: 'alice',
          replies: replies,
        ),
        isNull,
      );
    });
  });
}
