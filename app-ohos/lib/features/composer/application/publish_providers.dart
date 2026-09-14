import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/data/v2ex_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../shared/emoji/mv2_emoji_library.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/node_visuals.dart';
import '../../../shared/models/publish_form.dart';
import '../../auth/application/auth_controller.dart';
import '../../nodes/application/nodes_providers.dart';

/// Composer state for `/publish` (`docs/06` → Publish Topic).
@immutable
class PublishState {
  const PublishState({
    this.form,
    this.loading = true,
    this.failure,
    this.nodeSlug,
    this.nodeTitle,
    this.title = '',
    this.content = '',
    this.submitting = false,
    this.problems = const <String>[],
    this.preview = false,
    this.draftSaved = false,
    this.publishedTopicId,
  });

  /// Scraped `/new` form. `null` until it loads.
  final V2TopicForm? form;
  final bool loading;

  /// Set when the form could not be scraped; an [AuthFailure] drives the
  /// signed-out CTA.
  final Failure? failure;

  final String? nodeSlug;
  final String? nodeTitle;
  final String title;
  final String content;

  /// A publish request is in flight — the header button shows a spinner and
  /// ignores further taps (duplicate-submit guard).
  final bool submitting;

  /// Server `Problem` messages (or a local validation summary).
  final List<String> problems;

  /// The 预览 pane replaced the editor.
  final bool preview;

  /// A local draft was written to disk.
  final bool draftSaved;

  /// Numeric id from `302 → /t/{id}`; `null` on the offline fixture path.
  final int? publishedTopicId;

  bool get signedOut => failure is AuthFailure;
  bool get hasDraft => title.trim().isNotEmpty || content.trim().isNotEmpty;
  bool get canSubmit =>
      form != null &&
      !submitting &&
      (nodeSlug?.isNotEmpty ?? false) &&
      title.trim().isNotEmpty &&
      content.trim().isNotEmpty;

  PublishState copyWith({
    V2TopicForm? form,
    bool? loading,
    Failure? failure,
    bool clearFailure = false,
    String? nodeSlug,
    String? nodeTitle,
    bool clearNode = false,
    bool clearNodeTitle = false,
    String? title,
    String? content,
    bool? submitting,
    List<String>? problems,
    bool? preview,
    bool? draftSaved,
    int? publishedTopicId,
  }) {
    return PublishState(
      form: form ?? this.form,
      loading: loading ?? this.loading,
      failure: clearFailure ? null : (failure ?? this.failure),
      nodeSlug: clearNode ? null : (nodeSlug ?? this.nodeSlug),
      nodeTitle: (clearNode || clearNodeTitle)
          ? null
          : (nodeTitle ?? this.nodeTitle),
      title: title ?? this.title,
      content: content ?? this.content,
      submitting: submitting ?? this.submitting,
      problems: problems ?? this.problems,
      preview: preview ?? this.preview,
      draftSaved: draftSaved ?? this.draftSaved,
      publishedTopicId: publishedTopicId ?? this.publishedTopicId,
    );
  }
}

/// Owns the publish draft, the scraped `once` and the submit action.
class PublishController extends Notifier<PublishState> {
  static const String _draftKey = 'mv2.publishDraft';

  /// Long enough to coalesce typing, short enough that the "草稿已保存" status
  /// is honest by the time the user pauses.
  static const Duration _draftDebounce = Duration(milliseconds: 600);

  Timer? _draftTimer;
  SharedPreferences? _prefs;
  bool _disposed = false;

  @override
  PublishState build() {
    ref.onDispose(() {
      _disposed = true;
      _draftTimer?.cancel();
    });
    return const PublishState();
  }

  Future<SharedPreferences> _prefsInstance() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Entry point for the page: hydrates the local draft, then scrapes `/new`.
  ///
  /// [initialNode] comes from `/publish?node=…` and wins over the stored draft.
  Future<void> load({String? initialNode}) async {
    state = state.copyWith(loading: true, clearFailure: true);
    await _hydrateDraft();
    await _loadForm(initialNode);
  }

  Future<void> _hydrateDraft() async {
    try {
      final draft = _readDraft(await _prefsInstance());
      state = state.copyWith(
        title: draft.title,
        content: draft.content,
        clearNode: draft.nodeSlug == null,
        nodeSlug: draft.nodeSlug,
        nodeTitle: draft.nodeTitle,
        draftSaved: draft.hasContent,
      );
    } catch (_) {
      // Draft storage is best-effort: a failure must never block composing.
    }
  }

  Future<void> _loadForm(String? initialNode) async {
    state = state.copyWith(loading: true, clearFailure: true);
    try {
      final form = await ref.read(v2exApiProvider).topicForm(node: initialNode);
      final slug =
          initialNode ??
          state.nodeSlug ??
          form.defaultNode ??
          _firstOption(form);
      // Prefer the form's own label for the slug; only reuse the stored draft
      // label while the slug itself is unchanged (`/publish?node=…` must not
      // leave the previous node's title on screen).
      final title =
          _optionTitle(form, slug) ??
          (slug == state.nodeSlug ? state.nodeTitle : null);
      state = state.copyWith(
        form: form,
        loading: false,
        clearFailure: true,
        clearNode: slug == null,
        clearNodeTitle: title == null,
        nodeSlug: slug,
        nodeTitle: title,
      );
    } on Failure catch (failure) {
      if (failure is AuthFailure) {
        // Keep the global session honest: /new is login-only.
        await ref.read(authControllerProvider.notifier).handleAuthFailure();
      }
      if (_disposed) return;
      state = state.copyWith(loading: false, failure: failure);
    } catch (error, stackTrace) {
      if (_disposed) return;
      state = state.copyWith(
        loading: false,
        failure: UnknownFailure(cause: error, stackTrace: stackTrace),
      );
    }
  }

  /// Re-scrapes the form after a failure (expired `once`, transient network).
  Future<void> retry() => _loadForm(null);

  void setTitle(String value) {
    state = state.copyWith(
      title: value,
      draftSaved: false,
      problems: const <String>[],
    );
    _scheduleDraftSave();
  }

  void setContent(String value) {
    state = state.copyWith(
      content: value,
      draftSaved: false,
      problems: const <String>[],
    );
    _scheduleDraftSave();
  }

  void selectNode(String slug, String title) {
    state = state.copyWith(
      nodeSlug: slug,
      nodeTitle: title,
      draftSaved: false,
      problems: const <String>[],
    );
    _scheduleDraftSave();
  }

  void togglePreview() => state = state.copyWith(preview: !state.preview);

  /// Publishes the topic. Returns `true` on the `302` success path.
  ///
  /// When the session no longer accepts the cached `once` (V2EX hands the form
  /// back without a `Problem`), the token is re-scraped and the submit retried
  /// **exactly once** — `docs/12` §4 requires re-fetching the page when a token
  /// is missing or expired.
  Future<bool> submit() => _submit(allowTokenRefresh: true);

  Future<bool> _submit({required bool allowTokenRefresh}) async {
    final current = state;
    final form = current.form;
    final slug = current.nodeSlug;
    if (current.submitting || form == null || slug == null) return false;
    if (!current.canSubmit) {
      state = current.copyWith(problems: const <String>['请填写标题与正文，并选择节点。']);
      return false;
    }

    state = current.copyWith(submitting: true, problems: const <String>[]);
    try {
      final result = await ref
          .read(v2exApiProvider)
          .publishTopic(
            form: form,
            nodeName: slug,
            title: current.title.trim(),
            content: Mv2EmojiLibrary.expandForSubmit(current.content).trim(),
          );
      if (_disposed) return result.success;

      if (!result.success && allowTokenRefresh && result.invalidToken) {
        // Clear `submitting` first so the retry passes its own guard; the page
        // keeps rendering the composer (a form is still present), so the user
        // sees a short spinner rather than a reload.
        state = state.copyWith(submitting: false, clearFailure: true);
        await _loadForm(null);
        if (_disposed) return false;
        if (state.failure != null) {
          state = state.copyWith(
            submitting: false,
            problems: <String>[state.failure!.message],
          );
          return false;
        }
        return await _submit(allowTokenRefresh: false);
      }

      if (!result.success) {
        state = state.copyWith(
          submitting: false,
          problems: result.errors.isEmpty
              ? const <String>['发布失败，请稍后重试。']
              : result.errors,
        );
        return false;
      }
      _draftTimer?.cancel();
      await _clearDraft();
      state = state.copyWith(
        submitting: false,
        draftSaved: false,
        problems: const <String>[],
        publishedTopicId: result.topicId,
      );
      return true;
    } on Failure catch (failure) {
      if (failure is AuthFailure) {
        await ref.read(authControllerProvider.notifier).handleAuthFailure();
      }
      if (_disposed) return false;
      state = state.copyWith(
        submitting: false,
        problems: <String>[failure.message],
      );
      return false;
    }
  }

  // ------------------------------------------------------------------ draft

  void _scheduleDraftSave() {
    _draftTimer?.cancel();
    _draftTimer = Timer(_draftDebounce, _saveDraft);
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await _prefsInstance();
      final payload = jsonEncode(<String, String?>{
        'title': state.title,
        'content': state.content,
        'nodeSlug': state.nodeSlug,
        'nodeTitle': state.nodeTitle,
      });
      await prefs.setString(_draftKey, payload);
      if (_disposed) return;
      state = state.copyWith(draftSaved: true);
    } catch (_) {
      // Ignore: the draft is a convenience, not a source of truth.
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await _prefsInstance();
      await prefs.remove(_draftKey);
    } catch (_) {
      // Ignore.
    }
  }

  _PublishDraft _readDraft(SharedPreferences prefs) {
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.isEmpty) return const _PublishDraft();
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return const _PublishDraft();
      return _PublishDraft(
        title: (map['title'] as String?) ?? '',
        content: (map['content'] as String?) ?? '',
        nodeSlug: map['nodeSlug'] as String?,
        nodeTitle: map['nodeTitle'] as String?,
      );
    } on FormatException {
      return const _PublishDraft();
    }
  }

  static String? _firstOption(V2TopicForm form) =>
      form.nodeOptions.isEmpty ? null : form.nodeOptions.first.name;

  static String? _optionTitle(V2TopicForm form, String? slug) {
    if (slug == null) return null;
    for (final option in form.nodeOptions) {
      if (option.name == slug) return option.title;
    }
    return null;
  }
}

/// Nodes offered by the publish page's picker.
///
/// Prefers whatever `/new` itself rendered (usually nothing on mobile), then
/// falls back to the full directory from `/api/nodes/s2.json`.
final publishNodeOptionsProvider = FutureProvider<List<V2Node>>((ref) async {
  final form = ref.watch(publishProvider.select((state) => state.form));
  if (form != null && form.nodeOptions.isNotEmpty) {
    return form.nodeOptions
        .map((option) => NodeVisuals.node(key: option.name, name: option.title))
        .toList(growable: false);
  }
  return ref.watch(nodesProvider.future);
});

final publishProvider = NotifierProvider<PublishController, PublishState>(
  PublishController.new,
);

@immutable
class _PublishDraft {
  const _PublishDraft({
    this.title = '',
    this.content = '',
    this.nodeSlug,
    this.nodeTitle,
  });

  final String title;
  final String content;
  final String? nodeSlug;
  final String? nodeTitle;

  bool get hasContent => title.trim().isNotEmpty || content.trim().isNotEmpty;
}
