import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/network/mv2_http_client.dart';
import 'package:mv2/design_system/theme/mv2_theme.dart';
import 'package:mv2/features/auth/application/auth_controller.dart';
import 'package:mv2/features/my/application/my_providers.dart';
import 'package:mv2/features/my/data/my_api.dart';
import 'package:mv2/features/my/presentation/my_nodes_page.dart';
import 'package:mv2/features/my/presentation/my_topic_list_page.dart';

/// Renders the final 我的 pages against the **real captured** page HTML.
///
/// These are the widget-level counterpart to the on-device Maestro checks: they
/// pin the exact strings the 我的节点 / 主题 rows must show (node name without the
/// trailing counter, `N 主题` on the right).
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

class _FakeClient extends Mv2HttpClient {
  _FakeClient(this.body) : super(Dio(), CookieJar());

  final String body;

  @override
  Future<HttpResult> get(
    String path, {
    Map<String, dynamic>? query,
    String? referer,
    String? baseUrl,
  }) async => HttpResult(
    statusCode: 200,
    body: body,
    headers: const <String, List<String>>{},
  );
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget home,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: Mv2ThemeData.light(), home: home),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('我的节点 renders node name + 主题 count from real /my/nodes', (
    tester,
  ) async {
    final nodes = await MyApi(_FakeClient(fixture('my_nodes_real.html')))
        .favoriteNodes();

    final container = ProviderContainer(
      overrides: [
        isSignedInProvider.overrideWith((ref) => true),
        favoriteNodesProvider.overrideWith((ref) => nodes),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container, const MyNodesPage());

    // Name and count are separate cells — the anchor's raw text `V2EX 4166`
    // must never be rendered as the name.
    expect(find.text('V2EX'), findsOneWidget);
    expect(find.text('4.2k 主题'), findsOneWidget);
    expect(find.text('V2EX 4166'), findsNothing);
    expect(find.text('沙盒'), findsOneWidget);
    expect(find.text('2.3k 主题'), findsOneWidget);
    expect(find.text('VPS'), findsOneWidget);
    expect(find.text('8.3k 主题'), findsOneWidget);
  });

  testWidgets('我的主题 renders real topic rows', (tester) async {
    final page = await MyApi(
      _FakeClient(fixture('my_member_topics_real.html')),
      username: 'rwecho',
    ).myTopics();

    final container = ProviderContainer(
      overrides: [
        isSignedInProvider.overrideWith((ref) => true),
        myTopicsProvider.overrideWith((ref) => page),
      ],
    );
    addTearDown(container.dispose);

    await _pump(
      tester,
      container,
      const MyTopicListPage(kind: MyListKind.topics),
    );

    expect(find.text('我的主题'), findsOneWidget);
    expect(find.text('deepseek harness 手机端，各位有什么建议吗？'), findsOneWidget);
    expect(find.text('上架的过程中发现，华为是目前最友好的应用商城'), findsOneWidget);
  });

  testWidgets('我的回复 renders the real dock_area rows', (tester) async {
    final page = await MyApi(
      _FakeClient(fixture('my_replies_real.html')),
      username: 'rwecho',
    ).myReplies();

    final container = ProviderContainer(
      overrides: [
        isSignedInProvider.overrideWith((ref) => true),
        myRepliesProvider.overrideWith((ref) => page),
      ],
    );
    addTearDown(container.dispose);

    await _pump(
      tester,
      container,
      const MyTopicListPage(kind: MyListKind.replies),
    );

    expect(find.text('我的回复'), findsOneWidget);
    expect(find.textContaining('做了 iOS / Android / 鸿蒙三端'), findsOneWidget);
  });

  testWidgets('signed out shows the 登录后查看 state on every list', (tester) async {
    final container = ProviderContainer(
      overrides: [isSignedInProvider.overrideWith((ref) => false)],
    );
    addTearDown(container.dispose);

    await _pump(
      tester,
      container,
      const MyTopicListPage(kind: MyListKind.favorites),
    );
    expect(find.text('登录后查看'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
  });
}
