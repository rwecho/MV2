import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/data/home_tab.dart';
import 'package:mv2/core/data/v2ex_providers.dart';
import 'package:mv2/core/network/mv2_http_client.dart';
import 'package:mv2/features/blocked/application/blocked_users_controller.dart';
import 'package:mv2/features/feed/application/feed_providers.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/shared/models/node_visuals.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fixture_api.dart';

V2Topic _topic(String author) => V2Topic(
  id: author.hashCode,
  node: NodeVisuals.node(key: 'qna', name: '问与答'),
  title: '标题 $author',
  author: V2User(username: author),
  createdAtLabel: '1 小时前',
  replyCount: 0,
);

class _FeedApi extends FixtureV2exApi {
  _FeedApi() : super(latency: Duration.zero);

  @override
  Future<List<V2Topic>> feed(
    HomeTab tab, {
    PacePriority priority = PacePriority.userRead,
  }) async => <V2Topic>[
    _topic('livid'),
    _topic('kernel'),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the feed hides a blocked author, and restores them on unblock', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer(
      overrides: [v2exApiProvider.overrideWithValue(_FeedApi())],
    );
    addTearDown(container.dispose);

    // Baseline: nothing blocked.
    expect(
      (await container.read(feedProvider(HomeTab.tech).future))
          .map((V2Topic topic) => topic.author.username),
      <String>['livid', 'kernel'],
    );

    await container.read(blockedUsersProvider.notifier).block('livid');

    expect(
      (await container.read(feedProvider(HomeTab.tech).future))
          .map((V2Topic topic) => topic.author.username),
      <String>['kernel'],
    );

    await container.read(blockedUsersProvider.notifier).unblock('livid');

    expect(
      (await container.read(feedProvider(HomeTab.tech).future))
          .map((V2Topic topic) => topic.author.username),
      <String>['livid', 'kernel'],
    );
  });
}
