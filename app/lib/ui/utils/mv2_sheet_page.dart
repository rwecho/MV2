import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/theme/mv2_theme.dart';
import '../../design_system/tokens/mv2_motion.dart';
import 'mv2_breakpoints.dart';

/// Max width of a secondary page's card on wide viewports; phones never see
/// it (below the window width).
const double sheetMaxWidth = 760.0;

/// Locations presented as a floating card on wide viewports (see
/// [mv2SheetPage]). Topic detail is deliberately absent — it stays a
/// full-screen route for deep links, while in-app taps open through the
/// shell's detail pane (`openTopic`).
const List<String> _sheetLocations = <String>[
  '/reader',
  '/member',
  '/nodes/all',
  '/about',
  '/login',
  '/node',
  '/settings',
  '/read-later',
  '/history',
  '/blocked-users',
  '/my',
];

/// Whether a route location is one of the card-presented secondary pages.
bool mv2IsSheetLocation(String? location) =>
    location != null &&
    _sheetLocations.any(
      (sheet) => location == sheet || location.startsWith('$sheet/'),
    );

/// The route page for secondary destinations (设置, 我的主题, 用户主页, …).
///
/// On phones this is the plain full-screen push it always was. On wide
/// viewports it becomes an iPad-style floating card: a centred ~[sheetMaxWidth]
/// card slides up over a backdrop in the app's own surface colour. Tapping
/// outside the card — or the page's own back affordance — closes it.
Page<T> mv2SheetPage<T>({
  required BuildContext context,
  required LocalKey key,
  required Widget child,
  String? name,
}) {
  if (!mv2IsTwoPane(context)) {
    return MaterialPage<T>(key: key, name: name, child: child);
  }
  return _Mv2SheetPage<T>(key: key, name: name, child: child);
}

class _Mv2SheetPage<T> extends CustomTransitionPage<T> {
  const _Mv2SheetPage({required super.child, super.key, super.name})
    : super(
        // The backdrop is painted by the transition itself (see [_transition]),
        // so the route is opaque: nothing below needs to keep rendering.
        opaque: true,
        transitionDuration: Mv2Motion.sheet,
        reverseTransitionDuration: Mv2Motion.sheet,
        transitionsBuilder: _transition,
      );

  static Widget _transition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Mv2Motion.standard,
    );
    final topInset = MediaQuery.paddingOf(context).top;
    // Deliberately a solid backdrop in the app's own surface colour (plus a
    // touch of dim), NOT a see-through scrim: engines have shipped iOS 26
    // regressions where the route painted below a transparent route renders
    // as a black void (flutter/flutter#174925 class of bugs). The card floats
    // on a clean, intentional backdrop everywhere instead.
    final backdrop = Color.alphaBlend(
      const Color(0x14000000),
      context.colors.background,
    );
    return FadeTransition(
      opacity: curved,
      child: ColoredBox(
        color: backdrop,
        child: Stack(
          children: <Widget>[
            // Tap outside the card to close; taps inside the card are absorbed
            // by the page's own Material, so they never reach this gesture.
            Positioned.fill(
              child: Semantics(
                label: '关闭',
                button: true,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // A cold-started deep link (`mv2://member/x`) opens the card
                  // as the base route — nothing beneath to reveal, so a scrim
                  // tap is a no-op there.
                  onTap: () {
                    if (context.canPop()) context.pop();
                  },
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: topInset + 28, bottom: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: sheetMaxWidth),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.06),
                        end: Offset.zero,
                      ).animate(curved),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
