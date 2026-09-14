import 'fixture_api.dart';

/// The offline fixture data source, pre-configured with zero latency, for
/// tests that need data.
///
/// The shipped app never falls back to fixtures — it only talks to the live
/// site and renders an error state when that fails — so every widget/unit test
/// that needs data **must** inject this explicitly:
///
/// ```dart
/// ProviderContainer(
///   overrides: [v2exApiProvider.overrideWithValue(fixtureApi())],
/// )
/// ```
///
/// `riverpod` does not export its `Override` type, so this stays a factory
/// rather than a ready-made container.
FixtureV2exApi fixtureApi() => FixtureV2exApi(latency: Duration.zero);
