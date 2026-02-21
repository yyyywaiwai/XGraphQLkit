import Foundation
import Testing
@testable import XGraphQLkit

@Test func directClient_fetchesAllOptionsFromEnv() async throws {
    let env = DotEnv.loadMergedEnvironment()
    if DotEnv.nonEmptyValue("X_RUN_LIVE_TESTS", in: env) != "1" {
        return
    }

    guard
        let cookieHeader = DotEnv.nonEmptyValue("X_COOKIE_HEADER", in: env),
        let csrfToken = DotEnv.nonEmptyValue("X_CSRF_TOKEN", in: env),
        let bearerToken = DotEnv.nonEmptyValue("X_BEARER_TOKEN", in: env),
        let screenName = DotEnv.nonEmptyValue("X_TEST_SCREEN_NAME", in: env)
    else {
        return
    }

    let auth = XAuthContext(
        cookieHeader: cookieHeader,
        csrfToken: csrfToken,
        bearerToken: bearerToken,
        language: DotEnv.nonEmptyValue("X_LANGUAGE", in: env) ?? "ja",
        clientTransactionID: DotEnv.nonEmptyValue("X_CLIENT_TRANSACTION_ID", in: env),
        clientTransactionIDsByOperation: DotEnv.clientTransactionIDsByOperation(in: env),
        operationIDOverrides: DotEnv.operationIDOverrides(in: env)
    )

    let client = XDirectClient(auth: auth)
    let searchQuery = DotEnv.nonEmptyValue("X_TEST_SEARCH_QUERY", in: env) ?? "openai"
    let bookmarkQuery = DotEnv.nonEmptyValue("X_TEST_BOOKMARK_QUERY", in: env)

    for timeline in XUserTimelineType.allCases {
        let page = try await client.listUserPosts(
            screenName: screenName,
            timeline: timeline,
            count: 10
        )
        assertValidPage(page)
    }

    for timeline in XSearchTimelineType.allCases {
        let page = try await client.searchPosts(
            query: searchQuery,
            type: timeline,
            count: 10
        )
        assertValidPage(page)
    }

    let bookmarks = try await client.listBookmarks(count: 10)
    assertValidPage(bookmarks)

    if let bookmarkQuery,
       !bookmarkQuery.isEmpty,
       auth.clientTransactionIDsByOperation["BookmarkSearchTimeline"] != nil {
        let searchedBookmarks = try await client.searchBookmarks(
            query: bookmarkQuery,
            count: 10
        )
        assertValidPage(searchedBookmarks)
    }
}

private func assertValidPage(_ page: XPostsPage) {
    let uniqueIDs = Set(page.posts.map(\.id))
    #expect(uniqueIDs.count == page.posts.count)

    for post in page.posts.prefix(3) {
        #expect(!post.id.isEmpty)
        #expect(post.url.scheme == "https")
        #expect(post.url.host == "x.com")
        #expect(!post.screenName.isEmpty)
    }
}

private enum DotEnv {
    static func loadMergedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let path = "\(FileManager.default.currentDirectoryPath)/.env"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return env
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let separator = line.firstIndex(of: "=") else { continue }

            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty { continue }

            var value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value.removeFirst()
                value.removeLast()
            }
            value = value
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
            env[key] = value
        }
        return env
    }

    static func nonEmptyValue(_ key: String, in env: [String: String]) -> String? {
        guard let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    static func clientTransactionIDsByOperation(in env: [String: String]) -> [String: String] {
        var map: [String: String] = [:]

        let pairs: [(env: String, op: String)] = [
            ("X_CLIENT_TRANSACTION_ID_USER_TWEETS", "UserTweets"),
            ("X_CLIENT_TRANSACTION_ID_USER_TWEETS_AND_REPLIES", "UserTweetsAndReplies"),
            ("X_CLIENT_TRANSACTION_ID_USER_MEDIA", "UserMedia"),
            ("X_CLIENT_TRANSACTION_ID_USER_HIGHLIGHTS_TWEETS", "UserHighlightsTweets"),
            ("X_CLIENT_TRANSACTION_ID_SEARCH_TIMELINE", "SearchTimeline"),
            ("X_CLIENT_TRANSACTION_ID_BOOKMARKS", "Bookmarks"),
            ("X_CLIENT_TRANSACTION_ID_BOOKMARK_SEARCH_TIMELINE", "BookmarkSearchTimeline")
        ]

        for pair in pairs {
            if let value = nonEmptyValue(pair.env, in: env) {
                map[pair.op] = value
            }
        }
        return map
    }

    static func operationIDOverrides(in env: [String: String]) -> [String: String] {
        var map: [String: String] = [:]
        if let bookmarks = nonEmptyValue("X_OPERATION_ID_BOOKMARKS", in: env) {
            map["Bookmarks"] = bookmarks
        }
        if let bookmarkSearch = nonEmptyValue("X_OPERATION_ID_BOOKMARK_SEARCH_TIMELINE", in: env) {
            map["BookmarkSearchTimeline"] = bookmarkSearch
        }
        return map
    }
}
