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

        var queuedURLs = prioritizedScriptURLs(from: html).filter(isTrustedPublicAssetURL)
        var queuedURLStrings = Set(queuedURLs.map(\.absoluteString))
        var fetchedURLStrings = Set<String>()
        var fetchedCount = 0
        let maxFetchCount = 80

        while !queuedURLs.isEmpty, fetchedCount < maxFetchCount {
            queuedURLs.sort {
                let left = scriptPriority($0)
                let right = scriptPriority($1)
                if left == right {
                    return $0.absoluteString < $1.absoluteString
                }
                return left < right
            }

            let scriptURL = queuedURLs.removeFirst()
            queuedURLStrings.remove(scriptURL.absoluteString)
            guard fetchedURLStrings.insert(scriptURL.absoluteString).inserted else {
                continue
            }

            guard let scriptBody = try? await fetchText(from: scriptURL, session: session) else {
                continue
            }
            fetchedCount += 1

            if let token = firstBearerToken(in: scriptBody) {
                return token
            }

            for nestedURL in javaScriptAssetURLs(in: scriptBody, baseURL: scriptURL) {
                let absolute = nestedURL.absoluteString
                guard isTrustedPublicAssetURL(nestedURL),
                      !fetchedURLStrings.contains(absolute),
                      queuedURLStrings.insert(absolute).inserted else {
                    continue
                }
                queuedURLs.append(nestedURL)
            }
        }

        if let fallback = knownPublicBearerToken() {
            return fallback
        }

        throw XDirectClientError.bearerTokenNotFound
    }

    private static func knownPublicBearerToken() -> String? {
        // Public web client bearer used by X/Twitter web. Not a user secret.
        let token = "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
        return firstBearerToken(in: token)
    }

    public static func findMainScriptURL(session: URLSession = .shared) async throws -> URL {
        let html = try await fetchHomeHTML(session: session)
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

    static func fetchHomeHTML(session: URLSession) async throws -> String {
        try await fetchText(from: URL(string: "https://x.com")!, session: session)
    }

    static func fetchScriptText(from url: URL, session: URLSession) async throws -> String {
        try await fetchText(from: url, session: session)
    }

    private static func fetchText(from url: URL, session: URLSession) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
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
        firstMatch(in: text, pattern: #"AAAAA[A-Za-z0-9%_\-.=]{30,}"#)
    }

    static func scriptURLs(in html: String) -> [URL] {
        javaScriptAssetURLs(in: html, baseURL: URL(string: "https://x.com")!)
    }

    static func javaScriptAssetURLs(in text: String, baseURL: URL) -> [URL] {
        let patterns = [
            #"https://abs\.twimg\.com/responsive-web/client-web/[^"'` <>\n\r]+\.js"#,
            #"https://abs\.twimg\.com/x-web/x-web/(?:assets/)?[^"'` <>\n\r]+\.js"#,
            #"(?:src|href)\s*=\s*["']([^"']+\.js)["']"#,
            #"["'`]((?:\./|assets/)[A-Za-z0-9_./-]+\.js)["'`]"#,
            #"from\s*["'`](\.?/?assets/[^"'`]+\.js)["'`]"#
        ]

        var urls: [URL] = []
        var seen = Set<String>()
        let ns = text as NSString
        let searchRange = NSRange(location: 0, length: ns.length)

        func append(_ raw: String) {
            let resolved: URL?
            if raw.hasPrefix("//") {
                resolved = URL(string: "https:\(raw)")
            } else if let url = URL(string: raw), url.scheme != nil {
                resolved = url
            } else if raw.hasPrefix("assets/") || raw.hasPrefix("./assets/") {
                let normalized = raw.hasPrefix("./") ? String(raw.dropFirst(2)) : raw
                resolved = URL(string: normalized, relativeTo: URL(string: "https://abs.twimg.com/x-web/x-web/")!)?.absoluteURL
            } else {
                let baseDirectory = baseURL.deletingLastPathComponent()
                resolved = URL(string: raw, relativeTo: baseDirectory)?.absoluteURL
                if resolved == nil {
                    resolved = URL(string: raw, relativeTo: baseURL)?.absoluteURL
                }
            }

            guard let url = resolved else { return }
            let absolute = url.absoluteString
            guard absolute.hasSuffix(".js") else { return }
            guard seen.insert(absolute).inserted else { return }
            urls.append(url)
        }

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, options: [], range: searchRange) {
                let captureRange = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                    ? match.range(at: 1)
                    : match.range(at: 0)
                append(ns.substring(with: captureRange))
            }
        }

        return urls
    }

    static func prioritizedOperationScriptURLs(from html: String, operationName: String) -> [URL] {
        scriptURLs(in: html)
            .enumerated()
            .sorted { lhs, rhs in
                let leftScore = operationScriptPriority(lhs.element, operationName: operationName)
                let rightScore = operationScriptPriority(rhs.element, operationName: operationName)
                if leftScore == rightScore {
                    return lhs.offset < rhs.offset
                }
                return leftScore < rightScore
            }
            .map(\.element)
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
        if value.contains("entry-client") { return 1 }
        if value.contains("/responsive-web/client-web/main.") { return 2 }
        if value.contains("/responsive-web/client-web/") { return 3 }
        if value.contains("/x-web/x-web/assets/") { return 4 }
        if value.contains("/x-web/x-web/") { return 5 }
        return 10
    }

    private static func isTrustedPublicAssetURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }

        return host == "abs.twimg.com"
            || host == "x.com"
            || host.hasSuffix(".x.com")
            || host == "twitter.com"
            || host.hasSuffix(".twitter.com")
    }

    static func operationScriptPriority(_ url: URL, operationName: String) -> Int {
        let value = url.absoluteString.lowercased()

        let keywords: [String]
        switch operationName {
        case "UserByScreenName":
            keywords = ["user-profile", "_profile", "profile", "followers", "following"]
        case "UserTweets":
            keywords = ["_profile", "generic-timeline", "timeline", "tweet-results", "user-profile"]
        case "UserTweetsAndReplies":
            keywords = ["with_replies", "_profile", "generic-timeline", "timeline", "tweet-results"]
        case "UserMedia", "mediaQuery":
            keywords = ["media", "_profile", "generic-timeline", "timeline", "tweet-results"]
        case "UserHighlightsTweets":
            keywords = ["highlights", "_profile", "generic-timeline", "timeline", "tweet-results"]
        case "SearchTimeline", "BookmarkSearchTimeline":
            keywords = ["search", "explore", "global-trending", "timeline", "generic-timeline"]
        case "Bookmarks":
            keywords = ["bookmark", "timeline", "generic-timeline"]
        case "TweetResultByRestId", "TweetDetail":
            keywords = ["tweet-result", "conversation", "status", "_id", "tweet"]
        default:
            keywords = []
        }

        if let index = keywords.firstIndex(where: { value.contains($0) }) {
            return index
        }
        if value.contains("/responsive-web/client-web/main.") { return 20 }
        if value.contains("/responsive-web/client-web/") { return 30 }
        if value.contains("/x-web/x-web/assets/") { return 40 }
        return 100
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
