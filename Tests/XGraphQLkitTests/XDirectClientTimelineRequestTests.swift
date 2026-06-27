import Foundation
import Testing
@testable import XGraphQLkit

@Suite(.serialized)
private struct XDirectClientTimelineRequestTests {
    @Test func mediaTimelineUsesMediaQueryWithoutUserLookupAndKeepsCursor() async throws {
        let recorder = GraphQLRequestRecorder()
        let session = makeStubbedSession { request in
            if isHomeRequest(request) {
                return StubbedResponse(status: 200, body: "<html></html>")
            }

            let operationName = try graphQLOperationName(from: request)
            let variables = try graphQLVariables(from: request)
            recorder.record(operationName: operationName, variables: variables)

            switch operationName {
            case "UserByScreenName":
                return StubbedResponse(status: 200, body: userByScreenNameResponse(userID: "111"))
            case "mediaQuery":
                return StubbedResponse(status: 200, body: timelineResponse(
                    screenName: "yyyyyy_public",
                    cursor: "BOTTOM_MEDIA",
                    posts: [
                        currentTweet(
                            id: "2025509212844089822",
                            screenName: "yyyyyy_public",
                            mediaType: "video"
                        )
                    ]
                ))
            default:
                return StubbedResponse(status: 404, body: "{}")
            }
        }
        defer {
            session.invalidateAndCancel()
            GraphQLURLProtocolStub.handler = nil
        }

        let client = XDirectClient(
            auth: testAuth(operationIDOverrides: [
                "UserByScreenName": "user-op",
                "mediaQuery": "media-op"
            ]),
            session: session
        )

        let page = try await client.listUserPosts(
            screenName: "yyyyyy_public",
            timeline: .media,
            count: 40,
            cursor: "CURSOR_MEDIA"
        )

        #expect(recorder.operationNames == ["mediaQuery"])
        #expect(recorder.variables(for: "mediaQuery")?["screenName"] as? String == "yyyyyy_public")
        #expect(recorder.variables(for: "mediaQuery")?["count"] as? Int == 40)
        #expect(recorder.variables(for: "mediaQuery")?["cursor"] as? String == "CURSOR_MEDIA")
        #expect(recorder.variables(for: "mediaQuery")?["userId"] == nil)
        #expect(page.posts.map(\.id) == ["2025509212844089822"])
        #expect(page.posts.first?.screenName == "yyyyyy_public")
        #expect(page.posts.first?.media.first?.kind == .video)
        #expect(page.nextCursor == "BOTTOM_MEDIA")
    }

    @Test func videosTimelineUsesUserTweetsWithoutUserLookupAndKeepsCursor() async throws {
        let recorder = GraphQLRequestRecorder()
        let session = makeStubbedSession { request in
            if isHomeRequest(request) {
                return StubbedResponse(status: 200, body: "<html></html>")
            }

            let operationName = try graphQLOperationName(from: request)
            let variables = try graphQLVariables(from: request)
            recorder.record(operationName: operationName, variables: variables)

            switch operationName {
            case "UserByScreenName":
                return StubbedResponse(status: 200, body: userByScreenNameResponse(userID: "111"))
            case "UserTweets":
                return StubbedResponse(status: 200, body: timelineResponse(
                    screenName: "yyyyyy_public",
                    cursor: "BOTTOM_TIMELINE",
                    posts: [
                        currentTweet(id: "video-post", screenName: "yyyyyy_public", mediaType: "video"),
                        currentTweet(id: "photo-post", screenName: "yyyyyy_public", mediaType: "photo")
                    ]
                ))
            default:
                return StubbedResponse(status: 404, body: "{}")
            }
        }
        defer {
            session.invalidateAndCancel()
            GraphQLURLProtocolStub.handler = nil
        }

        let client = XDirectClient(
            auth: testAuth(operationIDOverrides: [
                "UserByScreenName": "user-op",
                "UserTweets": "tweets-op"
            ]),
            session: session
        )

        let page = try await client.listUserPosts(
            screenName: "yyyyyy_public",
            timeline: .videos,
            count: 40,
            cursor: "CURSOR_TIMELINE"
        )

        #expect(recorder.operationNames == ["UserTweets"])
        #expect(recorder.variables(for: "UserTweets")?["screenName"] as? String == "yyyyyy_public")
        #expect(recorder.variables(for: "UserTweets")?["count"] as? Int == 40)
        #expect(recorder.variables(for: "UserTweets")?["cursor"] as? String == "CURSOR_TIMELINE")
        #expect(recorder.variables(for: "UserTweets")?["userId"] == nil)
        #expect(page.posts.map(\.id) == ["video-post"])
        #expect(page.nextCursor == "BOTTOM_TIMELINE")
    }
}

private final class GraphQLRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [(operationName: String, variables: [String: Any])] = []

    var operationNames: [String] {
        lock.withLock {
            captured.map(\.operationName)
        }
    }

    func record(operationName: String, variables: [String: Any]) {
        lock.withLock {
            captured.append((operationName: operationName, variables: variables))
        }
    }

    func variables(for operationName: String) -> [String: Any]? {
        lock.withLock {
            captured.first(where: { $0.operationName == operationName })?.variables
        }
    }
}

private struct StubbedResponse {
    let status: Int
    let body: String
}

private final class GraphQLURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> StubbedResponse)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let stubbed = try handler(request)
            let response = HTTPURLResponse(
                url: url,
                statusCode: stubbed.status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(stubbed.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeStubbedSession(
    handler: @escaping (URLRequest) throws -> StubbedResponse
) -> URLSession {
    GraphQLURLProtocolStub.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GraphQLURLProtocolStub.self]
    return URLSession(configuration: configuration)
}

private func testAuth(operationIDOverrides: [String: String]) -> XAuthContext {
    XAuthContext(
        cookieHeader: "ct0=csrf; auth_token=auth",
        csrfToken: "csrf",
        bearerToken: "bearer",
        language: "ja",
        operationIDOverrides: operationIDOverrides
    )
}

private func isHomeRequest(_ request: URLRequest) -> Bool {
    request.url?.host == "x.com" && request.url?.path == ""
        || request.url?.host == "x.com" && request.url?.path == "/"
}

private func graphQLOperationName(from request: URLRequest) throws -> String {
    guard
        let url = request.url,
        url.path.contains("/i/api/graphql/")
    else {
        throw URLError(.unsupportedURL)
    }
    return url.lastPathComponent
}

private func graphQLVariables(from request: URLRequest) throws -> [String: Any] {
    guard
        let url = request.url,
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        let raw = components.queryItems?.first(where: { $0.name == "variables" })?.value,
        let data = raw.data(using: .utf8),
        let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return [:]
    }
    return dictionary
}

private func userByScreenNameResponse(userID: String) -> String {
    jsonString([
        "data": [
            "user_result_by_screen_name": [
                "result": [
                    "__typename": "User",
                    "rest_id": userID
                ]
            ]
        ]
    ])
}

private func timelineResponse(
    screenName: String,
    cursor: String,
    posts: [[String: Any]]
) -> String {
    let entries: [[String: Any]] = posts.map { post in
        [
            "entryId": "tweet-\(post["rest_id"] ?? UUID().uuidString)",
            "content": [
                "itemContent": [
                    "tweet_results": [
                        "result": post
                    ]
                ]
            ]
        ]
    } + [
        [
            "entryId": "cursor-bottom-0",
            "content": [
                "entryType": "TimelineTimelineCursor",
                "cursor_type": "Bottom",
                "value": cursor
            ]
        ]
    ]

    return jsonString([
        "data": [
            "user_result_by_screen_name": [
                "result": [
                    "__typename": "User",
                    "core": [
                        "screen_name": screenName
                    ],
                    "timeline": [
                        "instructions": [
                            [
                                "type": "TimelineAddEntries",
                                "entries": entries
                            ]
                        ]
                    ]
                ]
            ]
        ]
    ])
}

private func currentTweet(
    id: String,
    screenName: String,
    mediaType: String
) -> [String: Any] {
    var media: [String: Any] = [
        "id_str": "\(id)-media",
        "type": mediaType,
        "media_url_https": "https://pbs.twimg.com/media/\(id).jpg"
    ]
    if mediaType != "photo" {
        media["video_info"] = [
            "aspect_ratio": [16, 9],
            "variants": [
                [
                    "content_type": "application/x-mpegURL",
                    "url": "https://video.twimg.com/ext_tw_video/\(id)/playlist.m3u8"
                ],
                [
                    "bitrate": 832000,
                    "content_type": "video/mp4",
                    "url": "https://video.twimg.com/ext_tw_video/\(id)/video.mp4"
                ]
            ]
        ]
    }

    return [
        "__typename": "Tweet",
        "rest_id": id,
        "details": [
            "full_text": "Post \(id)",
            "created_at_ms": "1782500000000"
        ],
        "core": [
            "user_results": [
                "result": [
                    "__typename": "User",
                    "core": [
                        "screen_name": screenName
                    ]
                ]
            ]
        ],
        "media_entities2": [media]
    ]
}

private func jsonString(_ object: Any) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
}
