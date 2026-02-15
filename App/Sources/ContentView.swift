import SwiftUI
import AVKit
import XDirectGraphQLPoC

@MainActor
final class TimelineViewModel: ObservableObject {
    @Published var auth: XAuthContext?
    @Published var screenName: String = "XDevelopers"
    @Published var posts: [XPost] = []
    @Published var nextCursor: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    func loadFirstPage() async {
        posts = []
        nextCursor = nil
        await loadNextPage()
    }

    func loadNextPage() async {
        guard let auth else { return }
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let client = XDirectClient(auth: auth)
            let page = try await client.listUserPosts(
                screenName: screenName,
                count: 20,
                cursor: nextCursor
            )
            posts.append(contentsOf: page.posts)
            nextCursor = page.nextCursor
        } catch {
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
                                vm.auth = auth
                            case .failure(let err):
                                vm.errorMessage = err.localizedDescription
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
                        HStack(spacing: 8) {
                            TextField("@screenName", text: $vm.screenName)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button("読み込み") {
                                Task { await vm.loadFirstPage() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(vm.isLoading)
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
