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
