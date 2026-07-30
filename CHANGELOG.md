# Changelog

All notable changes to `sghimire/mobile-browser` are documented in this file.

## [1.0.0] - 2026-07-28

Initial release.

### Added

- Native in-app browsing for NativePHP Mobile apps, powered by `android.webkit.WebView` (Android) and `WKWebView` (iOS).
- Two modes per call: `webview` (full-screen in-app browser with a compact header — smart back button, page title, and an overflow menu with Open in Chrome/Safari, Refresh, Copy Link, and Share) or `external` (hands the URL to the device's default browser and leaves the app).
- OAuth sign-in via a dedicated `auth()` builder — presents the authorize URL in an isolated system browser context (`ASWebAuthenticationSession` on iOS, Chrome Custom Tabs on Android) and captures the redirect automatically.
- Laravel facade (`Browser`) and fluent, chainable builders in PHP and JS, plus a `browser.d.ts` type declaration file.
- `Opened`, `Closed`, and `AuthCompleted` Laravel events — usable with `Event::listen()` or bound directly to a Livewire method via `#[OnNative]`.
- Programmatic close for an open in-app browser session or an in-progress sign-in.
- Redesigned iOS `BrowserViewController` toolbar with updated system colors and back/forward navigation gestures, matching the Android header.
- Native Kotlin (Android) and Swift (iOS) bridge implementation — a standalone, free plugin with no paid equivalent to depend on.
- MIT LICENSE and README with full usage documentation.
