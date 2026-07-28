# Mobile Browser

Native in-app browsing for [NativePHP Mobile](https://nativephp.com) apps, powered by `android.webkit.WebView` on Android and `WKWebView` on iOS — with a one-line escape hatch to hand a URL off to the device's external default browser instead.

This package is a **free, self-contained plugin**. It ships its own Laravel facade, a fluent open builder, Laravel events, JS/TypeScript bindings, and the native Kotlin/Swift implementation — no paid plugin dependency, no extra native libraries (both platforms' web views ship with the OS).

## Features

- Two modes per call: `webview` (full-screen in-app browser with toolbar, back/forward/reload, and a share button) or `external` (hands the URL to the device's default browser app and leaves yours).
- Fluent, chainable open builder in both PHP and JavaScript.
- Programmatically close an open in-app browser session.
- `Opened` and `Closed` Laravel events, or bind straight to Livewire with `#[OnNative]`.
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
    ->title('Support')                   // toolbar title override
    ->showNavigationButtons(true)        // back/forward/reload bar
    ->shareButton(true)                  // share button in the toolbar
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
| `title(string $title)` | Toolbar title override for `webview` mode. Defaults to the page's own `<title>` once loaded. |
| `showToolbar(bool $enabled = true)` | Show/hide the top toolbar (close, title, share) in `webview` mode. |
| `showNavigationButtons(bool $enabled = true)` | Show/hide the back/forward/reload bar in `webview` mode. |
| `shareButton(bool $enabled = true)` | Show/hide the share button on the toolbar. |
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

This fires `Closed` with `reason: 'closed_by_app'`. It has no effect on a URL opened with `external()`, since that leaves your app entirely.

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
use Sandip\Browser\Native\Facades\Browser;

class SupportBrowser extends Component
{
    public bool $isOpen = false;

    public function openSupport(): void
    {
        Browser::open('https://example.com/support')->id('support-page')->open();
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
| `.title(title)` | `(string) => this` | Toolbar title override, `webview` mode only. |
| `.showToolbar(enabled?)` | `(boolean = true) => this` | Show/hide the top toolbar. |
| `.showNavigationButtons(enabled?)` | `(boolean = true) => this` | Show/hide the back/forward/reload bar. |
| `.shareButton(enabled?)` | `(boolean = true) => this` | Show/hide the share button. |
| `.desktopMode(enabled?)` | `(boolean = true) => this` | Request a desktop user agent. `webview` mode only. |
| `.id(id)` | `(string) => this` | Custom correlation ID. |
| `.getId()` | `() => string \| null` | Read the current correlation ID. |
| `Browser.close(id?)` | `(string?) => Promise<{ closed: boolean }>` | Dismiss the open in-app browser. |
| `On(event, callback)` | `(string, (payload, eventName) => void) => void` | Subscribe to a native event. |
| `Off(event, callback)` | `(string, (payload, eventName) => void) => void` | Unsubscribe. |
| `Events.Browser.Opened` | `string` | Event name constant. |
| `Events.Browser.Closed` | `string` | Event name constant. |

`await`-ing (or `.then`-ing) a `PendingOpen` sends the request to the native bridge exactly once — awaiting it twice is a no-op the second time.

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

Dispatched when the in-app browser is dismissed, or when an `external` hand-off fails.

| Property | Type | Description |
|---|---|---|
| `reason` | `?string` / `string \| null` | `"user_closed"` when the user taps close, `"closed_by_app"` when closed via `close()`, `"replaced"` when superseded by a new `open()` call, `"load_error"`, `"invalid_url"`, `"no_browser_available"`, `"launch_failed"`. Never `null` in practice. |
| `id` | `?string` / `string \| null` | The correlation ID from `.id()`, if one was set. |

- PHP classes: `Sandip\Browser\Native\Events\Browser\Opened`, `Sandip\Browser\Native\Events\Browser\Closed`
- JS event name constants: `Events.Browser.Opened`, `Events.Browser.Closed`

## Platform notes

| | Android | iOS |
|---|---|---|
| Min OS version | API 23 | 15.0 |
| Permission | `android.permission.INTERNET` | none |
| Native implementation | `resources/android/BrowserFunctions.kt` (`android.webkit.WebView`) | `resources/ios/BrowserFunctions.swift` (`WKWebView`) |
| External hand-off | `Intent.ACTION_VIEW` | `UIApplication.shared.open` |

Both are configured automatically by `nativephp.json` — you don't need to edit native project files by hand.

## Testing

```bash
composer install
composer test
```

Outside of a compiled native shell, `Browser::open($url)->open()` and `Browser::close()` return `false` (there's no bridge to call) — this is expected and is exactly what the test suite asserts.

## License

MIT
