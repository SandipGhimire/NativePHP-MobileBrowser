const baseUrl = "/_native/api/call";

const VALID_MODES = ["webview", "external"];
const REDIRECT_SCHEME = "nativephp";

async function bridgeCall(method, params = {}) {
  const response = await fetch(baseUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-TOKEN":
        document.querySelector('meta[name="csrf-token"]')?.content || "",
    },
    body: JSON.stringify({ method, params }),
  });

  const result = await response.json();

  if (result.status === "error") {
    const error = new Error(
      result.message || "The browser could not be opened.",
    );
    error.code = result.code;
    throw error;
  }

  return result.data;
}

class PendingOpen {
  constructor(url) {
    if (typeof url !== "string" || url.trim() === "") {
      throw new Error("A URL must be provided.");
    }

    this._url = url;
    this._id = null;
    this._mode = "webview";
    this._title = null;
    this._showToolbar = true;
    this._showNavigationButtons = true;
    this._shareButton = true;
    this._desktopMode = false;
    this._started = false;
  }

  mode(mode) {
    if (!VALID_MODES.includes(mode)) {
      throw new Error(
        `Invalid browser mode: ${mode}. Valid modes are: ${VALID_MODES.join(", ")}.`,
      );
    }
    this._mode = mode;
    return this;
  }

  external(external = true) {
    return this.mode(external ? "external" : "webview");
  }

  title(title) {
    this._title = title;
    return this;
  }

  showToolbar(enabled = true) {
    this._showToolbar = enabled;
    return this;
  }

  showNavigationButtons(enabled = true) {
    this._showNavigationButtons = enabled;
    return this;
  }

  shareButton(enabled = true) {
    this._shareButton = enabled;
    return this;
  }

  desktopMode(enabled = true) {
    this._desktopMode = enabled;
    return this;
  }

  id(id) {
    this._id = id;
    return this;
  }

  getId() {
    return this._id;
  }

  then(resolve, reject) {
    if (this._started) {
      return resolve();
    }
    this._started = true;

    return bridgeCall("MobileBrowser.Open", {
      url: this._url,
      mode: this._mode,
      title: this._title,
      showToolbar: this._showToolbar,
      showNavigationButtons: this._showNavigationButtons,
      shareButton: this._shareButton,
      desktopMode: this._desktopMode,
      id: this._id,
    }).then(resolve, reject);
  }
}

class PendingAuth {
  constructor(url, redirectUri) {
    if (typeof url !== "string" || url.trim() === "") {
      throw new Error("An authorize URL must be provided.");
    }

    let scheme;
    try {
      scheme = new URL(redirectUri).protocol.replace(/:$/, "");
    } catch {
      scheme = null;
    }

    if (!scheme) {
      throw new Error(
        `A redirectUri with a scheme must be provided, e.g. ${REDIRECT_SCHEME}://127.0.0.1/auth/callback.`,
      );
    }

    if (scheme !== REDIRECT_SCHEME) {
      throw new Error(
        `redirectUri must use the "${REDIRECT_SCHEME}://" scheme so the OAuth callback can be routed back into the app, e.g. ${REDIRECT_SCHEME}://127.0.0.1/auth/callback.`,
      );
    }

    this._url = url;
    this._redirectUri = redirectUri;
    this._id = null;
    this._ephemeral = true;
    this._started = false;
  }

  ephemeral(enabled = true) {
    this._ephemeral = enabled;
    return this;
  }

  id(id) {
    this._id = id;
    return this;
  }

  getId() {
    return this._id;
  }

  then(resolve, reject) {
    if (this._started) {
      return resolve();
    }
    this._started = true;

    return bridgeCall("MobileBrowser.Auth", {
      url: this._url,
      redirectUri: this._redirectUri,
      ephemeral: this._ephemeral,
      id: this._id,
    }).then(resolve, reject);
  }
}

export const Browser = {
  open: (url) => new PendingOpen(url),

  auth: (url, redirectUri) => new PendingAuth(url, redirectUri),

  close: (id) => bridgeCall("MobileBrowser.Close", { id: id ?? null }),
};

export { PendingOpen, PendingAuth };

const _eventListeners = {};
let _listenerInstalled = false;

function installListener() {
  if (_listenerInstalled) {
    return;
  }

  document.addEventListener("native-event", (e) => {
    const eventName = e.detail.event.replace(/^(\\)+/, "");
    const payload = e.detail.payload;
    (_eventListeners[eventName] || []).forEach((callback) =>
      callback(payload, eventName),
    );
  });

  _listenerInstalled = true;
}

export function On(eventName, callback) {
  installListener();
  (_eventListeners[eventName] ??= []).push(callback);
}

export function Off(eventName, callback) {
  if (_eventListeners[eventName]) {
    _eventListeners[eventName] = _eventListeners[eventName].filter(
      (cb) => cb !== callback,
    );
  }
}

export const Events = {
  Browser: {
    Opened: "Sandip\\Browser\\Native\\Events\\Browser\\Opened",
    Closed: "Sandip\\Browser\\Native\\Events\\Browser\\Closed",
    AuthCompleted: "Sandip\\Browser\\Native\\Events\\Browser\\AuthCompleted",
  },
};

export default { Browser, On, Off, Events, PendingOpen, PendingAuth };
