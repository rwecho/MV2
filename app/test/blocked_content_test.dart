import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/features/blocked/application/blocked_content.dart';
import 'package:mv2/shared/models/models.dart';
import 'package:mv2/shared/models/node_visuals.dart';

V2Topic _topic(String author) => V2Topic(
  id: author.hashCode,
  node: NodeVisuals.node(key: 'qna', name: '问与答'),
  title: '标题 $author',
  author: V2User(username: author),
  createdAtLabel: '1 小时前',
  replyCount: 0,
);

V2Reply _reply(String author, {int floor = 1}) => V2Reply(
  floor: floor,
  author: V2User(username: author),
  content: '回复 $author',
  createdAtLabel: '1 小时前',
);

V2Notification _notification(String actor, String id) => V2Notification(
  id: id,
  kind: NotificationKind.reply,
  actor: V2User(username: actor),
  timeLabel: '1 小时前',
  quote: '引用 $actor',
  sourceTitle: '主题',
);

void main() {
  group('BlockedContent', () {
    test('hides nothing when the block list is empty', () {
      final topics = <V2Topic>[_topic('livid'), _topic('kernel')];
      expect(BlockedContent.topics(<String>{}, topics), topics);
      expect(BlockedContent.topics(<String>{}, topics), same(topics));
    });

    test('drops topics from blocked authors only', () {
      final filtered = BlockedContent.topics(<String>{'livid'}, <V2Topic>[
        _topic('livid'),
        _topic('kernel'),
      ]);
      expect(filtered.map((t) => t.author.username), <String>['kernel']);
    });

    test('drops replies from blocked authors', () {
      final filtered = BlockedContent.replies(<String>{'spam'}, <V2Reply>[
        _reply('spam'),
        _reply('kernel', floor: 2),
      ]);
      expect(filtered.map((r) => r.author.username), <String>['kernel']);
    });

    test('drops blocked rows and the day section they emptied', () {
      final groups = BlockedContent.notificationGroups(<String>{'spam'}, [
        V2NotificationGroup(
          title: '今天',
          items: [_notification('spam', '1'), _notification('kernel', '2')],
        ),
        V2NotificationGroup(title: '更早', items: [_notification('spam', '3')]),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.title, '今天');
      expect(groups.single.items.single.actor.username, 'kernel');
    });

    test('an unknown author is never treated as blocked', () {
      expect(BlockedContent.hides(<String>{'livid'}, null), isFalse);
      expect(BlockedContent.hides(<String>{'livid'}, 'kernel'), isFalse);
      expect(BlockedContent.hides(<String>{'livid'}, 'livid'), isTrue);
    });
  });
}
