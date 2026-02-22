import Foundation

public struct XAuthContext: Sendable, Equatable {
    public let cookieHeader: String
    public let csrfToken: String
    public let bearerToken: String
    public let language: String
    public let clientTransactionID: String?
    public let clientTransactionIDsByOperation: [String: String]
    public let operationIDOverrides: [String: String]

    public init(
        cookieHeader: String,
        csrfToken: String,
        bearerToken: String,
        language: String = "en",
        clientTransactionID: String? = nil,
        clientTransactionIDsByOperation: [String: String] = [:],
        operationIDOverrides: [String: String] = [:]
    ) {
        self.cookieHeader = cookieHeader
        self.csrfToken = csrfToken
        self.bearerToken = bearerToken
        self.language = language
        self.clientTransactionID = clientTransactionID
        self.clientTransactionIDsByOperation = clientTransactionIDsByOperation
        self.operationIDOverrides = operationIDOverrides
    }
}

public struct XPost: Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String
    public let screenName: String
    public let createdAt: Date?
    public let createdAtRaw: String?
    public let url: URL
    public let media: [XMediaItem]

    public init(
        id: String,
        text: String,
        screenName: String,
        createdAt: Date?,
        createdAtRaw: String?,
        url: URL,
        media: [XMediaItem] = []
    ) {
        self.id = id
        self.text = text
        self.screenName = screenName
        self.createdAt = createdAt
        self.createdAtRaw = createdAtRaw
        self.url = url
        self.media = media
    }
}

public enum XMediaKind: String, Sendable, Equatable {
    case photo
    case video
    case animatedGif = "animated_gif"
}

public struct XMediaItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: XMediaKind
    public let url: URL
    public let thumbnailURL: URL?
    public let aspectRatio: Double? // width / height

    public init(id: String, kind: XMediaKind, url: URL, thumbnailURL: URL?, aspectRatio: Double?) {
        self.id = id
        self.kind = kind
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.aspectRatio = aspectRatio
    }
}

public struct XPostsPage: Sendable, Equatable {
    public let posts: [XPost]
    public let nextCursor: String?

    public init(posts: [XPost], nextCursor: String?) {
        self.posts = posts
        self.nextCursor = nextCursor
    }
}

public struct XPostURLInfo: Sendable, Equatable {
    public let originalURL: URL
    public let normalizedURL: URL
    public let host: String
    public let screenName: String?
    public let postID: String
    public let refererPath: String

    public init(
        originalURL: URL,
        normalizedURL: URL,
        host: String,
        screenName: String?,
        postID: String,
        refererPath: String
    ) {
        self.originalURL = originalURL
        self.normalizedURL = normalizedURL
        self.host = host
        self.screenName = screenName
        self.postID = postID
        self.refererPath = refererPath
    }
}

public enum XSearchTimelineType: String, Sendable, Equatable, CaseIterable {
    case top
    case latest
    case accounts
    case media
    case lists
    case photos
    case videos

    public var productValue: String {
        switch self {
        case .top: return "Top"
        case .latest: return "Latest"
        case .accounts: return "Top"
        case .media: return "Top"
        case .lists: return "Top"
        case .photos: return "Top"
        case .videos: return "Top"
        }
    }

    public var filterQueryValue: String? {
        switch self {
        case .top: return nil
        case .latest: return "live"
        case .accounts: return "user"
        case .media: return "media"
        case .lists: return "list"
        case .photos: return "image"
        case .videos: return "video"
        }
    }

    public var clientSideMediaKinds: [XMediaKind]? {
        switch self {
        case .photos:
            return [.photo]
        case .videos:
            return [.video, .animatedGif]
        case .top, .latest, .accounts, .media, .lists:
            return nil
        }
    }

    public func filterSearchPosts(_ posts: [XPost]) -> [XPost] {
        guard let kinds = clientSideMediaKinds else { return posts }
        return posts.filter { post in
            post.media.contains { media in
                kinds.contains(media.kind)
            }
        }
    }
}

public enum XUserTimelineType: String, Sendable, Equatable, CaseIterable {
    case posts
    case replies
    case media
    case highlights
}

public enum XDirectClientError: LocalizedError {
    case missingCT0Cookie
    case bearerTokenNotFound
    case operationNotFound(String)
    case invalidResponse
    case unauthorized(status: Int)
    case badStatus(status: Int, body: String)
    case userIdNotFound(String)
    case invalidPostURL(String)
    case postNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .missingCT0Cookie:
            return "ct0 cookie が見つかりません。WebViewでXにログイン後に再試行してください。"
        case .bearerTokenNotFound:
            return "WebクライアントのBearerトークン抽出に失敗しました。"
        case .operationNotFound(let op):
            return "GraphQL operation '\(op)' のqueryId抽出に失敗しました。"
        case .invalidResponse:
            return "レスポンスのJSON形式が想定外です。"
        case .unauthorized(let status):
            return "認証エラーです (HTTP \(status))。ct0/cookie/Bearerを確認してください。"
        case .badStatus(let status, let body):
            return "HTTP \(status): \(body)"
        case .userIdNotFound(let screenName):
            return "@\(screenName) のuserIdを取得できませんでした。"
        case .invalidPostURL(let value):
            return "投稿URLの解析に失敗しました: \(value)"
        case .postNotFound(let postID):
            return "投稿を取得できませんでした (postID: \(postID))。"
        }
    }
}
