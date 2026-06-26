import Foundation
import Testing
@testable import XGraphQLkit

@Test func extractOperationIDs_handlesEscapedAndUnescapedAndOrder() async throws {
    let body = #"""
    /* minified-ish */
    a={queryId:\"AAAA1111bbbb2222CCCC3333dddd4444\",operationName:\"UserTweets\"};
    b={operationName:"UserByScreenName",queryId:"zzzz9999YYYY8888xxxx7777WWWW6666"};
    c={QueryId:"MiXeD5555MiXeD6666MiXeD7777MiXeD8888",OperationName:"SomeOp"};
    """#

    let map = XOperationIDExtractor.extractOperationIDs(from: body)

    #expect(map["UserTweets"] == "AAAA1111bbbb2222CCCC3333dddd4444")
    #expect(map["UserByScreenName"] == "zzzz9999YYYY8888xxxx7777WWWW6666")
    #expect(map["SomeOp"] == "MiXeD5555MiXeD6666MiXeD7777MiXeD8888")
}

@Test func extractOperationIDs_handlesRelayParamsIDAndName() async throws {
    let body = #"""
    var O = {
      fragment:{name:`UserByScreenName`},
      params:{id:`iAhB7PpOVltiFEfQBeA40Q`,metadata:{},name:`UserByScreenName`,operationKind:`query`,text:null}
    };
    """#

    let map = XOperationIDExtractor.extractOperationIDs(from: body)

    #expect(map["UserByScreenName"] == "iAhB7PpOVltiFEfQBeA40Q")
}

@Test func extractOperationIDs_handlesCurrentRelayProvidedVariablesShape() async throws {
    let body = #"""
    var A={fragment:{argumentDefinitions:[],kind:`Fragment`,metadata:null,name:`UserByScreenName`},
    params:{id:`_kuJi4oIDFMUU-N285gZWg`,metadata:{},name:`UserByScreenName`,operationKind:`query`,text:null,providedVariables:{__relay_internal__pv__appviewerisloggedinprovider:p}}};
    """#

    let map = XOperationIDExtractor.extractOperationIDs(from: body)

    #expect(map["UserByScreenName"] == "_kuJi4oIDFMUU-N285gZWg")
}

@Test func userByScreenNameUserIDExtraction_handlesCurrentAndLegacyShapes() async throws {
    let current: [String: Any] = [
        "data": [
            "user_result_by_screen_name": [
                "result": [
                    "__typename": "User",
                    "rest_id": "1429332355580235777"
                ]
            ]
        ]
    ]
    let legacy: [String: Any] = [
        "data": [
            "user_result_by_screen_name": [
                "result": [
                    "user": [
                        "rest_id": "1234567890"
                    ]
                ]
            ]
        ]
    ]
    let older: [String: Any] = [
        "data": [
            "user": [
                "result": [
                    "rest_id": "9999999999"
                ]
            ]
        ]
    ]

    #expect(XDirectClient.userID(fromUserByScreenNameRoot: current) == "1429332355580235777")
    #expect(XDirectClient.userID(fromUserByScreenNameRoot: legacy) == "1234567890")
    #expect(XDirectClient.userID(fromUserByScreenNameRoot: older) == "9999999999")
}

@Test func authCapture_scriptURLsSupportLegacyAndXWebAssets() async throws {
    let html = #"""
    <link rel="modulepreload" href="https://abs.twimg.com/x-web/x-web/assets/chunk-DhL7OvcY.js">
    <link rel="modulepreload" href="https://abs.twimg.com/x-web/x-web/assets/guest-token-pxm0d9yq.js">
    <script src="https://abs.twimg.com/responsive-web/client-web/main.123abc.js"></script>
    <script src="/relative/app.js"></script>
    """#

    let urls = XAuthCapture.scriptURLs(in: html).map(\.absoluteString)
    #expect(urls.contains("https://abs.twimg.com/x-web/x-web/assets/chunk-DhL7OvcY.js"))
    #expect(urls.contains("https://abs.twimg.com/x-web/x-web/assets/guest-token-pxm0d9yq.js"))
    #expect(urls.contains("https://abs.twimg.com/responsive-web/client-web/main.123abc.js"))
    #expect(urls.contains("https://x.com/relative/app.js"))

    let prioritized = XAuthCapture.prioritizedScriptURLs(from: html).map(\.absoluteString)
    #expect(prioritized.first == "https://abs.twimg.com/x-web/x-web/assets/guest-token-pxm0d9yq.js")
}

@Test func authCapture_resolvesNestedXWebAssetReferences() async throws {
    let script = #"""
    import("./user-profile-D6pmWWzj.js");
    const deps = ["assets/generic-timeline-BXqNE4XM.js"];
    """#
    let baseURL = URL(string: "https://abs.twimg.com/x-web/x-web/assets/_profile-B78i3Kpo.js")!

    let urls = XAuthCapture.javaScriptAssetURLs(in: script, baseURL: baseURL).map(\.absoluteString)

    #expect(urls.contains("https://abs.twimg.com/x-web/x-web/assets/user-profile-D6pmWWzj.js"))
    #expect(urls.contains("https://abs.twimg.com/x-web/x-web/assets/generic-timeline-BXqNE4XM.js"))
}

@Test func authCapture_extractsBearerTokenFromXWebGuestTokenAsset() async throws {
    let token = "AAAAA_TEST_BEARER_TOKEN_FOR_UNIT_TESTS_ONLY_000000"
    let script = #"n.set(`Authorization`,`Bearer \#(token)`)"#

    #expect(XAuthCapture.firstBearerToken(in: script) == token)
}

@Test func searchTimelineType_productAndFilterMapping() async throws {
    #expect(XSearchTimelineType.top.productValue == "Top")
    #expect(XSearchTimelineType.latest.productValue == "Latest")
    #expect(XSearchTimelineType.accounts.productValue == "Top")
    #expect(XSearchTimelineType.media.productValue == "Top")
    #expect(XSearchTimelineType.lists.productValue == "Top")
    #expect(XSearchTimelineType.photos.productValue == "Top")
    #expect(XSearchTimelineType.videos.productValue == "Top")

    #expect(XSearchTimelineType.top.filterQueryValue == nil)
    #expect(XSearchTimelineType.latest.filterQueryValue == "live")
    #expect(XSearchTimelineType.accounts.filterQueryValue == "user")
    #expect(XSearchTimelineType.media.filterQueryValue == "media")
    #expect(XSearchTimelineType.lists.filterQueryValue == "list")
    #expect(XSearchTimelineType.photos.filterQueryValue == "image")
    #expect(XSearchTimelineType.videos.filterQueryValue == "video")

    #expect(XSearchTimelineType.top.clientSideMediaKinds == nil)
    #expect(XSearchTimelineType.latest.clientSideMediaKinds == nil)
    #expect(XSearchTimelineType.accounts.clientSideMediaKinds == nil)
    #expect(XSearchTimelineType.media.clientSideMediaKinds == nil)
    #expect(XSearchTimelineType.lists.clientSideMediaKinds == nil)
    #expect(XSearchTimelineType.photos.clientSideMediaKinds == [.photo])
    #expect(XSearchTimelineType.videos.clientSideMediaKinds == [.video, .animatedGif])
}

@Test func searchTimelineType_clientSideMediaFiltering() async throws {
    let posts = [
        makePost(id: "p-photo", mediaKinds: [.photo]),
        makePost(id: "p-video", mediaKinds: [.video]),
        makePost(id: "p-gif", mediaKinds: [.animatedGif]),
        makePost(id: "p-mixed", mediaKinds: [.photo, .video]),
        makePost(id: "p-none", mediaKinds: [])
    ]

    let photos = XSearchTimelineType.photos.filterSearchPosts(posts)
    #expect(photos.map(\.id) == ["p-photo", "p-mixed"])

    let videos = XSearchTimelineType.videos.filterSearchPosts(posts)
    #expect(videos.map(\.id) == ["p-video", "p-gif", "p-mixed"])

    let top = XSearchTimelineType.top.filterSearchPosts(posts)
    #expect(top.map(\.id) == posts.map(\.id))
}

@Test func userTimelineType_videosFiltersVideoPosts() async throws {
    let posts = [
        makePost(id: "p-photo", mediaKinds: [.photo]),
        makePost(id: "p-video", mediaKinds: [.video]),
        makePost(id: "p-gif", mediaKinds: [.animatedGif]),
        makePost(id: "p-mixed", mediaKinds: [.photo, .video]),
        makePost(id: "p-none", mediaKinds: [])
    ]

    let videos = XUserTimelineType.videos.filterPosts(posts)
    #expect(videos.map(\.id) == ["p-video", "p-gif", "p-mixed"])

    let regularPosts = XUserTimelineType.posts.filterPosts(posts)
    #expect(regularPosts.map(\.id) == posts.map(\.id))
}

@Test func graphQLValidationRecovery_retriesHTTP422AndExtractsMissingKeys() async throws {
    let featuresBody = #"""
    {"errors":[{"code":"GRAPHQL_VALIDATION_FAILED","message":"The following features cannot be null: responsive_web_next_feature_enabled, rweb_new_media_tab_enabled."}]}
    """#
    let fieldTogglesBody = #"""
    {"errors":[{"code":"GRAPHQL_VALIDATION_FAILED","message":"The following fieldToggles cannot be null: withArticlePlainText"}]}
    """#

    #expect(XGraphQLValidationRecovery.isRetryableStatus(400))
    #expect(XGraphQLValidationRecovery.isRetryableStatus(422))
    #expect(!XGraphQLValidationRecovery.isRetryableStatus(429))

    #expect(
        XGraphQLValidationRecovery.missingKeys(from: featuresBody, kind: .features) == [
            "responsive_web_next_feature_enabled",
            "rweb_new_media_tab_enabled"
        ]
    )
    #expect(
        XGraphQLValidationRecovery.missingKeys(from: fieldTogglesBody, kind: .fieldToggles) == [
            "withArticlePlainText"
        ]
    )
}

@Test func parsePostURL_extractsScreenNameAndPostID() async throws {
    let input = URL(string: "https://x.com/yyyyyy_public/status/2025509212844089822?s=20")!
    let info = XDirectClient.parsePostURL(input)

    #expect(info != nil)
    #expect(info?.screenName == "yyyyyy_public")
    #expect(info?.postID == "2025509212844089822")
    #expect(info?.refererPath == "/yyyyyy_public/status/2025509212844089822")
    #expect(info?.normalizedURL.absoluteString == "https://x.com/yyyyyy_public/status/2025509212844089822")
}

@Test func parsePostURL_supportsIWebStatusPath() async throws {
    let input = URL(string: "https://x.com/i/web/status/2025509212844089822")!
    let info = XDirectClient.parsePostURL(input)

    #expect(info != nil)
    #expect(info?.screenName == nil)
    #expect(info?.postID == "2025509212844089822")
    #expect(info?.refererPath == "/i/web/status/2025509212844089822")
}

@Test func parsePostURL_rejectsInvalidHostOrPath() async throws {
    #expect(XDirectClient.parsePostURL(URL(string: "https://example.com/user/status/1234567890")!) == nil)
    #expect(XDirectClient.parsePostURL(URL(string: "https://x.com/user/likes")!) == nil)
    #expect(XDirectClient.parsePostURL("not-a-url") == nil)
}

private func makePost(id: String, mediaKinds: [XMediaKind]) -> XPost {
    let media = mediaKinds.enumerated().map { idx, kind in
        XMediaItem(
            id: "\(id)-m\(idx)",
            kind: kind,
            url: URL(string: "https://example.com/\(id)-\(idx).mp4")!,
            thumbnailURL: nil,
            aspectRatio: nil
        )
    }
    return XPost(
        id: id,
        text: id,
        screenName: "tester",
        createdAt: nil,
        createdAtRaw: nil,
        url: URL(string: "https://x.com/tester/status/\(id)")!,
        media: media
    )
}
