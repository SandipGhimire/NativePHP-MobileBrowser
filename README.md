# Mobile Browser

Native in-app browsing for [NativePHP Mobile](https://nativephp.com) apps, powered by `android.webkit.WebView` on Android and `WKWebView` on iOS — with a one-line escape hatch to hand a URL off to the device's external default browser instead, and a proper native OAuth flow for signing in with a third-party provider.

This package is a **free, self-contained plugin**. It ships its own Laravel facade, fluent builders, Laravel events, JS/TypeScript bindings, and the native Kotlin/Swift implementation — no paid plugin dependency.

## Features

- Two modes per call: `webview` (full-screen in-app browser with a compact, modern header — smart back button, page title, and an overflow menu with Open in Chrome/Safari, Refresh, Copy Link, and Share — that follows the device's light/dark theme automatically) or `external` (hands the URL to the device's default browser app and leaves yours).
- **OAuth sign-in** via a dedicated `auth()` builder — presents the authorize URL in a secure, isolated system browser context (`ASWebAuthenticationSession` on iOS, Chrome Custom Tabs on Android) and captures the redirect for you, with no embedded-WebView login screen (which most providers, including Google, reject).
- Fluent, chainable builders in both PHP and JavaScript.
- Programmatically close an open in-app browser session or cancel an in-progress sign-in.
- `Opened`, `Closed`, and `AuthCompleted` Laravel events, or bind straight to Livewire with `#[OnNative]`.
- Works from PHP (Blade/Livewire) and from JavaScript (Vue, React, Inertia, or plain JS).

## Requirements

- PHP ^8.2
- [`nativephp/mobile`](https://nativephp.com) ^3.0
- `livewire/livewire` — only needed if you use the `#[OnNative]` attribute

## Installation

```bash
composer require sghimire/mobile-browser
```

Laravel's package auto-discovery registers `BrowserServiceProvider` for you. Then register the plugin with NativePHP:

```bash
php artisan native:plugin:register
```

This wires up the plugin's `nativephp.json` manifest (bridge functions, Android `INTERNET` permission) into your native build. Rebuild/reinstall the native shell afterwards (`php artisan native:install` or `native:run`) so it's picked up.

## How It Works (Under the Hood)

Same two-phase pattern as every async call in this plugin family — a synchronous "start" acknowledgement, then the real result delivered later through two parallel channels.

1. **Request out.** `Browser::open($url)->open()` (PHP) and `Browser.open(url)` (JS) both reach the same bridge — JS via `fetch('/_native/api/call', { method: 'MobileBrowser.Open', params })`, PHP via `nativephp_call('MobileBrowser.Open', json_encode($params))`. The bridge router matches `"MobileBrowser.Open"` to `BrowserFunctions.Open`.
2. **Immediate ack.** The call returns right away confirming the request was accepted — not that the page has loaded (webview mode) or that the external browser actually opened.
3. **Result comes back later, twice.** In `webview` mode, once the page finishes its first load, the native side injects a `native-event` `CustomEvent` on `document` (what the JS `On()`/`Off()` helpers listen for) *and* makes a call back into Laravel that dispatches the real `Opened` event (what `Event::listen()` / `#[OnNative]` pick up). Closing the browser delivers `Closed` the same way. In `external` mode, `Opened` fires as soon as the OS confirms the hand-off succeeded; a failed hand-off (no browser available, bad URL) is returned as a synchronous bridge error instead.
4. Because results are asynchronous and delivered to PHP and JS independently, always drive your UI from the `Opened` / `Closed` events — never from the return value of `open()`.
5. `Browser::auth($authorizeUrl, $redirectUri)->auth()` follows the identical two-phase pattern over `MobileBrowser.Auth` / `BrowserFunctions.Auth`: an immediate ack that the sign-in was presented, followed later by `AuthCompleted` (the callback URL arrived) or `Closed` (cancelled or failed).

---

## In-app browser UI

The `webview` mode overlay uses a compact, modern header — the same shape as Instagram's or Chrome Custom Tabs' in-app browser, not a full custom chrome — and it's the same on both platforms:

- **Back button** — always smart: walks back through the page's own navigation history if there is any, otherwise closes the overlay. This matches the OS hardware-back/swipe-back gesture, which behaves the same way regardless of any setting below.
- **Two-line title** — the page's own `<title>` on top, updating live as the user navigates, with your `->title()` override underneath as a smaller subtitle (hidden if you never set one).
- **Overflow menu (⋮)** — Open in Chrome (Android) / Open in Safari (iOS), Refresh, Copy Link, and Share — Share only appears if `shareButton(true)` (the default).
- **System theme aware** — header colors, text, icon tint, status bar contrast (Android), and the webview background all switch with the OS light/dark setting automatically. Nothing to configure.

`showToolbar(false)` hides this header entirely, leaving a bare webview (e.g. a kiosk-style page). `showNavigationButtons(false)` changes what a *tap on the header's back button* does — it stops walking page history and just closes the overlay instead; it has no effect on the hardware/gesture back, which always tries page history first either way.

There's no separate back/forward/reload bar anymore — reload moved into the overflow menu, and forward navigation was dropped in favor of this simpler, single-header layout.

---

## PHP Usage

### The `Browser` facade

```php
use Sandip\Browser\Native\Facades\Browser;

// Open a URL in the in-app browser (default mode)
Browser::open('https://example.com')->open();

// Hand it off to the device's external browser instead
Browser::open('https://example.com')->external()->open();

// Fully configured in-app browser
Browser::open('https://example.com')
    ->id('support-page')                // correlate this session with its events
    ->title('Support')                   // subtitle shown under the page's own title
    ->showNavigationButtons(true)        // header back button can walk page history
    ->shareButton(true)                  // "Share…" entry in the overflow menu
    ->desktopMode(false)                 // request the mobile site (default)
    ->open();
```

`open()` on the builder returns `bool` — `true` once the request reached the native bridge, `false` if it couldn't be started (e.g. running outside the native shell, or the builder was already opened once).

If you never call `->open()` explicitly, it fires automatically when the builder object is destructed. Calling `->open()` yourself is recommended so you can check the return value.

#### Builder methods

| Method | Description |
|---|---|
| `mode(string $mode)` | `'webview'` (default) or `'external'`. Throws `InvalidArgumentException` if unknown. |
| `external(bool $external = true)` | Shortcut for `mode('external')` / `mode('webview')`. |
| `title(string $title)` | Subtitle shown under the page's own title in the header, `webview` mode. Header shows just the page title if you don't set this. |
| `showToolbar(bool $enabled = true)` | Show/hide the compact header (back button, title, overflow menu) in `webview` mode. |
| `showNavigationButtons(bool $enabled = true)` | Whether tapping the header's back button can walk the page's own navigation history before closing the overlay. Hardware/gesture back is unaffected. |
| `shareButton(bool $enabled = true)` | Show/hide "Share…" in the header's overflow menu. |
| `desktopMode(bool $enabled = true)` | Request a desktop user agent instead of the mobile one. `webview` mode only. |
| `id(string $id)` | Custom correlation ID for this session (not auto-generated — `null` unless set). |
| `getId()` | Get this session's correlation ID, or `null`. |
| `open()` | Send the open request to the native bridge. Returns `bool`. |

#### Supported modes

`webview`, `external` (also available as `PendingOpen::MODES`). Defaults to `webview` if `mode()` / `external()` is never called.

### Closing an in-app browser

Useful for dismissing an open `webview` session programmatically (e.g. from elsewhere in the UI once a task completes):

```php
use Sandip\Browser\Native\Facades\Browser;

Browser::close();                  // close whatever in-app browser is open
Browser::close('support-page');    // close a specific session by id
```

This fires `Closed` with `reason: 'closed_by_app'`. It has no effect on a URL opened with `external()`, since that leaves your app entirely. `Browser::close()` also cancels an in-progress `auth()` sign-in — see below.

### OAuth sign-in with `auth()`

`open()` is deliberately **not** meant for logging a user into a third-party provider — most providers (Google included) detect and reject sign-in attempts from an embedded WebView ("Error 403: disallowed_useragent"), and even where it's not blocked outright, an app-controlled WebView can read the password field, which is exactly what OAuth exists to avoid. `auth()` runs the authorization-code flow in a proper isolated system browser context instead:

- **iOS**: [`ASWebAuthenticationSession`](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) — the platform API built for this, with optional Safari cookie sharing for SSO.
- **Android**: [Chrome Custom Tabs](https://developer.chrome.com/docs/android/custom-tabs) launched from a dedicated redirect-handling activity — the same pattern used by [AppAuth-Android](https://github.com/openid/AppAuth-Android).

```php
use Sandip\Browser\Native\Facades\Browser;

Browser::auth(
    'https://provider.com/oauth/authorize?response_type=code&client_id=123&redirect_uri=nativephp%3A%2F%2F127.0.0.1%2Fauth%2Fcallback&state=xyz',
    'nativephp://127.0.0.1/auth/callback'
)->id('sign-in')->auth();
```

The two arguments are `Browser::auth(string $authorizeUrl, string $redirectUri)`:

- `$authorizeUrl` — the full provider authorize URL, built however you like (query string assembled by hand, a package like `league/oauth2-client`, etc.). It must itself already contain a `redirect_uri` parameter matching `$redirectUri` — that's what tells the *provider* where to send the browser back to; the second argument is what tells *this plugin* which incoming URL to treat as that callback and intercept.
- `$redirectUri` — **must use the `nativephp://` scheme**, e.g. `nativephp://127.0.0.1/auth/callback`. Host and path are yours to choose freely (useful if you run more than one OAuth flow), but the scheme itself is fixed on both platforms: Android can only route a callback back into the app through a scheme registered in the compiled AndroidManifest at build time (there's no way to register one dynamically per PHP call), so every app using this plugin shares the one `nativephp://` scheme rather than something derived per-app. Register exactly this redirect URI with your OAuth provider.

#### Builder methods

| Method | Description |
|---|---|
| `ephemeral(bool $enabled = true)` | Use a private browsing session with no shared cookies/SSO state, so the provider always shows a fresh login instead of silently reusing a previous session. Defaults to `true`. On iOS this maps directly to `prefersEphemeralWebBrowserSession`; Android's `CookieManager` has no per-session scoping, so this clears the app's WebView cookie jar before presenting the Custom Tab instead — see the platform notes below. |
| `id(string $id)` | Custom correlation ID for this session. |
| `getId()` | Read the current correlation ID, or `null`. |
| `auth()` | Send the request to the native bridge. Returns `bool`. |

If you never call `->auth()` explicitly, it fires automatically when the builder object is destructed, same as `open()`.

#### Handling the result

```php
use Sandip\Browser\Native\Events\Browser\AuthCompleted;
use Sandip\Browser\Native\Events\Browser\Closed;
use Illuminate\Support\Facades\Event;

Event::listen(function (AuthCompleted $event) {
    $event->callbackUrl; // string — the full redirect URL the provider sent, e.g. "nativephp://127.0.0.1/auth/callback?code=...&state=..."
    $event->params;      // array<string, string> — every query AND fragment parameter already parsed out for you (code, state, access_token, error, ...)
    $event->id;           // ?string

    // Exchange the code for tokens exactly as you would in a normal web OAuth flow.
    $tokens = Http::asForm()->post('https://provider.com/oauth/token', [
        'grant_type' => 'authorization_code',
        'code' => $event->params['code'],
        'redirect_uri' => 'nativephp://127.0.0.1/auth/callback',
        'client_id' => config('services.provider.client_id'),
        'client_secret' => config('services.provider.client_secret'),
    ])->json();
});

Event::listen(function (Closed $event) {
    // Also fires here if the flow started with auth() - reason will be one of:
    // "user_cancelled", "closed_by_app", "auth_failed", "no_browser_available".
    $event->reason;
    $event->id;
});
```

`$event->params` already has both grant types covered: authorization-code flows return `code`/`state` as query parameters, implicit-grant flows return `access_token`/`token_type`/etc. in the URL fragment — both are parsed into the same flat array.

Cancel a sign-in in progress the same way you'd close a browser session:

```php
Browser::close('sign-in');
```

### Listening for results

```php
use Sandip\Browser\Native\Events\Browser\Opened;
use Sandip\Browser\Native\Events\Browser\Closed;
use Illuminate\Support\Facades\Event;

Event::listen(function (Opened $event) {
    $event->url;    // string — the URL that was opened
    $event->mode;   // string — "webview" or "external"
    $event->id;     // ?string — matches the id you passed to ->id(), if any
});

Event::listen(function (Closed $event) {
    $event->reason; // ?string — e.g. "user_closed", "closed_by_app", "load_error", "no_browser_available"
    $event->id;     // ?string
});
```

### Livewire: `#[OnNative]`

```php
use Livewire\Component;
use Sandip\Browser\Native\Attributes\OnNative;
use Sandip\Browser\Native\Events\Browser\Opened;
use Sandip\Browser\Native\Events\Browser\Closed;
use Sandip\Browser\Native\Events\Browser\AuthCompleted;
use Sandip\Browser\Native\Facades\Browser;

class SupportBrowser extends Component
{
    public bool $isOpen = false;

    public function openSupport(): void
    {
        Browser::open('https://example.com/support')->id('support-page')->open();
    }

    public function signIn(): void
    {
        Browser::auth($this->buildAuthorizeUrl(), 'nativephp://127.0.0.1/auth/callback')
            ->id('sign-in')
            ->auth();
    }

    #[OnNative(Opened::class)]
    public function onOpened(string $url, string $mode, ?string $id): void
    {
        $this->isOpen = true;
    }

    #[OnNative(Closed::class)]
    public function onClosed(?string $reason, ?string $id): void
    {
        $this->isOpen = false;
    }

    #[OnNative(AuthCompleted::class)]
    public function onAuthCompleted(string $callbackUrl, array $params, ?string $id): void
    {
        // exchange $params['code'] for tokens, log the user in, etc.
    }
}
```

---

## JavaScript Usage

### Importing

This package doesn't publish a `#nativephp` import alias (that's reserved for NativePHP's first-party plugins). Import the file directly — either from the vendor path, or copy it into your own `resources/js/` and import it from there:

```js
import { Browser, On, Off, Events } from '../../vendor/sghimire/mobile-browser/resources/js/browser.js';
```

Full TypeScript types (including the `BrowserMode` union) are included in `browser.d.ts` alongside it.

### Basic open

`Browser.open(url)` returns a thenable builder — `await` it directly, or chain builder methods first:

```js
import { Browser } from '../../vendor/sghimire/mobile-browser/resources/js/browser.js';

await Browser.open('https://example.com');

// or fully configured
await Browser.open('https://example.com')
  .id('support-page')
  .title('Support')
  .showNavigationButtons(true)
  .shareButton(true);

// external browser
await Browser.open('https://example.com').external();
```

### Closing an in-app browser

```js
import { Browser } from '../../vendor/sghimire/mobile-browser/resources/js/browser.js';

await Browser.close();                // close whatever in-app browser is open
await Browser.close('support-page');  // close a specific session by id
```

### OAuth sign-in

`Browser.auth(authorizeUrl, redirectUri)` runs the same native OAuth flow as the PHP `auth()` builder (see the PHP section above for the full explanation of why this exists instead of just using `open()`, and why `redirectUri` must use the `nativephp://` scheme):

```js
import { Browser, On, Off, Events } from '../../vendor/sghimire/mobile-browser/resources/js/browser.js';

function handleAuthCompleted(payload) {
  // payload: { callbackUrl: string, params: Record<string, string>, id: string | null }
  const { code, state } = payload.params;
  // exchange `code` for tokens from your backend
}

On(Events.Browser.AuthCompleted, handleAuthCompleted);

await Browser.auth(
  'https://provider.com/oauth/authorize?response_type=code&client_id=123&redirect_uri=nativephp%3A%2F%2F127.0.0.1%2Fauth%2Fcallback&state=xyz',
  'nativephp://127.0.0.1/auth/callback',
).id('sign-in');

// cancel a sign-in in progress the same way as closing a browser session
await Browser.close('sign-in');
```

### Listening for events

```js
import { Browser, On, Off, Events } from '../../vendor/sghimire/mobile-browser/resources/js/browser.js';

function handleOpened(payload) {
  // payload: { url: string, mode: 'webview' | 'external', id: string | null }
}

function handleClosed(payload) {
  // payload: { reason: string | null, id: string | null }
}

On(Events.Browser.Opened, handleOpened);
On(Events.Browser.Closed, handleClosed);

// later, e.g. on component unmount
Off(Events.Browser.Opened, handleOpened);
Off(Events.Browser.Closed, handleClosed);
```

### React example

```jsx
import { useState, useEffect, useCallback } from 'react';
import { Browser, On, Off, Events } from '../../vendor/sghimire/mobile-browser/resources/js/browser.js';

export function SupportLink() {
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    const handleOpened = () => setIsOpen(true);
    const handleClosed = () => setIsOpen(false);
    On(Events.Browser.Opened, handleOpened);
    On(Events.Browser.Closed, handleClosed);
    return () => {
      Off(Events.Browser.Opened, handleOpened);
      Off(Events.Browser.Closed, handleClosed);
    };
  }, []);

  const openSupport = useCallback(() => {
    Browser.open('https://example.com/support').title('Support');
  }, []);

  return <button onClick={openSupport}>{isOpen ? 'Support open…' : 'Get support'}</button>;
}
```

### JS API reference

| Export | Signature | Description |
|---|---|---|
| `Browser.open(url)` | `(string) => PendingOpen` | Start building an open request. |
| `.mode(mode)` | `(BrowserMode) => this` | `'webview'` or `'external'`. Throws if unknown. |
| `.external(external?)` | `(boolean = true) => this` | Shortcut for `mode('external')` / `mode('webview')`. |
| `.title(title)` | `(string) => this` | Subtitle shown under the page's own title in the header, `webview` mode only. |
| `.showToolbar(enabled?)` | `(boolean = true) => this` | Show/hide the compact header (back button, title, overflow menu). |
| `.showNavigationButtons(enabled?)` | `(boolean = true) => this` | Whether the header's back button can walk page history before closing the overlay. Hardware/gesture back is unaffected. |
| `.shareButton(enabled?)` | `(boolean = true) => this` | Show/hide "Share…" in the header's overflow menu. |
| `.desktopMode(enabled?)` | `(boolean = true) => this` | Request a desktop user agent. `webview` mode only. |
| `.id(id)` | `(string) => this` | Custom correlation ID. |
| `.getId()` | `() => string \| null` | Read the current correlation ID. |
| `Browser.auth(url, redirectUri)` | `(string, string) => PendingAuth` | Start building an OAuth sign-in request. `redirectUri` must use the `nativephp://` scheme. |
| `.ephemeral(enabled?)` | `(boolean = true) => this` | Use a private session with no shared cookies/SSO state. Defaults to `true`. |
| `Browser.close(id?)` | `(string?) => Promise<{ closed: boolean }>` | Dismiss the open in-app browser, or cancel an in-progress `auth()` sign-in. |
| `On(event, callback)` | `(string, (payload, eventName) => void) => void` | Subscribe to a native event. |
| `Off(event, callback)` | `(string, (payload, eventName) => void) => void` | Unsubscribe. |
| `Events.Browser.Opened` | `string` | Event name constant. |
| `Events.Browser.Closed` | `string` | Event name constant. |
| `Events.Browser.AuthCompleted` | `string` | Event name constant. |

`await`-ing (or `.then`-ing) a `PendingOpen`/`PendingAuth` sends the request to the native bridge exactly once — awaiting it twice is a no-op the second time.

---

## Events reference

### `Opened`

Dispatched once the page has loaded (`webview` mode) or the OS confirms the hand-off succeeded (`external` mode).

| Property | Type | Description |
|---|---|---|
| `url` | `string` / `string` | The URL that was opened. |
| `mode` | `string` / `'webview' \| 'external'` | Which mode served the request. |
| `id` | `?string` / `string \| null` | The correlation ID from `.id()`, if one was set. |

### `Closed`

Dispatched when the in-app browser is dismissed, when an `external` hand-off fails, or when an `auth()` sign-in ends without completing.

| Property | Type | Description |
|---|---|---|
| `reason` | `?string` / `string \| null` | Browsing: `"user_closed"`, `"closed_by_app"`, `"replaced"`, `"load_error"`, `"invalid_url"`, `"no_browser_available"`, `"launch_failed"`. Sign-in: `"user_cancelled"`, `"closed_by_app"`, `"replaced"`, `"auth_failed"`, `"no_browser_available"`, `"invalid_url"`. Never `null` in practice. |
| `id` | `?string` / `string \| null` | The correlation ID from `.id()`, if one was set. |

### `AuthCompleted`

Dispatched once the OAuth provider redirects back to `redirectUri` after `auth()`.

| Property | Type | Description |
|---|---|---|
| `callbackUrl` | `string` / `string` | The full callback URL exactly as the provider sent it. |
| `params` | `array` / `Record<string, string>` | Every query **and** URL-fragment parameter, already parsed and merged into one flat map — covers both authorization-code (`code`, `state`) and implicit-grant (`access_token`, `token_type`, ...) flows. |
| `id` | `?string` / `string \| null` | The correlation ID from `.id()`, if one was set. |

- PHP classes: `Sandip\Browser\Native\Events\Browser\Opened`, `Sandip\Browser\Native\Events\Browser\Closed`, `Sandip\Browser\Native\Events\Browser\AuthCompleted`
- JS event name constants: `Events.Browser.Opened`, `Events.Browser.Closed`, `Events.Browser.AuthCompleted`

## Platform notes

| | Android | iOS |
|---|---|---|
| Min OS version | API 23 | 15.0 |
| Permission | `android.permission.INTERNET` | none |
| Native implementation | `resources/android/BrowserFunctions.kt` (`android.webkit.WebView`) | `resources/ios/BrowserFunctions.swift` (`WKWebView`) |
| External hand-off | `Intent.ACTION_VIEW` | `UIApplication.shared.open` |
| OAuth sign-in | Chrome Custom Tabs (`androidx.browser:browser`) + a dedicated `BrowserAuthActivity` that owns the `nativephp://` intent-filter | `ASWebAuthenticationSession` |

Both are configured automatically by `nativephp.json` — you don't need to edit native project files by hand.

### OAuth implementation notes and known limitations

- **Why not just use `open()` for sign-in?** Providers routinely detect and block embedded WebView user agents for OAuth (Google returns `Error 403: disallowed_useragent`), and it defeats one of OAuth's own purposes — the app hosting the WebView could otherwise read the password field. `auth()` presents the login in a context the app can't inspect.
- **`ephemeral()` on Android** clears the app's shared `CookieManager` cookie jar before presenting the Custom Tab. Android's `CookieManager` is process-wide rather than scoped to one WebView/tab, so this is an app-wide clear, not a perfectly isolated private session the way iOS's `prefersEphemeralWebBrowserSession` is. Avoid triggering `auth()` while another unrelated `webview`-mode `open()` session needs to keep its cookies.
- **Cancellation detection on Android** has no direct signal from Custom Tabs (unlike iOS, which gets an explicit cancellation callback). This plugin detects it by noticing the redirect-handling activity was resumed again without a matching callback ever arriving — reliable for the normal case (user backs out of the tab), but calling `Browser::close()` cannot force the Custom Tab itself to visually disappear if it's already in the foreground; it only dismisses this plugin's own state and fires `Closed`.
- **Process death mid-flow** (Android killing the app while the Custom Tab is open, e.g. under memory pressure) drops the in-memory session state, so a redirect arriving after that point can't be correlated back to a `Closed`/`AuthCompleted` dispatch. Uncommon, but a known limitation shared with most Custom-Tabs-based implementations that don't persist flow state to disk.
- **The `nativephp://` scheme is shared plugin-wide, not per-app-generated**, because Android intent-filters are compiled into the AndroidManifest at build time and can't be registered dynamically from a PHP call. Host and path in `redirectUri` are still yours to pick freely.

## Testing

```bash
composer install
composer test
```

Outside of a compiled native shell, `Browser::open($url)->open()` and `Browser::close()` return `false` (there's no bridge to call) — this is expected and is exactly what the test suite asserts.

## License

MIT
