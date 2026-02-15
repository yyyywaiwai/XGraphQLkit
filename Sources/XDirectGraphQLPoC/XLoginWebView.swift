import Foundation

#if canImport(SwiftUI) && canImport(WebKit) && canImport(UIKit)
import SwiftUI
import UIKit
import WebKit

@available(iOS 16.0, *)
public struct XLoginWebView: UIViewRepresentable {
    public typealias UIViewType = WKWebView

    public let loginURL: URL
    public let language: String
    public let onAuthCaptured: @Sendable (Result<XAuthContext, Error>) -> Void

    public init(
        loginURL: URL = URL(string: "https://x.com/i/flow/login")!,
        language: String = "en",
        onAuthCaptured: @escaping @Sendable (Result<XAuthContext, Error>) -> Void
    ) {
        self.loginURL = loginURL
        self.language = language
        self.onAuthCaptured = onAuthCaptured
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(language: language, onAuthCaptured: onAuthCaptured)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: loginURL))
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}

    public final class Coordinator: NSObject, WKNavigationDelegate {
        private let language: String
        private let onAuthCaptured: @Sendable (Result<XAuthContext, Error>) -> Void
        private var delivered = false

        init(language: String, onAuthCaptured: @escaping @Sendable (Result<XAuthContext, Error>) -> Void) {
            self.language = language
            self.onAuthCaptured = onAuthCaptured
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                guard !delivered else { return }
                do {
                    let context = try await XAuthCapture.capture(
                        from: webView.configuration.websiteDataStore.httpCookieStore,
                        language: language
                    )
                    delivered = true
                    onAuthCaptured(.success(context))
                } catch {
                    // ログイン完了前はct0がないため失敗する。ここでは無視し、次の画面遷移で再評価する。
                }
            }
        }
    }
}
#endif
