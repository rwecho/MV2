import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/push/push_payload.dart';

/// `Mv2PushPayload` is the only thing standing between an FCM `data` map and
/// "does tapping the push open the right topic" — the worker always sends
/// `link`, and only sometimes `topicId`.
void main() {
  group('Mv2PushPayload.routeFor', () {
    test('prefers the explicit topicId', () {
      expect(
        Mv2PushPayload.routeFor(<String, Object?>{
          'topicId': '1241200',
          'link': 'https://www.v2ex.com/t/1241200',
        }),
        '/topic/1241200',
      );
    });

    test('still lands on the reply when the link carries a floor', () {
      expect(
        Mv2PushPayload.routeFor(<String, Object?>{
          'topicId': '1241200',
          'link': 'https://www.v2ex.com/t/1241200#reply20',
        }),
        '/topic/1241200?floor=20',
      );
    });

    test('keeps the reply floor from a `#replyN` fragment', () {
      expect(
        Mv2PushPayload.routeFor(<String, Object?>{
          'link': 'https://www.v2ex.com/t/1241200#reply20',
        }),
        '/topic/1241200?floor=20',
      );
    });

    test('handles the worker\'s relative links', () {
      expect(
        Mv2PushPayload.routeFor(<String, Object?>{
          'link': '/t/123?p=1#reply7',
        }),
        '/topic/123?floor=7',
      );
    });

    test('falls back to the deep-link parser for non-topic links', () {
      expect(
        Mv2PushPayload.routeFor(<String, Object?>{'link': '/go/python'}),
        '/node/python',
      );
      expect(
        Mv2PushPayload.routeFor(<String, Object?>{'link': '/member/livid'}),
        '/member/livid',
      );
    });

    test('returns null when there is nothing to open', () {
      expect(Mv2PushPayload.routeFor(<String, Object?>{}), isNull);
      expect(Mv2PushPayload.routeFor(<String, Object?>{'link': '  '}), isNull);
      expect(
        Mv2PushPayload.routeFor(<String, Object?>{'link': 'not a link'}),
        isNull,
      );
    });

    test('ignores a non-numeric topicId and parses the link instead', () {
      expect(
        Mv2PushPayload.routeFor(<String, Object?>{
          'topicId': 'abc',
          'link': '/t/99#reply1',
        }),
        '/topic/99?floor=1',
      );
    });
  });
}
