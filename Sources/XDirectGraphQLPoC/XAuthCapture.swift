import Foundation

#if canImport(WebKit)
import WebKit
#endif

public enum XAuthCapture {
    public static func fetchPublicBearerToken(session: URLSession = .shared) async throws -> String {
        let mainJSURL = try await findMainScriptURL(session: session)
        let scriptBody = try await fetchText(from: mainJSURL, session: session)

        guard let token = firstMatch(in: scriptBody, pattern: #"AAAAA[A-Za-z0-9%_-]{30,}"#) else {
            throw XDirectClientError.bearerTokenNotFound
        }
        return token
    }

    public static func findMainScriptURL(session: URLSession = .shared) async throws -> URL {
        let html = try await fetchText(from: URL(string: "https://x.com")!, session: session)

        if let raw = firstMatch(in: html, pattern: #"https://abs\.twimg\.com/responsive-web/client-web/main\.[^\"']+\.js"#),
           let url = URL(string: raw) {
            return url
        }

        if let raw = firstMatch(in: html, pattern: #"https://abs\.twimg\.com/responsive-web/client-web/[^\"']+\.js"#),
           let url = URL(string: raw) {
            return url
        }

        throw XDirectClientError.bearerTokenNotFound
    }

    private static func fetchText(from url: URL, session: URLSession) async throws -> String {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw XDirectClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw XDirectClientError.badStatus(status: http.statusCode, body: String(body.prefix(250)))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return ns.substring(with: match.range)
    }

    #if canImport(WebKit)
    @MainActor
    public static func captureFromDefaultWKStore(language: String = "en", session: URLSession = .shared) async throws -> XAuthContext {
        try await capture(from: WKWebsiteDataStore.default().httpCookieStore, language: language, session: session)
    }

    @MainActor
    public static func capture(from cookieStore: WKHTTPCookieStore, language: String = "en", session: URLSession = .shared) async throws -> XAuthContext {
        let cookies = await allCookies(from: cookieStore)
        guard let ct0 = cookies.first(where: { $0.name == "ct0" })?.value, !ct0.isEmpty else {
            throw XDirectClientError.missingCT0Cookie
        }

        let cookieHeader = cookies
            .sorted(by: { $0.name < $1.name })
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        let bearer = try await fetchPublicBearerToken(session: session)
        return XAuthContext(cookieHeader: cookieHeader, csrfToken: ct0, bearerToken: bearer, language: language)
    }

    @MainActor
    private static func allCookies(from cookieStore: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
    #endif
}
