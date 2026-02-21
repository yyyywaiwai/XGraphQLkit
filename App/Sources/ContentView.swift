import SwiftUI
import AVKit
import XGraphQLkit

@MainActor
final class TimelineViewModel: ObservableObject {
    enum Source: String, CaseIterable, Identifiable {
        case account
        case search
        case bookmarks

        var id: String { rawValue }
    }

    @Published var auth: XAuthContext?
    @Published var source: Source = .account
    @Published var screenName: String = "XDevelopers"
    @Published var searchQuery: String = "openai"
    @Published var bookmarkQuery: String = ""
    @Published var userTimelineType: XUserTimelineType = .posts
    @Published var searchTimelineType: XSearchTimelineType = .top
    @Published var posts: [XPost] = []
    @Published var nextCursor: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let logPrefix = "[XGraphQLtest]"
    private var requestSequence: Int = 0
    private static let debugDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func debugLog(_ message: String, requestID: Int? = nil) {
        let timestamp = Self.debugDateFormatter.string(from: Date())
        if let requestID {
            print("\(logPrefix) [\(timestamp)] [req:\(requestID)] \(message)")
        } else {
            print("\(logPrefix) [\(timestamp)] \(message)")
        }
    }

    private func nextRequestID() -> Int {
        requestSequence += 1
        return requestSequence
    }

    private func debugMaskedToken(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "-" }
        let suffixCount = min(4, token.count)
        let suffix = String(token.suffix(suffixCount))
        if token.count <= 8 {
            return "****\(suffix)"
        }
        let prefixCount = min(4, token.count - suffixCount)
        let prefix = String(token.prefix(prefixCount))
        return "\(prefix)...\(suffix)"
    }

    private func debugShortText(_ text: String, maxLength: Int = 180) -> String {
        let compact = text.replacingOccurrences(of: "\n", with: " ")
        return String(compact.prefix(maxLength))
    }

    private func debugAuthSummary(_ auth: XAuthContext) -> String {
        let overrideOps = auth.operationIDOverrides.keys.sorted().joined(separator: ",")
        let transactionOps = auth.clientTransactionIDsByOperation.keys.sorted().joined(separator: ",")
        return """
        language=\(auth.language) cookieLen=\(auth.cookieHeader.count) ct0=\(debugMaskedToken(auth.csrfToken)) bearer=\(debugMaskedToken(auth.bearerToken))
        opOverrides=[\(overrideOps)] clientTransactionOps=[\(transactionOps)] globalClientTransactionID=\(debugMaskedToken(auth.clientTransactionID))
        """
    }

    private func debugSearchRefererPath(query: String, querySource: String, type: XSearchTimelineType) -> String {
        var components = URLComponents()
        components.path = "/search"
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "src", value: querySource)
        ]
        if let filter = type.filterQueryValue {
            items.append(URLQueryItem(name: "f", value: filter))
        }
        components.queryItems = items
        if let query = components.percentEncodedQuery, !query.isEmpty {
            return "/search?\(query)"
        }
        return "/search"
    }

    func loadFirstPage() async {
        debugLog("loadFirstPage source=\(source.rawValue) currentPosts=\(posts.count)")
        switch source {
        case .account:
            let name = screenName.trimmingCharacters(in: .whitespacesAndNewlines)
            debugLog("selection account screenName=\(name) timeline=\(userTimelineType.rawValue) expectedOp=\(userTimelineType.debugOperationName) expectedReferer=\(userTimelineType.debugRefererPath(screenName: name))")
        case .search:
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            debugLog("selection search query=\(debugShortText(query, maxLength: 90)) type=\(searchTimelineType.rawValue) product=\(searchTimelineType.productValue) filter=\(searchTimelineType.filterQueryValue ?? "-") referer=\(debugSearchRefererPath(query: query, querySource: "typed_query", type: searchTimelineType))")
        case .bookmarks:
            let query = bookmarkQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            debugLog("selection bookmarks query=\(debugShortText(query, maxLength: 90)) mode=\(query.isEmpty ? "list" : "search")")
        }
        posts = []
        nextCursor = nil
        await loadNextPage()
    }

    func loadNextPage() async {
        guard let auth else {
            debugLog("loadNextPage skipped: auth is nil")
            return
        }
        guard !isLoading else {
            debugLog("loadNextPage skipped: already loading")
            return
        }

        let requestID = nextRequestID()
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        debugLog("loadNextPage start source=\(source.rawValue) cursor=\(nextCursor ?? "-") posts=\(posts.count)", requestID: requestID)
        debugLog("auth \(debugAuthSummary(auth))", requestID: requestID)

        do {
            let requestTag = "[req:\(requestID)]"
            let client = XDirectClient(
                auth: auth,
                debugLog: { [logPrefix, requestTag] message in
                    print("\(logPrefix) \(requestTag) \(message)")
                }
            )
            let page: XPostsPage
            switch source {
            case .account:
                let name = screenName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    errorMessage = "screenName を入力してください。"
                    debugLog("validation failed: empty screenName", requestID: requestID)
                    return
                }
                debugLog("request account op=\(userTimelineType.debugOperationName) screenName=\(name) timeline=\(userTimelineType.rawValue) referer=\(userTimelineType.debugRefererPath(screenName: name)) cursor=\(nextCursor ?? "-")", requestID: requestID)
                page = try await client.listUserPosts(
                    screenName: name,
                    timeline: userTimelineType,
                    count: 20,
                    cursor: nextCursor
                )

            case .search:
                let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    errorMessage = "検索ワードを入力してください。"
                    debugLog("validation failed: empty search query", requestID: requestID)
                    return
                }
                debugLog("request search op=SearchTimeline query=\(debugShortText(query, maxLength: 120)) type=\(searchTimelineType.rawValue) product=\(searchTimelineType.productValue) filter=\(searchTimelineType.filterQueryValue ?? "-") referer=\(debugSearchRefererPath(query: query, querySource: "typed_query", type: searchTimelineType)) cursor=\(nextCursor ?? "-")", requestID: requestID)
                page = try await client.searchPosts(
                    query: query,
                    type: searchTimelineType,
                    count: 20,
                    cursor: nextCursor
                )

            case .bookmarks:
                let query = bookmarkQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.isEmpty {
                    debugLog("request bookmarks op=Bookmarks mode=list cursor=\(nextCursor ?? "-")", requestID: requestID)
                    page = try await client.listBookmarks(count: 20, cursor: nextCursor)
                } else {
                    debugLog("request bookmarks op=BookmarkSearchTimeline mode=search query=\(debugShortText(query, maxLength: 120)) cursor=\(nextCursor ?? "-")", requestID: requestID)
                    page = try await client.searchBookmarks(
                        query: query,
                        count: 20,
                        cursor: nextCursor
                    )
                }
            }

            posts.append(contentsOf: page.posts)
            nextCursor = page.nextCursor
            let headPostIDs = page.posts.prefix(3).map(\.id).joined(separator: ",")
            debugLog("success fetched=\(page.posts.count) total=\(posts.count) nextCursor=\(nextCursor ?? "-") headPostIDs=[\(headPostIDs)]", requestID: requestID)
        } catch {
            switch error {
            case let XDirectClientError.badStatus(status, body):
                debugLog("error badStatus status=\(status) bodyLen=\(body.count) bodyPrefix=\(debugShortText(body, maxLength: 260))", requestID: requestID)
            case let XDirectClientError.operationNotFound(operation):
                debugLog("error operationNotFound op=\(operation)", requestID: requestID)
            case let XDirectClientError.unauthorized(status):
                debugLog("error unauthorized status=\(status)", requestID: requestID)
            default:
                debugLog("error type=\(String(reflecting: Swift.type(of: error))) message=\(error.localizedDescription)", requestID: requestID)
            }
            errorMessage = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = TimelineViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.auth == nil {
                    VStack(spacing: 12) {
                        Text("Xにログインして認証情報を取得します")
                            .font(.headline)
                        Text("捨て垢前提のPoCです。ログイン後、自動でct0/Cookie/Bearerを取得します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        XLoginWebView { result in
                            switch result {
                            case .success(let auth):
                                let overrideOps = auth.operationIDOverrides.keys.sorted().joined(separator: ",")
                                let transactionOps = auth.clientTransactionIDsByOperation.keys.sorted().joined(separator: ",")
                                print("[XGraphQLtest] auth captured language=\(auth.language) cookieLen=\(auth.cookieHeader.count) ct0Len=\(auth.csrfToken.count) bearerLen=\(auth.bearerToken.count) opOverrides=[\(overrideOps)] clientTransactionOps=[\(transactionOps)]")
                                Task { @MainActor in
                                    vm.auth = auth
                                }
                            case .failure(let err):
                                print("[XGraphQLtest] auth capture failed: \(err.localizedDescription)")
                                Task { @MainActor in
                                    vm.errorMessage = err.localizedDescription
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.quaternary, lineWidth: 1)
                        }
                        .padding()
                    }
                } else {
                    VStack(spacing: 0) {
                        VStack(spacing: 10) {
                            Picker("取得元", selection: $vm.source) {
                                ForEach(TimelineViewModel.Source.allCases) { source in
                                    Text(source.label).tag(source)
                                }
                            }
                            .pickerStyle(.segmented)

                            switch vm.source {
                            case .account:
                                HStack(spacing: 8) {
                                    TextField("@screenName", text: $vm.screenName)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .textFieldStyle(.roundedBorder)

                                    Picker("種別", selection: $vm.userTimelineType) {
                                        ForEach(XUserTimelineType.allCases, id: \.self) { kind in
                                            Text(kind.label).tag(kind)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }

                            case .search:
                                HStack(spacing: 8) {
                                    TextField("検索ワード", text: $vm.searchQuery)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .textFieldStyle(.roundedBorder)

                                    Picker("種別", selection: $vm.searchTimelineType) {
                                        ForEach(XSearchTimelineType.allCases, id: \.self) { kind in
                                            Text(kind.label).tag(kind)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }

                            case .bookmarks:
                                TextField("ブックマーク内検索（空欄で全件）", text: $vm.bookmarkQuery)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack {
                                Button("読み込み") {
                                    Task { await vm.loadFirstPage() }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(vm.isLoading)

                                if vm.isLoading {
                                    ProgressView()
                                }
                            }
                        }
                        .padding()

                        if let msg = vm.errorMessage {
                            Text(msg)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                        }
                        List(vm.posts) { post in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(post.text)
                                    .font(.body)

                                if !post.media.isEmpty {
                                    XMediaStripView(items: post.media)
                                        .padding(.top, 4)
                                }

                                Text(post.url.absoluteString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .onTapGesture {
                                UIApplication.shared.open(post.url)
                            }
                        }

                        HStack {
                            Button("次のページ") {
                                Task { await vm.loadNextPage() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(vm.nextCursor == nil || vm.isLoading)

                            if vm.isLoading {
                                ProgressView()
                                    .padding(.leading, 6)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("XGraphQLtest")
            .onChange(of: vm.source) { value in
                print("[XGraphQLtest] ui source changed -> \(value.rawValue)")
            }
            .onChange(of: vm.userTimelineType) { value in
                print("[XGraphQLtest] ui userTimelineType changed -> \(value.rawValue) op=\(value.debugOperationName)")
            }
            .onChange(of: vm.searchTimelineType) { value in
                print("[XGraphQLtest] ui searchTimelineType changed -> \(value.rawValue) product=\(value.productValue) filter=\(value.filterQueryValue ?? "-")")
            }
        }
    }
}

private extension TimelineViewModel.Source {
    var label: String {
        switch self {
        case .account: return "アカウント"
        case .search: return "検索"
        case .bookmarks: return "ブックマーク"
        }
    }
}

private extension XUserTimelineType {
    var label: String {
        switch self {
        case .posts: return "投稿"
        case .replies: return "返信"
        case .media: return "メディア"
        case .highlights: return "ハイライト"
        }
    }

    var debugOperationName: String {
        switch self {
        case .posts: return "UserTweets"
        case .replies: return "UserTweetsAndReplies"
        case .media: return "UserMedia"
        case .highlights: return "UserHighlightsTweets"
        }
    }

    func debugRefererPath(screenName: String) -> String {
        switch self {
        case .posts: return "/\(screenName)"
        case .replies: return "/\(screenName)/with_replies"
        case .media: return "/\(screenName)/media"
        case .highlights: return "/\(screenName)/highlights"
        }
    }
}

private extension XSearchTimelineType {
    var label: String {
        switch self {
        case .top: return "話題"
        case .latest: return "最新"
        case .accounts: return "アカウント"
        case .media: return "メディア"
        case .lists: return "リスト"
        case .photos: return "写真"
        case .videos: return "動画"
        }
    }
}

private struct XMediaStripView: View {
    let items: [XMediaItem]
    @State private var selectedItem: XMediaItem?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(items) { item in
                    XMediaItemView(item: item)
                        .onTapGesture {
                            selectedItem = item
                        }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $selectedItem) { item in
            XMediaViewer(item: item)
        }
    }
}

private struct XMediaItemView: View {
    let item: XMediaItem

    var body: some View {
        ZStack {
            switch item.kind {
            case .photo:
                AsyncImage(url: item.url) { phase in
                    switch phase {
                    case .empty:
                        ZStack { Color.secondary.opacity(0.15); ProgressView() }
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        ZStack { Color.secondary.opacity(0.15); Image(systemName: "photo").font(.title3) }
                    @unknown default:
                        ZStack { Color.secondary.opacity(0.15) }
                    }
                }
            case .video, .animatedGif:
                if let thumb = item.thumbnailURL {
                    AsyncImage(url: thumb) { phase in
                        switch phase {
                        case .empty:
                            ZStack { Color.secondary.opacity(0.15); ProgressView() }
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            ZStack { Color.secondary.opacity(0.15); Image(systemName: "video").font(.title3) }
                        @unknown default:
                            ZStack { Color.secondary.opacity(0.15) }
                        }
                    }
                } else {
                    ZStack { Color.secondary.opacity(0.15); Image(systemName: "video").font(.title3) }
                }

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 220, height: heightForItem(item))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1) }
    }

    private func heightForItem(_ item: XMediaItem) -> CGFloat {
        // ざっくり見やすいサイズ。縦長になりすぎないよう上限を置く。
        let w: CGFloat = 220
        if let ar = item.aspectRatio, ar > 0 {
            let h = w / CGFloat(ar)
            return min(max(h, 140), 260)
        }
        return 170
    }
}

private struct XMediaViewer: View {
    let item: XMediaItem
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Group {
                switch item.kind {
                case .photo:
                    AsyncImage(url: item.url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding()
                        case .failure:
                            Text("画像の読み込みに失敗しました")
                                .foregroundStyle(.white)
                        @unknown default:
                            EmptyView()
                        }
                    }
                case .video, .animatedGif:
                    if let player {
                        VideoPlayer(player: player)
                            .onAppear { player.play() }
                            .onDisappear { player.pause() }
                    } else {
                        ProgressView().tint(.white)
                            .onAppear {
                                // 通常は video.twimg.com 側なので追加ヘッダ無しで再生できる想定
                                player = AVPlayer(url: item.url)
                            }
                    }
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(16)
            }
        }
    }
}
