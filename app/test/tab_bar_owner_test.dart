import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tab-bar ownership in the fixed chrome, on the vendored
/// `adaptive_platform_ui` (see `../docs/vendor-patches.md`).
///
/// On the unfolded Duo the app is two-pane: the opened topic renders in a
/// pane built *inside* the shell route, not pushed on a navigator. Its
/// scaffold registers the newest toolbar entry and becomes the chrome owner;
/// the tab bar must stay visible for such a page (UIKit: the detail column of
/// a split never hides the tab bar), while a page pushed *over* the tabs must
/// still hide it.
void main() {
  Future<(ToolbarRegistry, BuildContext)> pump(WidgetTester tester) async {
    late ToolbarRegistry registry;
    late BuildContext probe;
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveToolbarHost(
          child: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Builder(
                builder: (context) {
                  registry = ToolbarRegistry.maybeOf(context)!;
                  probe = context;
                  return Column(
                    children: [
                      // The shell: owns the tab bar.
                      Expanded(
                        child: AdaptiveScaffold(
                          appBar: const AdaptiveAppBar(title: 'shell'),
                          bottomNavigationBar: AdaptiveBottomNavigationBar(
                            selectedIndex: 0,
                            onTap: (_) {},
                            items: [
                              AdaptiveNavigationDestination(
                                icon: Icons.home_outlined,
                                label: '首页',
                              ),
                              AdaptiveNavigationDestination(
                                icon: Icons.person_outline_rounded,
                                label: '我的',
                              ),
                            ],
                          ),
                        ),
                      ),
                      // The detail pane: newest entry, same route.
                      Expanded(
                        child: AdaptiveScaffold(
                          appBar: AdaptiveAppBar(title: 'detail'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
      // The registry notifies after the frame; settle one more.
    );
    await tester.pump();
    return (registry, probe);
  }

  testWidgets('a pane page in the tabs\u2019 own route keeps the tab bar',
      (tester) async {
    final (registry, _) = await pump(tester);

    final shell = registry.entries.singleWhere((e) => e.hasTabBar);
    final detail = registry.entries.singleWhere((e) => !e.hasTabBar);
    // The pane page is the newest entry, so it owns the chrome's items.
    expect(registry.active?.id, detail.id);
    // …but the tab bar still belongs with it: same route, same layout.
    expect(registry.tabBarOwnerFor(detail)?.id, shell.id);
  });

  testWidgets('a page pushed over the tabs still hides the tab bar',
      (tester) async {
    final (registry, probe) = await pump(tester);

    // A page that is genuinely *outside* the tab layout: another route on the
    // root navigator. Model it without a real push — the registry is
    // route-driven, and what matters is the containment test.
    final shell = registry.entries.singleWhere((e) => e.hasTabBar);
    final outside = ToolbarEntry(
      id: 'pushed',
      appBar: const AdaptiveAppBar(title: 'pushed'),
      route: null, // a different, unknown route
      navigator: Navigator.maybeOf(probe),
      visible: true,
    );
    registry.upsert(outside);
    await tester.pump();

    expect(registry.tabBarOwnerFor(registry.byId('pushed')), isNull);
    expect(registry.tabBarOwnerFor(registry.active)?.id, isNot(shell.id));
  });
}
