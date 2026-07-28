import AuthenticationServices
import UIKit
import WebKit

enum BrowserFunctions {

    static let openedEvent = "Sandip\\Browser\\Native\\Events\\Browser\\Opened"
    static let closedEvent = "Sandip\\Browser\\Native\\Events\\Browser\\Closed"
    static let authCompletedEvent = "Sandip\\Browser\\Native\\Events\\Browser\\AuthCompleted"

    static weak var activeController: BrowserViewController?

    static let validModes: Set<String> = ["webview", "external"]

    static let authRedirectScheme = "nativephp"

    static var activeAuthSession: ASWebAuthenticationSession?
    private static var activeAuthSessionId: String?
    private static var pendingAuthCancelReason: String?
    private static let authContextProvider = AuthContextProvider()

    class Open: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            guard let url = parameters["url"] as? String, !url.isEmpty else {
                return BridgeResponse.error(code: "INVALID_URL", message: "A URL must be provided.")
            }

            let mode = parameters["mode"] as? String ?? "webview"
            guard BrowserFunctions.validModes.contains(mode) else {
                return BridgeResponse.error(
                    code: "INVALID_MODE",
                    message: "Invalid browser mode: \(mode). Valid modes are: \(BrowserFunctions.validModes.sorted().joined(separator: ", "))."
                )
            }

            let id = parameters["id"] as? String

            if mode == "external" {
                return openExternal(url: url, id: id)
            }

            let title = parameters["title"] as? String
            let showToolbar = parameters["showToolbar"] as? Bool ?? true
            let showNavigationButtons = parameters["showNavigationButtons"] as? Bool ?? true
            let shareButton = parameters["shareButton"] as? Bool ?? true
            let desktopMode = parameters["desktopMode"] as? Bool ?? false

            DispatchQueue.main.async {
                BrowserFunctions.present(
                    url: url,
                    title: title,
                    showToolbar: showToolbar,
                    showNavigationButtons: showNavigationButtons,
                    shareButton: shareButton,
                    desktopMode: desktopMode,
                    id: id
                )
            }

            return BridgeResponse.success(data: ["started": true])
        }

        private func openExternal(url: String, id: String?) -> [String: Any] {
            guard let parsedUrl = URL(string: url) else {
                return BridgeResponse.error(code: "INVALID_URL", message: "Could not parse URL: \(url)")
            }

            guard UIApplication.shared.canOpenURL(parsedUrl) else {
                return BridgeResponse.error(
                    code: "NO_BROWSER_AVAILABLE",
                    message: "No application is available to open this URL."
                )
            }

            DispatchQueue.main.async {
                BrowserFunctions.cancelActiveAuthSession(reason: "replaced")
                UIApplication.shared.open(parsedUrl, options: [:]) { success in
                    if success {
                        LaravelBridge.shared.send?(BrowserFunctions.openedEvent, [
                            "url": url,
                            "mode": "external",
                            "id": id,
                        ])
                    } else {
                        LaravelBridge.shared.send?(BrowserFunctions.closedEvent, [
                            "reason": "launch_failed",
                            "id": id,
                        ])
                    }
                }
            }

            return BridgeResponse.success(data: ["started": true])
        }
    }

    class Close: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            let id = parameters["id"] as? String

            if BrowserFunctions.activeAuthSession != nil,
               id == nil || BrowserFunctions.activeAuthSessionId == id {
                DispatchQueue.main.async {
                    BrowserFunctions.cancelActiveAuthSession(reason: "closed_by_app")
                }
                return BridgeResponse.success(data: ["closed": true])
            }

            guard let controller = BrowserFunctions.activeController,
                  id == nil || controller.sessionId == id else {
                return BridgeResponse.success(data: ["closed": false])
            }

            DispatchQueue.main.async {
                controller.finish(reason: "closed_by_app")
            }

            return BridgeResponse.success(data: ["closed": true])
        }
    }

    class Auth: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            guard let urlString = parameters["url"] as? String, !urlString.isEmpty,
                  let url = URL(string: urlString) else {
                return BridgeResponse.error(code: "INVALID_URL", message: "An authorize URL must be provided.")
            }

            guard let redirectUriString = parameters["redirectUri"] as? String,
                  let redirectUri = URL(string: redirectUriString),
                  let scheme = redirectUri.scheme, !scheme.isEmpty else {
                return BridgeResponse.error(
                    code: "INVALID_REDIRECT_URI",
                    message: "A valid redirectUri with a scheme must be provided."
                )
            }

            guard scheme == BrowserFunctions.authRedirectScheme else {
                return BridgeResponse.error(
                    code: "UNSUPPORTED_REDIRECT_SCHEME",
                    message: "redirectUri must use the \"\(BrowserFunctions.authRedirectScheme)://\" scheme so the OAuth callback can be routed back into the app, e.g. \(BrowserFunctions.authRedirectScheme)://127.0.0.1/auth/callback."
                )
            }

            let ephemeral = parameters["ephemeral"] as? Bool ?? true
            let id = parameters["id"] as? String

            DispatchQueue.main.async {
                BrowserFunctions.presentAuth(url: url, callbackScheme: scheme, ephemeral: ephemeral, id: id)
            }

            return BridgeResponse.success(data: ["started": true])
        }
    }

    private static func present(url: String, title: String?, showToolbar: Bool, showNavigationButtons: Bool, shareButton: Bool, desktopMode: Bool, id: String?) {
        let rootViewController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController

        guard let presenter = rootViewController else {
            LaravelBridge.shared.send?(closedEvent, [
                "reason": "no_root_view_controller",
                "id": id,
            ])
            return
        }

        activeController?.finish(reason: "replaced")
        cancelActiveAuthSession(reason: "replaced")

        let controller = BrowserViewController(
            url: url,
            title: title,
            showToolbar: showToolbar,
            showNavigationButtons: showNavigationButtons,
            shareButton: shareButton,
            desktopMode: desktopMode,
            id: id
        )
        controller.modalPresentationStyle = .fullScreen
        activeController = controller
        presenter.present(controller, animated: true)
    }

    fileprivate static func cancelActiveAuthSession(reason: String) {
        guard activeAuthSession != nil else { return }
        pendingAuthCancelReason = reason
        activeAuthSession?.cancel()
    }

    fileprivate static func presentAuth(url: URL, callbackScheme: String, ephemeral: Bool, id: String?) {
        cancelActiveAuthSession(reason: "replaced")

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackUrl, error in
            let cancelReason = BrowserFunctions.pendingAuthCancelReason
            BrowserFunctions.activeAuthSession = nil
            BrowserFunctions.activeAuthSessionId = nil
            BrowserFunctions.pendingAuthCancelReason = nil

            if let cancelReason = cancelReason {
                LaravelBridge.shared.send?(closedEvent, ["reason": cancelReason, "id": id])
                return
            }

            if let error = error {
                let reason = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin ? "user_cancelled" : "auth_failed"
                LaravelBridge.shared.send?(closedEvent, ["reason": reason, "id": id])
                return
            }

            guard let callbackUrl = callbackUrl else {
                LaravelBridge.shared.send?(closedEvent, ["reason": "auth_failed", "id": id])
                return
            }

            LaravelBridge.shared.send?(authCompletedEvent, [
                "callbackUrl": callbackUrl.absoluteString,
                "params": parseCallbackParams(callbackUrl),
                "id": id,
            ])
        }

        session.prefersEphemeralWebBrowserSession = ephemeral
        session.presentationContextProvider = authContextProvider

        activeAuthSession = session
        activeAuthSessionId = id

        session.start()
    }

    private static func parseCallbackParams(_ url: URL) -> [String: String] {
        var result: [String: String] = [:]

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return result
        }

        components.queryItems?.forEach { item in
            result[item.name] = item.value ?? ""
        }

        if let fragment = components.fragment, !fragment.isEmpty {
            URLComponents(string: "?" + fragment)?.queryItems?.forEach { item in
                result[item.name] = item.value ?? ""
            }
        }

        return result
    }
}

private final class AuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }
}

final class BrowserViewController: UIViewController, WKNavigationDelegate {

    private let pageUrl: String
    private let titleOverride: String?
    private let showToolbar: Bool
    private let showNavigationButtons: Bool
    private let shareButtonEnabled: Bool
    private let desktopMode: Bool
    let sessionId: String?

    private var webView: WKWebView!
    private var titleLabel: UILabel?
    private var progressView: UIProgressView?
    private var backButton: UIButton?
    private var forwardButton: UIButton?
    private var finished = false
    private var openedFired = false
    private var progressObservation: NSKeyValueObservation?

    init(url: String, title: String?, showToolbar: Bool, showNavigationButtons: Bool, shareButton: Bool, desktopMode: Bool, id: String?) {
        self.pageUrl = url
        self.titleOverride = title
        self.showToolbar = showToolbar
        self.showNavigationButtons = showNavigationButtons
        self.shareButtonEnabled = shareButton
        self.desktopMode = desktopMode
        self.sessionId = id
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        setUpWebView()
        if showToolbar { setUpToolbar() }
        if showNavigationButtons { setUpNavigationBar() }
        layoutWebView()

        guard let url = URL(string: pageUrl) else {
            finish(reason: "invalid_url")
            return
        }
        webView.load(URLRequest(url: url))
    }

    private func setUpWebView() {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        if desktopMode {
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        }

        view.addSubview(webView)

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self = self, let progressView = self.progressView else { return }
            progressView.progress = Float(webView.estimatedProgress)
            progressView.isHidden = webView.estimatedProgress >= 1.0
        }
    }

    private func layoutWebView() {
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: showToolbar ? view.safeAreaLayoutGuide.topAnchor : view.topAnchor, constant: showToolbar ? 44 : 0),
            webView.bottomAnchor.constraint(equalTo: showNavigationButtons ? view.safeAreaLayoutGuide.bottomAnchor : view.bottomAnchor, constant: showNavigationButtons ? -44 : 0),
        ])
    }

    private func setUpToolbar() {
        let bar = UIView()
        bar.backgroundColor = .white
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark")?.withRenderingMode(.alwaysTemplate), for: .normal)
        styleIconButton(closeButton)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        bar.addSubview(closeButton)

        let label = UILabel()
        label.text = titleOverride ?? pageUrl
        label.textColor = .black
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(label)
        titleLabel = label

        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(progress)
        progressView = progress

        var shareButton: UIButton?
        if shareButtonEnabled {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "square.and.arrow.up")?.withRenderingMode(.alwaysTemplate), for: .normal)
            styleIconButton(button)
            button.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
            bar.addSubview(button)
            shareButton = button
        }

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),

            closeButton.leadingAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            closeButton.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -6),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            label.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 8),

            progress.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            progress.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])

        if let shareButton = shareButton {
            shareButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                shareButton.trailingAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.trailingAnchor, constant: -12),
                shareButton.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -6),
                shareButton.widthAnchor.constraint(equalToConstant: 32),
                shareButton.heightAnchor.constraint(equalToConstant: 32),
                label.trailingAnchor.constraint(lessThanOrEqualTo: shareButton.leadingAnchor, constant: -8),
            ])
        } else {
            NSLayoutConstraint.activate([
                label.trailingAnchor.constraint(lessThanOrEqualTo: bar.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            ])
        }
    }

    private func setUpNavigationBar() {
        let bar = UIView()
        bar.backgroundColor = .white
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        styleIconButton(back)
        back.isEnabled = false
        back.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        bar.addSubview(back)
        backButton = back

        let reload = UIButton(type: .system)
        reload.setImage(UIImage(systemName: "arrow.clockwise")?.withRenderingMode(.alwaysTemplate), for: .normal)
        styleIconButton(reload)
        reload.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)
        bar.addSubview(reload)

        let forward = UIButton(type: .system)
        forward.setImage(UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate), for: .normal)
        styleIconButton(forward)
        forward.isEnabled = false
        forward.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)
        bar.addSubview(forward)
        forwardButton = forward

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -44),

            back.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -6),
            back.centerXAnchor.constraint(equalTo: bar.centerXAnchor, constant: -60),
            back.widthAnchor.constraint(equalToConstant: 36),
            back.heightAnchor.constraint(equalToConstant: 36),

            reload.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -6),
            reload.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            reload.widthAnchor.constraint(equalToConstant: 36),
            reload.heightAnchor.constraint(equalToConstant: 36),

            forward.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -6),
            forward.centerXAnchor.constraint(equalTo: bar.centerXAnchor, constant: 60),
            forward.widthAnchor.constraint(equalToConstant: 36),
            forward.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    private func styleIconButton(_ button: UIButton) {
        button.tintColor = .black
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func closeTapped() {
        finish(reason: "user_closed")
    }

    @objc private func shareTapped() {
        let shareUrl = webView.url?.absoluteString ?? pageUrl
        guard let url = URL(string: shareUrl) else { return }
        let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(activityController, animated: true)
    }

    @objc private func backTapped() {
        webView.goBack()
    }

    @objc private func forwardTapped() {
        webView.goForward()
    }

    @objc private func reloadTapped() {
        webView.reload()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        backButton?.isEnabled = webView.canGoBack
        forwardButton?.isEnabled = webView.canGoForward

        if titleOverride == nil {
            titleLabel?.text = webView.title?.isEmpty == false ? webView.title : pageUrl
        }

        if !openedFired {
            openedFired = true
            LaravelBridge.shared.send?(BrowserFunctions.openedEvent, [
                "url": pageUrl,
                "mode": "webview",
                "id": sessionId,
            ])
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    }

    func finish(reason: String) {
        guard !finished else { return }
        finished = true

        if BrowserFunctions.activeController === self {
            BrowserFunctions.activeController = nil
        }

        progressObservation?.invalidate()
        webView.stopLoading()

        dismiss(animated: true)

        LaravelBridge.shared.send?(BrowserFunctions.closedEvent, [
            "reason": reason,
            "id": sessionId,
        ])
    }
}
