# MV2 — HarmonyOS (ohos) variant

This directory is a **platform variant** of the mainline MV2 Flutter client,
built for HarmonyOS / OpenHarmony with the
[Flutter ohos fork](https://gitcode.com/CPF-Flutter/flutter_flutter).

> **Status: built, installed and launched on a HarmonyOS emulator (HMS push
> config still absent).**
> A Mate 60 emulator became available, so the debug HAP was installed
> (`hdc install`) and started (`aa start`): the home feed rendered live V2EX
> content and the app stayed up. The HMS bridge was confirmed active from the
> device log (`Mv2HmsPush --> AGC client_id is not configured; HMS push stays
> disabled.`), i.e. the deliberate degradation works on hardware. Everything
> that needs a real AppGallery Connect project — `pushService.getToken`, a
> delivered HMS notification, the notification-tap route — is still **not
> verified on a device** and is labelled as such. The acceptance evidence also
> includes `flutter analyze`, `flutter test` and `flutter build hap --debug`.
>
> **Update.** The ohos `flutter_tools` is now patched to bundle
> `NativeAssetsManifest.json` (§1.1); on device the sqlite3 asset id resolves
> for the first time, but the bundled `.so` is a glibc/Linux build that the
> HarmonyOS loader rejects, so the Drift store still uses its documented
> fallback (§4.1). The restricted-topic infinite skeleton is fixed and verified
> on the emulator (§3.5). Note the debug HAP is heavy: on a slow emulator the
> system may kill it with `LIFECYCLE_TIMEOUT` during startup — relaunch.

The mainline app at `../app/` is **untouched** and still builds for
ios / android / macos / web. This variant shares its Dart sources via
`tool/sync-from-app.sh`.

---

## 1. Build recipe

```bash
cd app-ohos

# 1. Resolve dependencies with the ohos SDK (the default pub mirror is broken).
PUB_HOSTED_URL=https://pub.dev \
  /Volumes/MacMiniDisk/workspace/flutter-ohos-3.41.9/bin/flutter pub get

# 2. Static analysis.
PUB_HOSTED_URL=https://pub.dev \
  /Volumes/MacMiniDisk/workspace/flutter-ohos-3.41.9/bin/flutter analyze

# 3. Build the HAP. Regenerate the local debug signing material first if
#    ohos/signing/ is missing.
#
#    Fixtures are the default. For LIVE data pass both defines:
#    MV2_FIXTURES=false talks to www.v2ex.com; MV2_PROXY routes through the
#    host proxy, which the emulator can only reach after the `hdc rport` below.
./tool/generate-ohos-debug-signing.sh
PUB_HOSTED_URL=https://pub.dev \
  /Volumes/MacMiniDisk/workspace/flutter-ohos-3.41.9/bin/flutter build hap --debug \
    --dart-define=MV2_FIXTURES=false \
    --dart-define=MV2_PROXY=http://127.0.0.1:7897

# 4. Reverse-forward the proxy port so the emulator can reach the host proxy.
#    (The host proxy must already be listening on 7897; `hdc fport ls` lists
#    the mapping as `tcp:7897 tcp:7897 [Reverse]`.) Re-running fails with
#    "TCP Port listen failed at 7897" once the reverse forward exists.
hdc rport tcp:7897 tcp:7897

# 5. Install and launch.
hdc install -r build/ohos/hap/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.rwecho.mv2
#    Colder start straight into a route (bypasses the missing deep-link shim):
hdc shell aa start -a EntryAbility -b com.rwecho.mv2 --ps route "mv2://topic/1241298"
```

**Verified result** (exit code captured without a pipe, so this is the real
`flutter build` status):

```
$ flutter build hap --debug
✓ Built build/ohos/hap/entry-default-signed.hap.
$ echo $?
0
```

| | |
|---|---|
| Artifact | `app-ohos/build/ohos/hap/entry-default-signed.hap` |
| Size | **161,901,483 bytes ≈ 154 MiB** (debug, arm64 only; `kernel_blob.bin` is ~101 MiB of it) |
| Unsigned intermediate | `app-ohos/ohos/entry/build/default/outputs/default/entry-default-unsigned.hap` (161,516,006 bytes) |
| ABI | `arm64-v8a` (default `TARGET_PLATFORM=ohos-arm64`) |
| Engine | `libs/arm64-v8a/libflutter.so` (38.7 MB) |
| Native asset | `libs/arm64-v8a/libsqlite3.so` (1.72 MB, ELF aarch64) |
| Signing | OpenHarmony **public demo** debug certificate (see §7) — not publishable |

Toolchain used: `Flutter 3.41.10-ohos-0.0.4-dev` / Dart **3.11.5**,
ohpm 6.1.1.830, hvigor from DevEco Studio, OpenHarmony SDK API 23 (`default`).

There is **no release/profiling variant** configured: `release` would need
Huawei-issued release certificates.

### 1.1 Local `flutter_tools` fix: bundle `NativeAssetsManifest.json`

**The ohos fork in this workspace is patched** (only the SDK, never app code):
`packages/flutter_tools/lib/src/build_system/targets/ohos.dart` —
`OhosAssetBundle.build` now passes

```dart
additionalContent: <String, DevFSContent>{
  'NativeAssetsManifest.json': DevFSFileContent(
    environment.buildDir.childFile('native_assets.json'),
  ),
},
```

to `copyAssets`, mirroring mainline's `CopyFlutterBundle` (and every other
platform target). Without it the HAP's `flutter_assets/` never received
`NativeAssetsManifest.json`, so the engine could not resolve any Dart
build-hook asset (`No asset with id 'package:sqlite3/src/ffi/libsqlite3.g.dart'
found. No available native assets.`). The patch is marked with a
`// Local fix` comment in the fork.

Rebuilding the tool after editing it (the stamp alone is not enough when the
change is uncommitted):

```bash
cd /Volumes/MacMiniDisk/workspace/flutter-ohos-3.41.9
rm -f bin/cache/flutter_tools.stamp bin/cache/flutter_tools.snapshot
PUB_HOSTED_URL=https://pub.dev ./bin/flutter --version   # rebuilds the snapshot
```

After a rebuild the HAP contains
`resources/rawfile/flutter_assets/NativeAssetsManifest.json`:

```json
{"format-version":[1,0,0],"native-assets":{"ohos_arm64":{"package:sqlite3/src/ffi/libsqlite3.g.dart":["absolute","libsqlite3.so"]}}}
```

**This fix is necessary but not sufficient** — see §4.1.

---

## 2. Dependency changes vs. `../app/pubspec.yaml`

Two independent forces: the ohos fork ships **Dart 3.11.5** (mainline is
3.13.3), and several native plugins have no HarmonyOS implementation.

### 2.1 SDK constraint

| Field | mainline | ohos | Why |
|---|---|---|---|
| `environment.sdk` | `^3.13.3` | `^3.11.0` | the fork's Dart is 3.11.5 |

### 2.2 Version pins / downgrades (all forced by `environment.sdk`)

| Package | mainline | ohos | Highest release needing ≤ Dart 3.11 |
|---|---|---|---|
| `flutter_riverpod` | `^3.4.3` | `^3.3.2` (→3.3.2) | 3.4.x requires `^3.12.0`; 3.3.2 requires `^3.7.0` |
| `go_router` | `^18.0.1` | `^17.5.0` (→17.5.0) | 18.x requires `^3.12.0`; 17.5.0 requires `^3.10.0` |
| `cached_network_image` | `^4.0.0` | `^3.4.1` (→3.4.1) | 4.0.0 requires `^3.12.0`; 3.4.1 requires `^3.0.0` |
| `freezed` (dev) | `^4.0.1` | `^3.2.5` (→3.2.5) | 4.0.x requires `>=3.13.0`; 3.2.5 requires `>=3.8.0` |
| `drift` | `^2.35.0` | `2.34.4` | `drift_dev` 2.34.x (newest on analyzer 10.x) refuses `drift >=2.35.0` |
| `build_runner` (dev) | `^2.16.1` | `2.15.1` | 2.15.2+ needs analyzer ≥13.3.0; see below |
| `drift_dev` (dev) | `^2.35.0` | `2.34.0` | 2.35.0 needs analyzer ≥13; 2.34.0 accepts `>=10 <13` |
| `json_serializable` (dev) | `^6.14.1` | `^6.14.1` (→6.14.1, unchanged) | 6.14.1 accepts analyzer `>=10 <15` |
| `shadcn_ui` | `^0.56.3` | **vendored path** `vendor/shadcn_ui` | see §2.4 |
| `app_links` | `^7.2.1` | **local shim** | 7.1.0+ requires `^3.12.0` |
| `firebase_core` / `firebase_messaging` | `^4.14.0` / `^16.6.0` | **local shims** (still needed so `FirebasePushGateway` compiles; ohos selects `HmsPushGateway` instead — §3.4) | no HarmonyOS Firebase SDK exists |
| `flutter_secure_storage`, `share_plus` | pub.dev | **local shims** | no usable ohos implementation |
| `image_picker` | pub.dev | **removed** — replaced by the local `mv2/image_picker` ArkTS bridge (§3.6) | no ohos port exists on pub.dev |
| `shared_preferences`, `path_provider`, `url_launcher`, `webview_flutter` | pub.dev | same + `*_ohos` federated impl | §3.1 |

Unchanged because they already allow Dart 3.11: `dio`, `dio_cookie_manager`,
`cookie_jar`, `html`, `freezed_annotation`, `json_annotation`, `flutter_lints`.

**The coherent codegen window.** `build_runner`, `drift_dev` and `freezed` all
constrain the shared `analyzer`:

* newest `build_runner` (2.16.x) → analyzer `>=13.3.0 <15`
* newest `drift_dev` (2.35.x) → analyzer `>=13.0.0 <15`
* newest `freezed` that supports Dart 3.11 (3.2.5) → analyzer `>=9.0.0 <11.0.0`

The only intersection is **analyzer 10.0.1**, which pins the whole toolchain as
listed above (`build_runner` 2.15.1 → `>=8 <14`, `json_serializable` 6.14.1 →
`>=10 <15`, `drift_dev` 2.34.0 → `>=10 <13`).

Note: the repository currently contains **no `@freezed` or `@JsonSerializable`
annotations** — the only generated file is the committed
`lib/core/storage/cache_database.g.dart` for Drift. The codegen
dev-dependencies are kept pinned so `dart run build_runner build` still works,
but no codegen was re-run for this variant (there is nothing to regenerate).

### 2.3 `sqlite3` build hook removed

Mainline's pubspec sets

```yaml
hooks:
  user_defines:
    sqlite3:
      source: system
```

That is dropped here: HarmonyOS has no system `sqlite3` to link against. It is
not needed either — see §5.

### 2.4 Vendored `shadcn_ui` (compile blocker)

The ohos fork adds `TargetPlatform.ohos` to the `TargetPlatform` enum. Every
exhaustive `switch (TargetPlatform)` in `shadcn_ui` 0.56.3 therefore becomes a
hard kernel-compile error:

```
shadcn_ui-0.56.3/lib/src/app.dart:715:17: Error: The type 'TargetPlatform' is
  not exhaustively matched by the switch cases since it doesn't match
  'TargetPlatform.ohos'.
```

`flutter analyze` does **not** catch this (dependency sources are not analysed) —
only `flutter build hap` does. The three affected switches in `lib/src/app.dart`
and `lib/src/components/input.dart` were patched with four
`case TargetPlatform.ohos:` lines (treated as Android-like), and the package is
vendored under `vendor/shadcn_ui/`; `pubspec.yaml` points at the path. A scan of
the whole resolved dependency tree found **no other** package with an
ohos-exhaustiveness problem.

---

## 3. Plugin strategy

### 3.1 Real HarmonyOS ports (federated, no Dart changes)

These declare `implements: <parent>` for `ohos`, so the mainline call sites are
byte-identical and the plugins are registered natively in the HAP
(`ohos/entry/src/main/ets/plugins/GeneratedPluginRegistrant.ets`):

| Package | Version | Parent | Backed by |
|---|---|---|---|
| `path_provider_ohos` | 2.2.1 | `path_provider` | ohos app sandbox paths |
| `shared_preferences_ohos` | 2.2.0 | `shared_preferences` | ohos preferences |
| `url_launcher_ohos` | 6.3.0 | `url_launcher` | ohos `startAbility` |
| `webview_flutter_ohos` | 3.15.0 | `webview_flutter` | ArkWeb |

Generated registrant (actual build output):

```ts
import WebViewFlutterPlugin from 'webview_flutter_ohos';
import UrlLauncherPlugin from 'url_launcher_ohos';
import SharedPreferencesPlugin from 'shared_preferences_ohos';
import PathProviderPlugin from 'path_provider_ohos';
```

### 3.2 Local shims (`shims/`)

Each shim keeps the **exact Dart API** the mainline uses, so no `lib/` call site
had to change. Shims are normal Dart packages pointed at by `path:` in
`pubspec.yaml`.

| Shim | Replaces | Behaviour on ohos | Escape hatch for the publisher |
|---|---|---|---|
| `shims/flutter_secure_storage` | `flutter_secure_storage` 11.x | `read`/`write`/`delete` backed by `shared_preferences`. **No keystore: values are plain app-sandbox storage.** `FlutterSecureStorage.securityDegraded == true`. | Swap in a HUKS/keystore implementation and delete the shim. |
| `shims/share_plus` | `share_plus` 13.x | `SharePlus.instance.share()` throws `UnsupportedError`. Both call sites already `catch` this and fall back to clipboard + SnackBar. | Implement the system share sheet. |
| `shims/app_links` | `app_links` 7.x | `uriLinkStream` is always empty; `getInitialLink()` returns `null`. The clipboard-pasteboard deep-link path (the one that matters for shared `https://www.v2ex.com/...` links) is unaffected because it only uses `Clipboard`. | Add an ArkTS `want` handler + `AppLinksPlatform`. |
| `shims/firebase_core` | `firebase_core` 4.x | `Firebase.initializeApp()` always throws; `Firebase.apps` is empty. | **Superseded on ohos**: `push_providers.dart` picks `HmsPushGateway`, so this shim is only compiled, never reached (see §3.4). |
| `shims/firebase_messaging` | `firebase_messaging` 16.x | API surface only; every method is inert because `_available` can never become true. | Same — kept so the mainline `FirebasePushGateway` still compiles. |

Why shims rather than deleting `firebase_*`: the existing `Mv2PushGateway`
interface already treats "SDK failed to initialise" as "push unavailable", so the
shims give the required no-op behaviour on every platform except ohos. The pubspec
comments and this table make the substitution explicit — no Firebase code is
compiled into the HAP with a working backend.

### 3.3 The `lib/` and `test/` files that differ from `../app/`

Listed here, enforced by `--exclude` in `tool/sync-from-app.sh`, and repeated in
that script's header comment:

1. **`lib/core/data/v2ex_providers.dart`** — `cacheDatabaseProvider` gains a
   `_openCacheDatabase()` indirection that is gated on
   `defaultTargetPlatform == TargetPlatform.ohos`, probes whether the sqlite3
   native asset can actually be opened (`sqlite3.openInMemory()`), and falls back
   to the SharedPreferences store if not. See §5. The gate matters: `flutter test`
   runs on the host, so gating keeps the test path byte-for-byte equivalent to
   mainline.
2. **`lib/features/composer/application/image_picker_providers.dart`** — the
   `imagePickerProvider` fork: `OhosImagePicker` on `TargetPlatform.ohos`. The
   shared interface (`image_picker_gateway.dart`) and the composer page are
   synced verbatim, so no page code is forked. See §3.6.
3. **`lib/features/composer/application/ohos_image_picker.dart`** *(new file)* —
   `OhosImagePicker`, the `Mv2ImagePicker` implementation over the
   `mv2/image_picker` platform channel (§3.6).
4. **`lib/core/storage/ohos_cache_database.dart`** *(new file)* — the
   SharedPreferences-backed fallback store. See §5.
5. **`lib/core/push/push_providers.dart`** — the gateway provider returns
   `HmsPushGateway` on `TargetPlatform.ohos` and `FirebasePushGateway`
   everywhere else. `Mv2PushGateway`, `push_service.dart` and every caller are
   untouched.
6. **`lib/core/push/hms_push_gateway.dart`** *(new file)* — `HmsPushGateway`,
   the Push Kit implementation of `Mv2PushGateway` (§3.4).
7. **`test/hms_push_gateway_test.dart`** *(new file)* — unit tests for the HMS
   gateway against fake `mv2/push` channels.

> **Reconciled with mainline (previous items 7–11, plus `composer_image_button.dart`).**
> `lib/core/data/v2ex_api.dart`, `lib/features/topic/application/topic_providers.dart`,
> `lib/features/topic/presentation/topic_detail_page.dart`,
> `lib/features/settings/application/settings_controller.dart` and
> `test/restricted_topic_test.dart` used to be listed here because the redirect
> classification, the `retry:` policy, the 去登录 state and the guarded
> `SharedPreferences` hydration were fixed in this variant first. They are now
> mirrored into `../app/`, so they are **no longer `--exclude`d** and are synced
> from it like every other file. The shared `lib/core/errors/provider_retry.dart`
> (`mv2Retry`) helper — used by the topic / feed / node / search / notifications
> / member / my-list providers — is synced the same way. See §3.5 and §5.
> `composer_image_button.dart` was excluded only to hide the 图片 button while
> `image_picker` had no ohos port; now that the page depends on the
> `Mv2ImagePicker` interface it is platform agnostic and synced verbatim.

Everything else under `lib/`, `assets/` and `test/` is verified identical to
`../app/` (content comparison over every `.dart` file, excluding the seven above).

### 3.4 HMS Push Kit (HarmonyOS notifications)

`lib/core/push/hms_push_gateway.dart` implements the **same** `Mv2PushGateway`
seam as Firebase, so `push_service.dart` is byte-identical to mainline:
`isAvailable`, `initialize`, `requestPermission`, `token`, `tokenRefreshes`,
`opened`, `initialOpened`, `foreground`.

Two platform channels connect it to
`ohos/entry/src/main/ets/push/HmsPushBridge.ets`:

| Channel | Direction | Methods / events |
|---|---|---|
| `mv2/push` | Dart → ArkTS | `isConfigured`, `getToken`, `requestPermission`, `initialOpened` |
| `mv2/push/events` | ArkTS → Dart | `{type: 'token'\|'message'\|'opened', …}` |

Push Kit APIs used, all in `HmsPushBridge.ets`:

* `pushService.getToken()` (`@kit.PushKit`) for the device token;
* `pushService.on('tokenUpdate', ability, cb)` for token rotation;
* `pushService.receiveMessage('DEFAULT', ability, cb)` for foreground
  data messages, whose `Payload.data` is the worker's JSON
  (`{link, topicId?, notificationId?}`);
* `notificationManager.isNotificationEnabled()` /
  `requestEnableNotification(context)` (`@kit.NotificationKit`) for the
  permission prompt;
* the notification **tap** path is the ability `want`: `EntryAbility.onCreate`
  (cold start, buffered) and `onNewWant` (warm) hand it to
  `HmsPushBridge.handleWant`, which finds the `{link, topicId}` JSON among the
  `want.parameters` and forwards it to the `opened` stream, where the existing
  `Mv2PushPayload.routeFor` → `/topic/:id` route takes over.

**Degradation.** `initialize()` first asks `isConfigured`, which reads the
`client_id` metadata from `module.json5`. The checked-in value is the
non-functional placeholder `REPLACE_WITH_AGC_CLIENT_ID`, so `isConfigured` is
`false`, `getToken` is never called and `isAvailable` stays `false` — the
推送通知 setting simply does nothing, exactly as before. A real `client_id`
whose `getToken` still fails (missing `agconnect-services.json`, bundle-name
mismatch, unsigned build) also lands on `isAvailable == false`, never a throw:
every Push Kit call is wrapped, and `getToken` errors surface as a
`PlatformException` only to `HmsPushGateway`, which converts them to "push
unavailable". No token or secret is ever logged.

### 3.5 Restricted topics: the infinite skeleton (mainline defect)

**Symptom.** Opening a login-only topic (`/t/1241298`) while signed out showed
the article skeleton (`27-ohos-42-anthropic-live-topic.jpeg`) instead of an
error or a sign-in prompt.

**Root cause — two independent bugs, both inherited from `../app/`:**

1. `RemoteV2exApi.topicDetail` never inspected the response status. V2EX answers
   `302 → /restricted → /signin?next=/restricted`; the client deliberately does
   not follow redirects, so `_getHtml` returned the **empty** redirect body and
   `TopicParser.parse('')` threw a generic `ParseFailure`
   (“页面结构可能已变更”) — at best the generic error state, never a sign-in
   prompt.
2. Riverpod 3 retries **every `Exception`** by default
   (`ProviderContainer.defaultRetry`: 10 attempts, exponential backoff,
   ~38 s total). Every MV2 `Failure` is an `Exception`, so even the
   `ParseFailure` from (1) was retried. While a retry is pending the state is an
   `AsyncLoading` that still carries the error
   (`AsyncLoading(hasError: true, isReloading: true)`), and
   `AsyncValue.when(loading:, error:)` renders `loading` for the whole backoff —
   hence a skeleton that looks permanent. The app's own model already says
   `AuthFailure.isRetryable == false`; Riverpod ignored it.

**Fix (now mirrored into `../app/`, so all three files are synced from it rather
than excluded):**

* `v2ex_api.dart` — `_getHtml(..., rejectRedirect: true)` turns a 3xx into a
  `Failure`: `Location` containing `/signin` or `/restricted` → `AuthFailure`,
  anything else → `NotFoundFailure`. `topicDetail` opts in.
* `topic_providers.dart` — `retry: mv2Retry` (shared
  `lib/core/errors/provider_retry.dart`) returns `null` for a non-retryable
  `Failure` and otherwise delegates to `ProviderContainer.defaultRetry`, so an
  auth/404/parse failure reaches the error state immediately. The same policy is
  applied to the feed / node / search / notifications / member / my-list
  providers.
* `topic_detail_page.dart` — an `AuthFailure` renders
  `Mv2StateView(title: '该主题需要登录后查看', actionLabel: '去登录')` pushing
  `/login`; every other error keeps the retryable `重试` state.

**Device evidence.** `aa start … --ps route "mv2://topic/1241298"` (signed out)
now renders the sign-in state —
`screenshots/27-ohos-50-restricted-topic-signin.jpeg` — and 去登录 opens the
login form — `screenshots/27-ohos-51-restricted-topic-login.jpeg`. Covered by
`test/restricted_topic_test.dart`.

**Mirror into `../app/`.** Both bugs are in mainline code; mainline would show
the same ~38 s skeleton for **any** non-retryable failure (a deleted topic, a
parse error), so the fix belongs upstream, not only here.

### 3.6 Image upload — the `mv2/image_picker` bridge

The reply/publish composer's 图片 button is live on ohos again (it used to be
hidden while `image_picker` had no port). The flow:

```
ComposerImageButton
  → imagePickerProvider (Mv2ImagePicker)
      ohos: OhosImagePicker ── MethodChannel mv2/image_picker ── ImagePickerBridge.ets
                                                                    photoAccessHelper.PhotoViewPicker
                                                                    → copy datashare:// URI into cacheDir
                                                                    → { path, name }   (null = cancel)
      other: ImagePickerImagePicker (package:image_picker)
  → ImgurUploader.upload(bytes) → inserts ![](https://i.imgur.com/…)
```

* **Shared:** `lib/features/composer/application/image_picker_gateway.dart`
  (`Mv2ImagePicker` + `Mv2PickedImage`) and `composer_image_button.dart` are
  synced from `../app/`; the page has no platform branch.
* **ohos-only:** `image_picker_providers.dart` (provider fork) and
  `ohos_image_picker.dart` (Dart side), plus
  `ohos/entry/src/main/ets/plugins/ImagePickerBridge.ets` (ArkTS side). The
  bridge is attached in `EntryAbility.configureFlutterEngine`, next to
  `HmsPushBridge`.
* **URI handling:** `PhotoViewPicker` returns a `datashare://` media URI that
  `dart:io` cannot open, so ArkTS copies the bytes into
  `context.cacheDir/mv2-pick-<ts>.<ext>` and returns `{path, name}`; Dart then
  does a plain `File(path).readAsBytes()`.
* **Cancel** answers `null` (both an empty `photoUris` list and a rejected
  `select()` are treated as a dismissal); a read/copy failure answers a
  `PlatformException`, which the composer surfaces through its existing error
  SnackBar.
* **Downscaling is not applied on ohos.** Mainline passes `maxWidth: 2400` /
  `imageQuality: 90` to `image_picker`; the ohos bridge uploads the picked
  original. Acceptable for correctness, but a 12 MP photo is uploaded at full
  size.

**Permissions / ACL the publisher must add.** None for the picker itself:
`photoAccessHelper.PhotoViewPicker` is a system-UI picker and grants the app
temporary read access to the item the user selects, so
`ohos.permission.READ_IMAGEVIDEO` is **not** declared and no runtime permission
prompt is shown (verified on device). Only if a future change replaces the
picker with a direct `photoAccessHelper.getAssets()` query would the publisher
need to declare `ohos.permission.READ_IMAGEVIDEO` in
`ohos/entry/src/main/module.json5` (`requestPermissions`, plus the
`reason`/`usedScene` fields and an ACL for a release certificate). Network
access for the Imgur upload reuses the already-declared
`ohos.permission.INTERNET`.

**Device evidence (live, `MV2_FIXTURES=false`).** In the reply composer the 图片
button is now rendered (it used to be hidden) —
`screenshots/27-ohos-80-image-picker.jpeg`; tapping it opens the system picker
(*所有图片* / *所有相册*, footer *仅可访问所选图片*) —
`screenshots/27-ohos-81-image-selected.jpeg`; confirming a photo runs the whole
path (copy → `File.readAsBytes()` → `ImgurUploader`) and inserts
`![](https://i.imgur.com/z1CEkdn.png)` into the draft —
`screenshots/27-ohos-82-image-after-upload.jpeg`. No reply was submitted.

### 3.7 Login: the `once` CSRF token rotates on every render

V2EX re-renders the whole `/signin` form after a failed POST and issues a fresh
`once` with it; resubmitting the previous token is answered with
`CSRF 失效，请重新提交`. The shared login page used to refresh only the captcha
image (which reuses the old token), so the **second** submit always failed with
that error.

Fixed in the shared `lib/features/auth/presentation/login_page.dart` (synced,
no ohos fork): a failed submit now calls `_loadForm()`, which re-scrapes the
form **and** reloads the captcha belonging to the new render, while keeping the
V2EX error text visible (`CSRF 失效` is surfaced as `登录令牌已过期，请重试`). The
manual captcha tap still only re-fetches the image: verified live that
`GET /_captcha?once=<stale>` answers `200 image/png`, so the captcha endpoint is
bound to the session rather than to `once`. Regression test:
`test/login_page_test.dart` (submits twice and asserts the second POST carries
the refreshed token).

Also fixed while reproducing this: `RemoteV2exApi.loginForm()` treated **any**
`/signin` redirect as "session already valid". After enough failed attempts
V2EX answers `302 → /signin/cooldown` ("too many sign in attempts … this IP"),
which the page then reported as "页面结构可能已变更". It is now mapped to a
`RateLimitFailure` (`登录尝试过于频繁…`) via
`V2exEndpoints.signInCooldown`. Covered by
`test/write_actions_test.dart` → `RemoteV2exApi.loginForm`.

**Device evidence.** `screenshots/27-ohos-70-login-attempt1.jpeg` — first
wrong-captcha submit answers the normal *输入的验证码不正确* and the captcha has
been re-rendered (new image, field cleared), i.e. the re-scrape ran. The second
submit carried the refreshed token; no `CSRF 失效` appeared. Caveat: the live
IP hit V2EX's `/signin/cooldown` while capturing attempt 2 (the reproduction's
own repeated failures tripped it), so the second POST's own message could not be
read from the screen — `screenshots/27-ohos-71-login-attempt2.jpeg` shows the
cooldown-driven "无法加载登录表单" state instead. The refreshed-`once` behaviour
itself is asserted deterministically by the widget test.

---

## 4. Feature matrix (works / degraded / missing)

Legend: **"Works (compiled)"** = the HarmonyOS implementation is registered and
the mainline logic is unchanged, but it was never executed on a device.
**Degraded** / **Missing** are documented losses.

| Feature | Status | Notes |
|---|---|---|
| Feed (首页 / 节点 / 最新) | **Works (compiled)** | pure-Dart parsers + `dio`; nothing platform-specific |
| Topic detail (主题详情 / 回复列表) | **Works (compiled)** | `html`-parsed, no native plugin |
| Reader 阅读模式 | **Works (compiled)** | Readability.js is bundled as an asset and evaluated through the WebView |
| Reader 原文模式 | **Works (compiled, unverified — highest risk)** | depends on `webview_flutter_ohos` (ArkWeb). No degradation was applied because a real ohos WebView exists. If ArkWeb fails, `ReaderPage` already degrades: extraction failure → 原文, WebView failure → `ReaderFailureView` with 用浏览器打开 |
| Reader 分享 / topic 分享 | **Degraded** | `share_plus` shim throws → the existing catch copies the link to the clipboard and shows "无法打开分享面板，链接已复制到剪贴板" |
| Reader 用浏览器打开 / 复制链接 | **Works (compiled)** | `url_launcher_ohos` + `Clipboard`; failure already shows "无法打开浏览器" |
| Search (搜索) | **Works (compiled)** | pure Dart (`sov2ex` JSON + HTML fallback) |
| Notifications list (通知) | **Works (compiled)** | pure Dart; reading the page does not need push |
| Unread badge | **Works (compiled)** | scraped from the signed-in account page |
| **Push notifications (推送)** | **Works (compiled, needs AGC config — highest risk)** | `HmsPushGateway` + the `mv2/push` ArkTS bridge implement Push Kit (`pushService.getToken` / `on('tokenUpdate')` / `receiveMessage`), and the worker gained an HMS sender. Without a real `client_id` + `agconnect-services.json` the gateway reports `isAvailable == false` and push stays off (§3.4, §7.3). Never executed on a device. |
| Profile (我的 / 会员) | **Works (compiled)** | pure Dart |
| Settings (设置) | **Works (compiled)** | `shared_preferences_ohos` is a real implementation |
| Login form | **Works (verified on device)** | dio + cookie jar + HTML parse; the `once`-rotation fix (§3.7) is exercised live up to the IP cooldown |
| Login captcha image | **Works (verified on device)** | fetched as bytes through `dio`; no image plugin needed |
| Session persistence | **Works, degraded security** | persisted, but in `shared_preferences` rather than a keystore (secure-storage shim) |
| Write actions (回复 / 发帖 / 感谢 / 收藏 / 忽略 / 举报) | **Works (compiled)** | form POST with manual redirect handling; no native plugin |
| Composer image upload | **Works (compiled)** | system picker via `photoAccessHelper.PhotoViewPicker` over `mv2/image_picker` (§3.6); the 图片 button is no longer hidden. Imgur upload reuses the shared `ImgurUploader`. Downscaling is not applied on ohos (original bytes are uploaded). |
| Local history (浏览历史) | **Works (compiled, fallback path)** | Drift/SQLite when the native asset loads, else SharedPreferences JSON capped at 200 rows |
| Read later (稍后阅读) | **Works (compiled, fallback path)** | same fallback design |
| Offline page cache | **Works (compiled, fallback path)** | same; fallback caps at 120 entries |
| Deep links — warm `mv2://` / https app links | **Missing** | `app_links` shim yields an empty stream; needs an ArkTS `want` handler. (Push-notification taps are handled separately by `HmsPushBridge.handleWant` — §3.4.) |
| Deep links — clipboard pasteboard detection | **Works (compiled)** | pure `Clipboard`, unaffected |
| Home-screen quick actions bridge | **Works (compiled)** | method channel only; the ohos side must implement it (§7) |
| Home-screen widget sync | **Works (compiled)** | method-channel `mv2/native`; no ohos service written yet |

### 4.1 Native assets and SQLite — **still the fallback path (blocked)**

`flutter build hap` runs the `sqlite3` package's Dart build hook and produces a
native asset that is bundled into the HAP:

```
libs/arm64-v8a/libsqlite3.so   1,722,264 bytes
ELF 64-bit LSB shared object, ARM aarch64
```

The fork patch in §1.1 makes `NativeAssetsManifest.json` ship too, and on device
the engine now **resolves** the asset — the old
`No asset with id 'package:sqlite3/src/ffi/libsqlite3.g.dart' found` is gone.
But `dlopen` then fails:

```
MV2: sqlite3 native asset unavailable, using prefs store:
Invalid argument(s): Couldn't resolve native function 'sqlite3_initialize' in
'package:sqlite3/src/ffi/libsqlite3.g.dart' : Failed to load dynamic library
'libsqlite3.so': ... Error loading shared library ld-linux-aarch64.so.1:
No such file or directory
(needed by /data/storage/el1/bundle/libs/arm64/libsqlite3.so)
```

`llvm-readelf -d` on the bundled `.so` shows why:

```
NEEDED  libc.so.6
NEEDED  ld-linux-aarch64.so.1
```

It is a **glibc/Linux aarch64** binary; HarmonyOS's loader is musl-based, so it
cannot be loaded. The build hook compiled it that way because the fork hands
hooks `targetOS: OS.linux` even for the ohos target
(`packages/flutter_tools/lib/src/isolated/native_assets/targets.dart`,
`OhosAssetTarget`, `// TODO(ohos): Revert to OS.ohos once hosted
package:code_assets recognizes OHOS`). Hosted `package:code_assets` 2.0.0 and
`native_toolchain_c` 0.19.4 have no OHOS target, so `CompilerResolver` falls
back to `aarch64LinuxGnuGcc` (glibc). This is an upstream toolchain limitation,
not fixable with a local `flutter_tools` one-liner: it needs either an
OHOS-aware `code_assets`/`native_toolchain_c` or a prebuilt OHOS
`libsqlite3.so` wired through the sqlite3 hook's `ExternalSqliteBinary` path.

Until then the Drift store stays on the designed fallback:
`cacheDatabaseProvider` (on ohos only) probes `sqlite3.openInMemory()`, the
probe throws, and it selects `OhosPrefsCacheDatabase` — a `CacheDatabase`
subclass backed by `shared_preferences`.
`lib/core/storage/ohos_cache_database.dart` documents the fallback's limits
(JSON blobs, 120-entry page cache, 200-row history, no transactions). 浏览历史 /
稍后阅读 keep working through the fallback; the local DB is simply not the
primary store yet.

---

## 5. Tests

`flutter test` under the ohos SDK (final run):

```
303 passed, 8 skipped, 1 failed
```

(The `+4` over the previous count is `test/restricted_topic_test.dart` — three
redirect-classification tests plus the 去登录 widget test; the `+7`
`test/hms_push_gateway_test.dart` drives `HmsPushGateway` against fake
`mv2/push` channels.)

The single failure is the deliberate shim behaviour, not a regression:

* `test/topic_detail_page_test.dart` → *"分享 tapping 分享 invokes the platform
  share channel"* — asserts that `share_plus` writes to its platform channel.
  The ohos shim throws instead, and the app's existing `catch` turns that into
  the clipboard fallback. The very next test in the same file, *"a failing share
  channel falls back to the clipboard"*, still passes — i.e. what the user
  actually experiences is covered and green.

**`test/native_bridge_test.dart` now passes** (it was the extra failure in the
previous baseline). Root cause: `SettingsController._hydrate` called
`SharedPreferences.getInstance()` unguarded, fire-and-forget from `build()`.
Where the plugin is unregistered — `flutter test` — that raises an *unhandled*
`MissingPluginException`, which fails whichever test first reads
`settingsProvider`. `native_bridge_test` reads it through
`pushServiceProvider.register` (`isEnabled`), and the ohos
`flutter_secure_storage` shim calls `SharedPreferences.getInstance()` as well
(cookie-jar read), so the latent mainline bug surfaced here and not upstream.
Fixed in `settings_controller.dart` (§3.3, reconciled note); the same unguarded call can
be reproduced deterministically in a two-line probe, and now degrades to the
defaults with a `MV2: settings storage unavailable` log line.

**`test/session_refresh_test.dart` is now order-independent.** It used to fail
when run alone with `MissingPluginException … getTemporaryDirectory on channel
plugins.flutter.io/path_provider`, thrown by Drift's `LazyDatabase` when
`recordHistory` constructs the file-backed `CacheDatabase` on the host (no
`path_provider` implementation in tests). The mainline test now overrides
`cacheDatabaseProvider` with an in-memory `NativeDatabase.memory()` executor —
mirrored here by the sync — so it passes run alone (verified) and in the full
suite without weakening any assertion. There is no longer an ordering
dependency between test files.

---

## 6. Keeping the Dart code in sync with `../app/`

```bash
./tool/sync-from-app.sh --dry-run   # show what would change
./tool/sync-from-app.sh             # mirror lib/ assets/ test/ from ../app
```

The script rsyncs `lib/`, `assets/` and `test/` one-way from `../app/` with
`--delete`, excluding exactly the six files in §3.3 plus everything listed in
its header comment (`pubspec.yaml`, `ohos/`, `README.md`, `tool/`, `shims/`,
`vendor/shadcn_ui/`). After a sync, re-run `pub get`, `analyze` and
`build hap --debug`.

If `../app/` grows a **new native plugin**, check pub.dev for an `*_ohos`
federated implementation first; if there is none, add a shim under `shims/` that
preserves the Dart API and point `pubspec.yaml` at it — do **not** fork page
code.

---

## 7. What the publisher must still do

1. **AppGallery Connect signing.** Delete the debug `signingConfigs` block in
   `ohos/build-profile.json5` and the whole `ohos/signing/` directory, then
   import the real release certificate and profile from DevEco Studio
   (*File → Project Structure → Signing Configs*). The checked-in material is
   generated by `tool/generate-ohos-debug-signing.sh` from the OpenHarmony
   **public demo keystore** bundled with DevEco Studio
   (`toolchains/lib/OpenHarmony.p12`). It exists only so `flutter build hap` can
   succeed offline; it is **not installable on a production HarmonyOS device and
   not publishable**.
2. **Real release build.** Configure `release` mode (obfuscation, ABI splits)
   once release signing exists; this variant was only validated in `debug`.
3. **HMS Push Kit (AGC configuration).** The client and worker halves are
   implemented (§3.4); what is missing is the AppGallery Connect project:
   1. Create a **HarmonyOS app** in AppGallery Connect and set its
      **bundle name to exactly** `ohos/AppScope/app.json5`'s `bundleName`
      (currently `com.rwecho.mv2`, which the publisher should also fix — see
      item 9).
   2. Enable **Push Kit** for the app and download
      **`agconnect-services.json`** (*Project settings → General information →
      App* / *Push Kit*). Drop it at **`ohos/entry/agconnect-services.json`**
      (the entry module root, next to `oh-package.json5`). It is git-ignored —
      it holds project secrets and must never be committed.
   3. Replace the placeholder in **`ohos/entry/src/main/module.json5`**
      (`metadata` → `client_id`) with the app's real **client_id**. The
      `HmsPushBridge` treats the placeholder as "unconfigured" and leaves push
      off.
   4. In the Cloudflare worker, set `HMS_APP_ID` (AGC **App ID**, in
      `wrangler.toml` `[vars]`) and the secret
      `HMS_SERVICE_ACCOUNT_JSON` (AGC **service-account key file**, *Project
      settings → Service accounts*). The worker mints an OAuth2 token from the
      JWT assertion and caches it in KV (`cloudflare/README.md`).
   5. Use **release/AppGallery signing** (item 1): an unsigned debug build
      fails `getToken` with `1000900010 Illegal application identity`.
   No ohpm dependency is required: `@kit.PushKit` ships with the DevEco
   HarmonyOS SDK and is resolved because the `default` product sets
   `runtimeOS: "HarmonyOS"`.
4. **Secure storage.** Replace `shims/flutter_secure_storage` with a
   HUKS/keystore-backed implementation so the V2EX session cookie is not kept in
   plain `SharedPreferences`.
5. **Image picker — done.** `shims/image_picker` is gone; the composer picks
   photos through `OhosImagePicker` + the ArkTS `photoAccessHelper` bridge
   (§3.6). Remaining polish: downscale in ArkTS before upload.
6. **Deep links.** Add an ArkTS `want` handler and a real `AppLinks` platform
   implementation behind `shims/app_links`.
7. **Share sheet.** Replace `shims/share_plus` with the ohos system share sheet.
8. **Native bridges.** Implement the `mv2/native` method channel on the ohos
   side: `setWidgetSnapshot` (home-screen widget/service), `quickAction`,
   `consumePendingQuickAction`. They are silent no-ops today, which is by design
   (`Mv2NativeBridge` treats a missing native side as a no-op).
9. **Store metadata.** `ohos/AppScope/app.json5` and
   `ohos/entry/src/main/module.json5` still carry `flutter create` defaults
   (`com.rwecho.mv2`, label "mv2", template icons, `versionCode`/`versionName` =
   `1000000`/`1.0.0`) which do **not** match the pubspec
   `1.2.35+1002035000`. Set the real bundle id, name, icon and version.
10. **Device validation.** A first emulator smoke pass exists (install + launch +
    live home feed; see the banner in §1). Now also verified on the emulator:
    the composer image picker + Imgur upload (§3.6, three screenshots) and the
    login form's captcha re-render after a failed submit (§3.7; the second POST
    could not be read back because the test tripped V2EX's IP sign-in cooldown).
    Still unverified on hardware: the ArkWeb-backed reader
    (`webview_flutter_ohos`) — the highest-risk dependency —
    session persistence/cookies, and anything HMS that needs a real AGC project
    (token, notification delivery, notification-tap route). The SQLite path was
    exercised on device and is **blocked by the glibc native asset** (§4.1); the
    restricted-topic sign-in state is verified (§3.5).

---

## 8. Layout

```
app-ohos/
├── pubspec.yaml                 # pinned for Dart 3.11.5 + path deps on shims
├── README.md                    # this file
├── lib/                         # mirror of ../app/lib (see §3.3 for the differ list)
├── assets/  test/               # mirrors of ../app
├── ohos/                        # generated HarmonyOS project
│   ├── build-profile.json5      # signingConfigs (local debug)
│   ├── signing/                 # generated debug keystore / profile / material
│   └── entry/
│       ├── agconnect-services.json   # publisher-supplied AGC config (git-ignored)
│       └── src/main/ets/
│           ├── push/HmsPushBridge.ets          # HMS Push Kit + mv2/push bridge
│           └── plugins/ImagePickerBridge.ets   # photoAccessHelper + mv2/image_picker bridge
├── shims/                       # 5 local stand-in packages (see §3.2)
├── vendor/shadcn_ui/            # 0.56.3 + 4 TargetPlatform.ohos patches
└── tool/
    ├── sync-from-app.sh             # one-way mirror from ../app
    ├── generate-ohos-debug-signing.sh
    └── generate-ohos-signing-material.js
```
