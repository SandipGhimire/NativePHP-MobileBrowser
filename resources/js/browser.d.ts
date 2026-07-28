export type BrowserMode = "webview" | "external";

export interface BridgeError extends Error {
  code?: string;
}

export interface OpenStartedResult {
  started: true;
}

export interface CloseResult {
  closed: boolean;
}

export interface BrowserOpenedPayload {
  url: string;
  mode: BrowserMode;
  id: string | null;
}

export interface BrowserClosedPayload {
  reason: string | null;
  id: string | null;
}

export interface BrowserAuthCompletedPayload {
  callbackUrl: string;
  params: Record<string, string>;
  id: string | null;
}

export declare class PendingOpen implements PromiseLike<
  OpenStartedResult | undefined
> {
  constructor(url: string);
  mode(mode: BrowserMode): this;
  external(external?: boolean): this;
  title(title: string): this;
  showToolbar(enabled?: boolean): this;
  showNavigationButtons(enabled?: boolean): this;
  shareButton(enabled?: boolean): this;
  desktopMode(enabled?: boolean): this;
  id(id: string): this;
  getId(): string | null;
  then<TResult1 = OpenStartedResult | undefined, TResult2 = never>(
    onfulfilled?:
      | ((
          value: OpenStartedResult | undefined,
        ) => TResult1 | PromiseLike<TResult1>)
      | undefined
      | null,
    onrejected?:
      | ((reason: BridgeError) => TResult2 | PromiseLike<TResult2>)
      | undefined
      | null,
  ): PromiseLike<TResult1 | TResult2>;
}

export declare class PendingAuth implements PromiseLike<
  OpenStartedResult | undefined
> {
  constructor(url: string, redirectUri: string);
  ephemeral(enabled?: boolean): this;
  id(id: string): this;
  getId(): string | null;
  then<TResult1 = OpenStartedResult | undefined, TResult2 = never>(
    onfulfilled?:
      | ((
          value: OpenStartedResult | undefined,
        ) => TResult1 | PromiseLike<TResult1>)
      | undefined
      | null,
    onrejected?:
      | ((reason: BridgeError) => TResult2 | PromiseLike<TResult2>)
      | undefined
      | null,
  ): PromiseLike<TResult1 | TResult2>;
}

export declare const Browser: {
  open(url: string): PendingOpen;
  auth(url: string, redirectUri: string): PendingAuth;
  close(id?: string | null): Promise<CloseResult>;
};

export declare const Events: {
  Browser: {
    Opened: "Sandip\\Browser\\Native\\Events\\Browser\\Opened";
    Closed: "Sandip\\Browser\\Native\\Events\\Browser\\Closed";
    AuthCompleted: "Sandip\\Browser\\Native\\Events\\Browser\\AuthCompleted";
  };
};

export declare function On(
  eventName: typeof Events.Browser.Opened,
  callback: (payload: BrowserOpenedPayload, eventName: string) => void,
): void;
export declare function On(
  eventName: typeof Events.Browser.Closed,
  callback: (payload: BrowserClosedPayload, eventName: string) => void,
): void;
export declare function On(
  eventName: typeof Events.Browser.AuthCompleted,
  callback: (payload: BrowserAuthCompletedPayload, eventName: string) => void,
): void;
export declare function On(
  eventName: string,
  callback: (payload: any, eventName: string) => void,
): void;

export declare function Off(
  eventName: typeof Events.Browser.Opened,
  callback: (payload: BrowserOpenedPayload, eventName: string) => void,
): void;
export declare function Off(
  eventName: typeof Events.Browser.Closed,
  callback: (payload: BrowserClosedPayload, eventName: string) => void,
): void;
export declare function Off(
  eventName: typeof Events.Browser.AuthCompleted,
  callback: (payload: BrowserAuthCompletedPayload, eventName: string) => void,
): void;
export declare function Off(
  eventName: string,
  callback: (payload: any, eventName: string) => void,
): void;

declare const _default: {
  Browser: typeof Browser;
  On: typeof On;
  Off: typeof Off;
  Events: typeof Events;
  PendingOpen: typeof PendingOpen;
  PendingAuth: typeof PendingAuth;
};

export default _default;
