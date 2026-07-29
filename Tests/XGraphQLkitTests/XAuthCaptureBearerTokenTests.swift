import Foundation
import Testing
@testable import XGraphQLkit

@Test func fetchPublicBearerTokenFollowsNestedXWebAssets() async throws {
    let token = "AAAAA_TEST_NESTED_BEARER_TOKEN_FOR_UNIT_TESTS_000000"
    NestedAssetURLProtocol.handler = { request in
        guard let url = request.url else {
            throw URLError(.badURL)
        }

        switch url.absoluteString {
        case "https://x.com":
            return #"<script type="module" src="https://abs.twimg.com/x-web/x-web/entry-client.js"></script>"#
        case "https://abs.twimg.com/x-web/x-web/entry-client.js":
            return #"import { token } from "./assets/guest-token-current.js";"#
        case "https://abs.twimg.com/x-web/x-web/assets/guest-token-current.js":
            return #"headers.set("Authorization", "Bearer \#(token)");"#
        default:
            throw URLError(.unsupportedURL)
        }
    }
    defer { NestedAssetURLProtocol.handler = nil }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NestedAssetURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let capturedToken = try await XAuthCapture.fetchPublicBearerToken(session: session)

    #expect(capturedToken == token)
}

@Test func fetchPublicBearerTokenFromLiveXWhenEnabled() async throws {
    guard ProcessInfo.processInfo.environment["X_RUN_PUBLIC_BEARER_TEST"] == "1" else {
        return
    }

    let capturedToken = try await XAuthCapture.fetchPublicBearerToken()

    #expect(capturedToken.hasPrefix("AAAAA"))
    #expect(capturedToken.count >= 35)
}

private final class NestedAssetURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> String)?

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
            let body = try handler(request)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/javascript"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
