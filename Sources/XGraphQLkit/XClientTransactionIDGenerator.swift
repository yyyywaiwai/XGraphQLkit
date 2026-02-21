import Foundation

#if canImport(WebKit)
import WebKit

@MainActor
final class XClientTransactionIDGenerator: NSObject, WKNavigationDelegate {
    static let shared = XClientTransactionIDGenerator()

    private static let bootstrapTimeoutSeconds: TimeInterval = 20

    private let webView: WKWebView
    private var navigationContinuations: [CheckedContinuation<Void, Error>] = []
    private var didLoadBootstrapPage = false
    private var navigationInProgress = false
    private var navigationTimeoutTask: Task<Void, Never>?

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    func generate(path: String, method: String = "GET") async -> String? {
        do {
            try await ensureBootstrapped()
            return try await evaluateGenerateScript(path: path, method: method)
        } catch {
            return nil
        }
    }

    private func ensureBootstrapped() async throws {
        if didLoadBootstrapPage {
            return
        }

        if navigationInProgress {
            try await withCheckedThrowingContinuation { continuation in
                navigationContinuations.append(continuation)
            }
            return
        }

        guard let url = URL(string: "https://x.com/home") else {
            throw XDirectClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.bootstrapTimeoutSeconds

        navigationInProgress = true
        startNavigationTimeout(seconds: Self.bootstrapTimeoutSeconds)
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuations.append(continuation)
            if webView.load(request) == nil {
                completeNavigation(.failure(XDirectClientError.invalidResponse))
            }
        }
    }

    private func evaluateGenerateScript(path: String, method: String) async throws -> String? {
        // X's webpack internals change frequently. Keep this logic observable and maintainable.
        let script = """
        try {
          if (!window.webpackChunk_twitter_responsive_web) { return null; }
          if (!window.__xgql_req) {
            window.webpackChunk_twitter_responsive_web.push([
              [Math.floor(Math.random() * 1000000000)],
              {},
              (req) => { window.__xgql_req = req; }
            ]);
          }
          if (!window.__xgql_req) { return null; }
          const req = window.__xgql_req;
          const debug = [];

          const describe = (value) => {
            if (value === null) { return "null"; }
            if (value === undefined) { return "undefined"; }
            if (typeof value === "function") { return "function"; }
            if (typeof value !== "object") { return typeof value; }
            const keys = Object.keys(value).slice(0, 10);
            return "keys=" + keys.join(",");
          };

          const uniqueCandidates = (list) => {
            const seen = new Set();
            return list.filter((candidate) => {
              if (typeof candidate.fn !== "function") { return false; }
              if (seen.has(candidate.fn)) { return false; }
              seen.add(candidate.fn);
              return true;
            });
          };

          const generatorCandidates = (exportsValue, label) => {
            const candidates = [];
            if (typeof exportsValue === "function") {
              candidates.push({ fn: exportsValue, label: label + "#exports" });
            }
            if (!exportsValue || typeof exportsValue !== "object") {
              return candidates;
            }

            if (typeof exportsValue.jJ === "function") {
              candidates.push({ fn: exportsValue.jJ, label: label + ".jJ" });
            }
            if (typeof exportsValue.default === "function") {
              candidates.push({ fn: exportsValue.default, label: label + ".default" });
            }
            for (const [key, value] of Object.entries(exportsValue)) {
              if (typeof value !== "function") { continue; }
              if (value.length < 3) { continue; }
              candidates.push({ fn: value, label: label + "." + key });
            }
            return uniqueCandidates(candidates);
          };

          const invokeCandidates = async (candidates) => {
            for (const candidate of candidates) {
              try {
                const token = await candidate.fn("https://x.com", path, method);
                if (typeof token === "string" && token.length > 0) {
                  return token;
                }
                debug.push("candidate non-string: " + candidate.label);
              } catch (error) {
                debug.push("candidate threw: " + candidate.label + " -> " + String(error));
              }
            }
            return null;
          };

          const moduleExportById = (id) => {
            try {
              return req(id);
            } catch (error) {
              debug.push("require failed: " + id + " -> " + String(error));
              return undefined;
            }
          };

          const primaryModule = moduleExportById(83914);
          const primaryCandidates = generatorCandidates(primaryModule, "83914");
          if (primaryCandidates.length === 0) {
            debug.push("primary missing candidates shape=" + describe(primaryModule));
          }
          const primaryToken = await invokeCandidates(primaryCandidates);
          if (primaryToken) { return primaryToken; }

          const cache = req.c || {};
          for (const [id, record] of Object.entries(cache)) {
            if (!record || typeof record !== "object") { continue; }
            const exportsValue = record.exports;
            const candidates = generatorCandidates(exportsValue, "cache:" + id);
            if (candidates.length === 0) { continue; }
            const token = await invokeCandidates(candidates);
            if (token) { return token; }
          }

          debug.push("generator unresolved cacheCount=" + String(Object.keys(cache).length));
          console.warn("[XGraphQLkit][XCTID] " + debug.join(" | "));
          return null;
        } catch (_) {
          return null;
        }
        """

        if #available(iOS 14.0, macOS 11.0, *) {
            let result = try await webView.callAsyncJavaScript(
                script,
                arguments: [
                    "path": path,
                    "method": method
                ],
                in: nil,
                contentWorld: .page
            )
            return result as? String
        }

        let escapedPath = jsStringLiteral(path)
        let escapedMethod = jsStringLiteral(method)
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("""
            (async () => {
              try {
                if (!window.webpackChunk_twitter_responsive_web) { return null; }
                if (!window.__xgql_req) {
                  window.webpackChunk_twitter_responsive_web.push([
                    [Math.floor(Math.random() * 1000000000)],
                    {},
                    (req) => { window.__xgql_req = req; }
                  ]);
                }
                if (!window.__xgql_req) { return null; }
                const req = window.__xgql_req;
                const debug = [];

                const describe = (value) => {
                  if (value === null) { return "null"; }
                  if (value === undefined) { return "undefined"; }
                  if (typeof value === "function") { return "function"; }
                  if (typeof value !== "object") { return typeof value; }
                  const keys = Object.keys(value).slice(0, 10);
                  return "keys=" + keys.join(",");
                };

                const uniqueCandidates = (list) => {
                  const seen = new Set();
                  return list.filter((candidate) => {
                    if (typeof candidate.fn !== "function") { return false; }
                    if (seen.has(candidate.fn)) { return false; }
                    seen.add(candidate.fn);
                    return true;
                  });
                };

                const generatorCandidates = (exportsValue, label) => {
                  const candidates = [];
                  if (typeof exportsValue === "function") {
                    candidates.push({ fn: exportsValue, label: label + "#exports" });
                  }
                  if (!exportsValue || typeof exportsValue !== "object") {
                    return candidates;
                  }

                  if (typeof exportsValue.jJ === "function") {
                    candidates.push({ fn: exportsValue.jJ, label: label + ".jJ" });
                  }
                  if (typeof exportsValue.default === "function") {
                    candidates.push({ fn: exportsValue.default, label: label + ".default" });
                  }
                  for (const [key, value] of Object.entries(exportsValue)) {
                    if (typeof value !== "function") { continue; }
                    if (value.length < 3) { continue; }
                    candidates.push({ fn: value, label: label + "." + key });
                  }
                  return uniqueCandidates(candidates);
                };

                const invokeCandidates = async (candidates) => {
                  for (const candidate of candidates) {
                    try {
                      const token = await candidate.fn("https://x.com", "\(escapedPath)", "\(escapedMethod)");
                      if (typeof token === "string" && token.length > 0) {
                        return token;
                      }
                      debug.push("candidate non-string: " + candidate.label);
                    } catch (error) {
                      debug.push("candidate threw: " + candidate.label + " -> " + String(error));
                    }
                  }
                  return null;
                };

                const moduleExportById = (id) => {
                  try {
                    return req(id);
                  } catch (error) {
                    debug.push("require failed: " + id + " -> " + String(error));
                    return undefined;
                  }
                };

                const primaryModule = moduleExportById(83914);
                const primaryCandidates = generatorCandidates(primaryModule, "83914");
                if (primaryCandidates.length === 0) {
                  debug.push("primary missing candidates shape=" + describe(primaryModule));
                }
                const primaryToken = await invokeCandidates(primaryCandidates);
                if (primaryToken) { return primaryToken; }

                const cache = req.c || {};
                for (const [id, record] of Object.entries(cache)) {
                  if (!record || typeof record !== "object") { continue; }
                  const exportsValue = record.exports;
                  const candidates = generatorCandidates(exportsValue, "cache:" + id);
                  if (candidates.length === 0) { continue; }
                  const token = await invokeCandidates(candidates);
                  if (token) { return token; }
                }

                debug.push("generator unresolved cacheCount=" + String(Object.keys(cache).length));
                console.warn("[XGraphQLkit][XCTID] " + debug.join(" | "));
                return null;
              } catch (_) {
                return null;
              }
            })();
            """) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result as? String)
                }
            }
        }
    }

    private func startNavigationTimeout(seconds: TimeInterval) {
        navigationTimeoutTask?.cancel()
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        navigationTimeoutTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            self.handleNavigationTimeout(seconds: seconds)
        }
    }

    private func handleNavigationTimeout(seconds: TimeInterval) {
        guard navigationInProgress else { return }
        webView.stopLoading()
        completeNavigation(
            .failure(
                URLError(
                    .timedOut,
                    userInfo: [
                        NSLocalizedDescriptionKey: "X bootstrap page load timed out after \(Int(seconds)) seconds."
                    ]
                )
            )
        )
    }

    private func jsStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private func completeNavigation(_ result: Result<Void, Error>) {
        guard navigationInProgress || !navigationContinuations.isEmpty else { return }

        navigationTimeoutTask?.cancel()
        navigationTimeoutTask = nil

        let continuations = navigationContinuations
        navigationContinuations.removeAll()
        navigationInProgress = false

        switch result {
        case .success:
            didLoadBootstrapPage = true
            for continuation in continuations {
                continuation.resume(returning: ())
            }
        case .failure(let error):
            for continuation in continuations {
                continuation.resume(throwing: error)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        completeNavigation(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completeNavigation(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        completeNavigation(.failure(error))
    }
}
#endif
