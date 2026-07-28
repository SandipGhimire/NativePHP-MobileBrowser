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

    private static let headerHeight: CGFloat = 52

    private let pageUrl: String
    private let titleOverride: String?
    private let showToolbar: Bool
    private let showNavigationButtons: Bool
    private let shareButtonEnabled: Bool
    private let desktopMode: Bool
    let sessionId: String?

    private var webView: WKWebView!
    private var titleLabel: UILabel?
    private var subtitleLabel: UILabel?
    private var progressView: UIProgressView?
    private var backButton: UIButton?
    private var overflowButton: UIButton?
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
        view.backgroundColor = .systemBackground

        setUpWebView()
        if showToolbar { setUpToolbar() }
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
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = .systemBackground

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
            webView.topAnchor.constraint(equalTo: showToolbar ? view.safeAreaLayoutGuide.topAnchor : view.topAnchor, constant: showToolbar ? Self.headerHeight : 0),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setUpToolbar() {
        let bar = UIView()
        bar.backgroundColor = .systemBackground
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(separator)

        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        styleIconButton(back)
        back.addTarget(self, action: #selector(backOrCloseTapped), for: .touchUpInside)
        bar.addSubview(back)
        backButton = back

        let titleStack = UIStackView()
        titleStack.axis = .vertical
        titleStack.alignment = .center
        titleStack.spacing = 1
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(titleStack)

        let label = UILabel()
        label.text = titleOverride ?? (URL(string: pageUrl)?.host ?? pageUrl)
        label.textColor = .label
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        titleStack.addArrangedSubview(label)
        titleLabel = label

        let subtitle = UILabel()
        subtitle.textColor = .secondaryLabel
        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textAlignment = .center
        subtitle.lineBreakMode = .byTruncatingMiddle
        if let devTitle = titleOverride, !devTitle.isEmpty {
            subtitle.text = devTitle
        } else {
            subtitle.isHidden = true
        }
        titleStack.addArrangedSubview(subtitle)
        subtitleLabel = subtitle

        let progress = UIProgressView(progressViewStyle: .default)
        progress.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(progress)
        progressView = progress

        let overflow = UIButton(type: .system)
        overflow.setImage(UIImage(systemName: "ellipsis")?.withRenderingMode(.alwaysTemplate), for: .normal)
        styleIconButton(overflow)
        overflow.menu = makeOverflowMenu()
        overflow.showsMenuAsPrimaryAction = true
        bar.addSubview(overflow)
        overflowButton = overflow

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Self.headerHeight),

            separator.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            back.leadingAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            back.centerYAnchor.constraint(equalTo: bar.bottomAnchor, constant: -26),
            back.widthAnchor.constraint(equalToConstant: 36),
            back.heightAnchor.constraint(equalToConstant: 36),

            overflow.trailingAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            overflow.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            overflow.widthAnchor.constraint(equalToConstant: 36),
            overflow.heightAnchor.constraint(equalToConstant: 36),

            titleStack.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            titleStack.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            titleStack.leadingAnchor.constraint(greaterThanOrEqualTo: back.trailingAnchor, constant: 8),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: overflow.leadingAnchor, constant: -8),

            progress.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            progress.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])
    }

    private func styleIconButton(_ button: UIButton) {
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeOverflowMenu() -> UIMenu {
        var actions: [UIAction] = [
            UIAction(title: "Open in Safari", image: UIImage(systemName: "safari")) { [weak self] _ in
                self?.openInExternalBrowser()
            },
            UIAction(title: "Refresh", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                self?.webView.reload()
            },
            UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                self?.copyLink()
            },
        ]

        if shareButtonEnabled {
            actions.append(
                UIAction(title: "Share…", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                    self?.shareTapped()
                }
            )
        }

        return UIMenu(title: "", children: actions)
    }

    private func openInExternalBrowser() {
        guard let url = webView.url ?? URL(string: pageUrl) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func copyLink() {
        UIPasteboard.general.string = webView.url?.absoluteString ?? pageUrl
    }

    @objc private func backOrCloseTapped() {
        if showNavigationButtons, webView.canGoBack {
            webView.goBack()
        } else {
            finish(reason: "user_closed")
        }
    }

    @objc private func shareTapped() {
        let shareUrl = webView.url?.absoluteString ?? pageUrl
        guard let url = URL(string: shareUrl) else { return }
        let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(activityController, animated: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        titleLabel?.text = webView.title?.isEmpty == false ? webView.title : (URL(string: pageUrl)?.host ?? pageUrl)

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
        NSLog("%@", "[BrowserFunctions] WebView load error: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("%@", "[BrowserFunctions] WebView load error: \(error.localizedDescription)")
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
