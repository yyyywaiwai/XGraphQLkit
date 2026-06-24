import Foundation

#if canImport(WebKit)
import WebKit
#endif

public enum XAuthCapture {
    public static func fetchPublicBearerToken(session: URLSession = .shared) async throws -> String {
        let html = try await fetchText(from: URL(string: "https://x.com")!, session: session)
        if let token = firstBearerToken(in: html) {
            return token
        }

        for scriptURL in prioritizedScriptURLs(from: html) {
            guard let scriptBody = try? await fetchText(from: scriptURL, session: session) else {
                continue
            }
            if let token = firstBearerToken(in: scriptBody) {
                return token
            }
        }

        throw XDirectClientError.bearerTokenNotFound
    }

    public static func findMainScriptURL(session: URLSession = .shared) async throws -> URL {
        let html = try await fetchText(from: URL(string: "https://x.com")!, session: session)
        let scriptURLs = scriptURLs(in: html)

        if let url = scriptURLs.first(where: { $0.absoluteString.contains("/responsive-web/client-web/main.") }) {
            return url
        }

        if let url = scriptURLs.first(where: { $0.absoluteString.contains("/responsive-web/client-web/") }) {
            return url
        }

        if let url = prioritizedScriptURLs(from: html).first {
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

    static func firstBearerToken(in text: String) -> String? {
        firstMatch(in: text, pattern: #"AAAAA[A-Za-z0-9%_-]{30,}"#)
    }

    static func scriptURLs(in html: String) -> [URL] {
        let patterns = [
            #"https://abs\.twimg\.com/responsive-web/client-web/[^"' <>\n\r]+\.js"#,
            #"https://abs\.twimg\.com/x-web/x-web/assets/[^"' <>\n\r]+\.js"#,
            #"(?:src|href)\s*=\s*["']([^"']+\.js)["']"#
        ]

        var urls: [URL] = []
        var seen = Set<String>()
        let ns = html as NSString
        let searchRange = NSRange(location: 0, length: ns.length)

        func append(_ raw: String) {
            let resolved: URL?
            if raw.hasPrefix("//") {
                resolved = URL(string: "https:\(raw)")
            } else if let url = URL(string: raw), url.scheme != nil {
                resolved = url
            } else {
                resolved = URL(string: raw, relativeTo: URL(string: "https://x.com")!)?.absoluteURL
            }

            guard let url = resolved else { return }
            let absolute = url.absoluteString
            guard absolute.hasSuffix(".js") else { return }
            guard seen.insert(absolute).inserted else { return }
            urls.append(url)
        }

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: html, options: [], range: searchRange) {
                let captureRange = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                    ? match.range(at: 1)
                    : match.range(at: 0)
                append(ns.substring(with: captureRange))
            }
        }

        return urls
    }

    static func prioritizedScriptURLs(from html: String) -> [URL] {
        scriptURLs(in: html)
            .enumerated()
            .sorted { lhs, rhs in
                let leftScore = scriptPriority(lhs.element)
                let rightScore = scriptPriority(rhs.element)
                if leftScore == rightScore {
                    return lhs.offset < rhs.offset
                }
                return leftScore < rightScore
            }
            .map(\.element)
    }

    private static func scriptPriority(_ url: URL) -> Int {
        let value = url.absoluteString
        if value.contains("guest-token") { return 0 }
        if value.contains("/responsive-web/client-web/main.") { return 1 }
        if value.contains("/responsive-web/client-web/") { return 2 }
        if value.contains("/x-web/x-web/assets/") { return 3 }
        return 10
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
