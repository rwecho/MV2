import 'package:flutter_test/flutter_test.dart';
import 'package:mv2/core/deeplink/deep_link.dart';

/// `docs/02` §Deep Link: Topic / Node / Member links must resolve to app routes.
void main() {
  group('Mv2DeepLink.routeFor — mv2:// scheme', () {
    test('topic', () {
      expect(Mv2DeepLink.routeFor('mv2://topic/123'), '/topic/123');
      expect(Mv2DeepLink.routeFor('mv2://t/123'), '/topic/123');
      // `mv2:///topic/123` leaves the host empty.
      expect(Mv2DeepLink.routeFor('mv2:///topic/123'), '/topic/123');
    });

    test('node and member', () {
      expect(Mv2DeepLink.routeFor('mv2://node/python'), '/node/python');
      expect(Mv2DeepLink.routeFor('mv2://go/python'), '/node/python');
      expect(Mv2DeepLink.routeFor('mv2://member/livid'), '/member/livid');
    });

    test('rejects unknown or incomplete targets', () {
      expect(Mv2DeepLink.routeFor('mv2://nope/1'), isNull);
      expect(Mv2DeepLink.routeFor('mv2://topic'), isNull);
      expect(Mv2DeepLink.routeFor('mv2://'), isNull);
    });
  });

  group('Mv2DeepLink.routeFor — v2ex.com web links', () {
    test('topic, including the #replyN floor fragment', () {
      expect(
        Mv2DeepLink.routeFor('https://www.v2ex.com/t/1231200'),
        '/topic/1231200',
      );
      expect(
        Mv2DeepLink.routeFor('https://www.v2ex.com/t/123#reply4'),
        '/topic/123?floor=4',
      );
      expect(Mv2DeepLink.routeFor('https://v2ex.com/t/123'), '/topic/123');
    });

    test('node and member', () {
      expect(
        Mv2DeepLink.routeFor('https://www.v2ex.com/go/python'),
        '/node/python',
      );
      expect(
        Mv2DeepLink.routeFor('https://www.v2ex.com/member/livid'),
        '/member/livid',
      );
    });

    test('ignores other hosts and non-content paths', () {
      expect(Mv2DeepLink.routeFor('https://example.com/t/123'), isNull);
      expect(Mv2DeepLink.routeFor('https://www.v2ex.com/'), isNull);
      expect(Mv2DeepLink.routeFor('https://www.v2ex.com/about'), isNull);
      expect(Mv2DeepLink.routeFor('https://www.v2ex.com/t/abc'), isNull);
    });
  });

  group('shared text', () {
    test('finds the URL inside a sentence', () {
      expect(
        Mv2DeepLink.urlIn('看看这个 https://www.v2ex.com/t/123 挺有意思'),
        'https://www.v2ex.com/t/123',
      );
      expect(
        Mv2DeepLink.routeFor('看看这个 https://www.v2ex.com/t/123 挺有意思'),
        '/topic/123',
      );
    });

    test('returns null when there is no link', () {
      expect(Mv2DeepLink.urlIn('没有链接'), isNull);
      expect(Mv2DeepLink.routeFor('没有链接'), isNull);
      expect(Mv2DeepLink.routeFor(null), isNull);
      expect(Mv2DeepLink.urlIn(''), isNull);
    });
  });
}
