import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/parser/html_dom.dart';
import '../../../core/telemetry/mv2_analytics.dart';
import '../../../ui/components/mv2_rich_text.dart';
import '../../settings/application/settings_controller.dart';
import 'reader_mode.dart';

/// Opens a web URL the way the 外链打开方式 setting wants: the in-app reader
/// (`/reader`), the untouched page in 原文, or the system browser.
///
/// Single choke point for every "open this link" affordance outside rich text
/// (which routes through [Mv2RichText.openExternalUrl] into here) — currently
/// the topic page's link-preview card. Keeps `link_open` attributed the same
/// way no matter which surface was tapped.
///
/// [url] may be relative (`/t/123`) or absolute; [absoluteV2exUrl] normalises
/// it first. Non-web schemes (`mailto:`, `tel:`) always leave the app and are
/// not content links, so they are not counted in `link_open`.
Future<void> openExternalUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(absoluteV2exUrl(url) ?? url);
  if (uri == null) return;

  // Read the preference before any await so `context` is never used across an
  // async gap without the mounted check below.
  final mode = _linkOpenMode(context);

  if (uri.scheme != 'http' && uri.scheme != 'https') {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return;
  }

  Mv2Analytics.logLinkOpen(mode: mode.name, isInternal: false);

  if (mode == Mv2LinkOpenMode.browser) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return;
  }

  if (!context.mounted) return;
  context.push(
    readerRoute(
      uri.toString(),
      mode: mode == Mv2LinkOpenMode.original ? ReaderMode.original : null,
    ),
  );
}

/// The persisted 外链打开方式 preference.
///
/// Callers are deliberately not `ConsumerWidget`s (rich text is used in
/// isolated widget tests and previews), so the scope is looked up defensively
/// and reader mode is assumed when none is mounted — the same value the
/// setting defaults to.
Mv2LinkOpenMode _linkOpenMode(BuildContext context) {
  try {
    return ProviderScope.containerOf(
      context,
      listen: false,
    ).read(settingsProvider).openLinkMode;
  } catch (_) {
    return Mv2LinkOpenMode.reader;
  }
}
