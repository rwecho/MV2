import 'package:flutter/foundation.dart';

/// A node selectable in the publish page, as rendered by the `/new` form.
///
/// The full directory always comes from `/api/nodes/s2.json`; this is only the
/// subset the page itself offers, used as a fallback when the directory is
/// unavailable.
@immutable
class V2NodeOption {
  const V2NodeOption({required this.name, required this.title});

  /// Slug posted as `node_name` (e.g. `programmer`).
  final String name;

  /// Display name (e.g. `程序员`).
  final String title;
}

/// The scraped V2EX topic form (`/new`), mirroring [V2LoginForm].
///
/// V2EX only asks for a session-level `once` CSRF token plus, optionally, the
/// node the page was opened for. Everything else (`title`, `content`,
/// `syntax`, `node_name`) is supplied by the client.
@immutable
class V2TopicForm {
  const V2TopicForm({
    required this.once,
    this.defaultNode,
    this.nodeOptions = const <V2NodeOption>[],
  });

  /// CSRF token; reusable for every write action in the session, but always
  /// re-scraped when the composer opens so an expired session is detected.
  final String once;

  /// The node slug preselected by `/new/{node}` (or the form's own hidden
  /// input), when the page carries one.
  final String? defaultNode;

  /// Nodes the page rendered as choices; may be empty when the picker is
  /// client-side only.
  final List<V2NodeOption> nodeOptions;
}

/// Outcome of a publish attempt.
@immutable
class V2PublishResult {
  const V2PublishResult({
    required this.success,
    this.topicId,
    this.errors = const <String>[],
    this.invalidToken = false,
  });

  final bool success;

  /// Numeric id parsed from the `302 → /t/{id}` Location on success. `null`
  /// when the server did not disclose it (offline fixture mode).
  final int? topicId;

  /// Messages scraped from `div.problem li` on rejection.
  final List<String> errors;

  /// The rejection looks like a `once` the session no longer accepts: the form
  /// came back with no explanation. Callers may re-scrape `/new` and retry once
  /// (`PublishParser.isStaleToken`).
  final bool invalidToken;
}
