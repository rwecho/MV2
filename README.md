# MV2

> **A modern V2EX client.**
>
> Flutter · iOS · Android · Open Source

**MV2** is a modern, open-source third-party client for the V2EX community. The current app is built with **Flutter** and focuses on a fast, native-feeling mobile experience with a consistent design system across iOS and Android.

The name **MV2** represents the product brand rather than a framework name. The visual identity uses a red/blue dual-choice motif; internally, we think of it as **Matrix for V2EX** — a compact identity for a different way into V2EX.

> MV2 is an independent third-party project and is not affiliated with or endorsed by V2EX.

---

## ✨ Highlights

- **Modern V2EX browsing** — home tabs, nodes, topic feeds and topic details.
- **Account experience** — sign in, account state, notifications and member pages.
- **Topic interaction** — reply, quote, thank, ignore and other V2EX-native interactions where supported.
- **Publishing** — create topics with node selection, Markdown preview and local draft persistence.
- **Native mobile UX** — haptics, modal sheets, pull-to-refresh, collapsible navigation and deep links.
- **Dark & light themes** — one consistent MV2 design system across platforms.
- **Offline-friendly development** — fixture-backed development mode plus the real V2EX site parser.
- **Notifications & widgets** — Firebase-backed notification infrastructure and native iOS widget support.

---

## 🧱 Tech Stack

### App

- **Flutter / Dart** — cross-platform application framework.
- **Riverpod** — application and feature state management.
- **go_router** — navigation and deep-link routing.
- **Dio** — HTTP networking.
- **Drift / SQLite** — local cache and persistence.
- **SharedPreferences / Secure Storage** — lightweight local settings and sensitive session state.
- **Firebase** — notification and app-service integrations used by the mobile client.

### Backend / Services

- **Cloudflare Workers** — lightweight service endpoints and push-related infrastructure.
- **V2EX** — content and account interactions come from V2EX APIs and web endpoints.

---

## 📁 Repository Structure

```text
.
├── app/                    # Flutter application
│   ├── lib/                # Dart source
│   ├── android/            # Android host project
│   ├── ios/                # iOS host project + MV2 widget integration
│   ├── assets/             # Fixtures and bundled resources
│   └── branding/           # MV2 logo and generated platform assets
├── cloudflare/             # Cloudflare Worker services
├── designs/                # Product/UI design references
├── docs/                   # Privacy, deletion and project documentation
└── .github/workflows/      # CI/CD for App Store / Google Play
```

For implementation details, see [`app/README.md`](app/README.md).

---

## 🚀 Development

### Requirements

- Flutter stable
- Dart (included with Flutter)
- Xcode for iOS builds
- Android Studio / Android SDK for Android builds

### Run locally

```bash
cd app
flutter pub get
flutter run
```

By default, MV2 can use bundled fixture pages for deterministic development. To run against the real V2EX site:

```bash
cd app
flutter run --dart-define=MV2_FIXTURES=false
```

### Quality checks

```bash
cd app
flutter analyze
flutter test
```

### Release builds

```bash
cd app
flutter build appbundle
flutter build ipa
```

Release CI is defined in `.github/workflows/publish-flutter.yml`. Pushing a `v*` tag triggers the store publishing workflow.

---

## 📱 Application Identity

The published application keeps the existing package / bundle identifiers for upgrade compatibility with previous MV2 releases.

For example, identifiers containing `v2ex.maui` are **legacy application identifiers**, not a statement about the current framework. They must not be casually renamed because changing them would create a different application in App Store / Google Play rather than update the existing one.

The current product implementation is Flutter.

---

## 🎨 Brand

**Product name:** MV2  
**Positioning:** A modern V2EX client  
**Internal brand idea:** Matrix for V2EX

The MV2 mark is built around two symmetrical red and blue capsule forms. Brand source files and generation notes live in [`app/branding/`](app/branding/).

---

## 🔐 Privacy & Legal

- [Privacy Policy](https://rwecho.github.io/V2ex.Maui2/privacy.html)
- [Data Deletion](https://rwecho.github.io/V2ex.Maui2/deletion.html)

MV2 is a third-party client. V2EX content, accounts and platform behavior remain subject to V2EX's own terms and policies.

---

## 🙏 Credits

- [V2EX](https://www.v2ex.com/)
- [Flutter](https://flutter.dev/)
- The open-source packages and projects used by MV2

---

## 📧 Contact

- Email: [rwecho@live.com](mailto:rwecho@live.com)

---

## License

This project is licensed under the [MIT License](LICENSE).
