import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Session-level CSRF token (`once`).
///
/// V2EX documents `once` as a **session** token that appears in every page's
/// hidden input (`docs/12` §4) and **rotates after a write**; its AJAX write
/// endpoints hand the new value back (`/thank/*` → `{success, once, message}`).
/// The copy scraped from a page goes stale the moment a write happens, so the
/// newest value is cached here and preferred by every writer — the topic action
/// controller and the reply composer share it.
class SessionOnceController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Records a rotated token. A `null`/empty value is ignored (the response
  /// simply did not carry one), so it never wipes a known-good token.
  void update(String? token) {
    if (token == null || token.isEmpty || token == state) return;
    state = token;
  }

  void reset() => state = null;
}

final sessionOnceProvider = NotifierProvider<SessionOnceController, String?>(
  SessionOnceController.new,
);
