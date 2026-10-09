import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// `DuoLayout` decides which edge hosts the bar; the package keeps it internal
// (it is the rule our chrome depends on), so the test reaches into `src` on
// purpose rather than re-implementing the rule and testing the copy.
import 'package:adaptive_platform_ui/src/toolbar/duo_vertical_bar.dart'
    show DuoLayout;
import 'package:adaptive_platform_ui/src/platform/system_vertical_bar.dart'
    show SystemVerticalBarEdge;
import 'package:mv2/ui/components/adaptive/mv2_adaptive_destinations.dart';

/// The five destinations we hand to `adaptive_platform_ui`, and the rules that
/// decide what the bar shows where.
///
/// The bar itself is the package's (a native UITabBar on iOS 26+, its
/// Cupertino/Material fallbacks elsewhere, and the Duo's trailing capsule bar
/// from the fixed chrome), so what is worth pinning down here is our side of
/// the contract: the entries, their order, the badge, and the indices the
/// shell maps branches onto — 发布 is in the middle of the bar but is not a
/// branch.
void main() {
  group('destinations', () {
    test('ship the same five entries in bar order', () {
      final items = mv2AdaptiveDestinations(notificationUnread: 7);

      expect(items, hasLength(5));
      expect(
        items.map((AdaptiveNavigationDestination d) => d.label),
        <String>['首页', '节点', '发布', '通知', '我的'],
      );
      // On the test host (not iOS) the icons stay Material IconData, so a
      // lookup can never silently fall through to an empty SF Symbol string.
      for (final item in items) {
        expect(item.icon, isA<IconData>());
      }
    });

    test('carry the unread count only on 通知', () {
      final items = mv2AdaptiveDestinations(notificationUnread: 7);

      expect(items[3].badgeCount, 7);
      expect(
        items
            .where((AdaptiveNavigationDestination d) => d.badgeCount != null)
            .length,
        1,
      );
      expect(
        mv2AdaptiveDestinations(notificationUnread: 0)[3].badgeCount,
        0,
      );
    });
  });

  group('branch ↔ bar index', () {
    test('skip 发布, which is an action rather than a branch', () {
      // Branches: 首页 0, 节点 1, 通知 2, 我的 3.
      expect(mv2BarIndexForBranch(0), 0);
      expect(mv2BarIndexForBranch(1), 1);
      expect(mv2BarIndexForBranch(2), 3);
      expect(mv2BarIndexForBranch(3), 4);
    });

    test('clamp out-of-range indices instead of throwing', () {
      expect(mv2BarIndexForBranch(-1), 0);
      expect(mv2BarIndexForBranch(99), 4);
    });
  });

  group('SF symbols', () {
    test('map the icons our headers use', () {
      expect(mv2SfSymbolFor(Icons.settings_outlined), 'gearshape');
      expect(mv2SfSymbolFor(Icons.search_rounded), 'magnifyingglass');
      expect(mv2SfSymbolFor(Icons.filter_list_rounded), 'line.3.horizontal.decrease');
      expect(mv2SfSymbolFor(Icons.more_horiz_rounded), 'ellipsis');
      expect(mv2SfSymbolFor(Icons.star_border_rounded), 'star');
    });

    test('return null when there is no symbol to name', () {
      expect(mv2SfSymbolFor(Icons.abc), isNull);
    });
  });

  group('the package places the bar in the strip in both Duo poses', () {
    // Folded cover display and unfolded inner display both keep a trailing
    // 84pt strip and no top inset; the package's own rule is what our chrome
    // relies on, so pin the decision rather than a copy of it.
    test('yes for the folded cover display', () {
      expect(
        DuoLayout.isVerticalBarPose(const EdgeInsets.only(right: 84, bottom: 34)),
        isTrue,
      );
    });

    test('yes for the unfolded inner display', () {
      expect(
        DuoLayout.isVerticalBarPose(const EdgeInsets.only(right: 84)),
        isTrue,
      );
    });

    test('no for phones and iPads, which keep horizontal bars', () {
      // iPhone portrait: top inset, no side strip.
      expect(
        DuoLayout.isVerticalBarPose(const EdgeInsets.only(top: 59)),
        isFalse,
      );
      // iPhone landscape: symmetric side insets.
      expect(
        DuoLayout.isVerticalBarPose(
          const EdgeInsets.symmetric(horizontal: 59),
        ),
        isFalse,
      );
      // iPad: no side inset at all.
      expect(DuoLayout.isVerticalBarPose(EdgeInsets.zero), isFalse);
    });

    test('the strip is the inset the system reserved', () {
      // 1.0.2 models the pose instead of exposing bare statics; `none` keeps
      // the decision on the insets alone, like on 1.0.1.
      final pose = DuoLayout.resolvePose(
        const EdgeInsets.only(right: 84),
        SystemVerticalBarEdge.none,
      );
      expect(pose!.stripWidth, 84);
      // The band extends 12pt inward of the strip, so the centred capsules
      // sit a few points off the bezel (the package's own bezel inset).
      expect(pose.bandWidth, 96);
    });
  });

  testWidgets('scroll content clears the adaptive bar', (tester) async {
    late double inset;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          viewPadding: EdgeInsets.only(bottom: 34),
        ),
        child: Builder(
          builder: (BuildContext context) {
            inset = mv2BarContentInset(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // 80pt bar + the home indicator; the exact value matters less than never
    // letting the last row end underneath the bar.
    expect(inset, greaterThanOrEqualTo(80 + 34));
  });
}
