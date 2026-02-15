# XGraphQLkit

XのWebクライアント用GraphQL (`/i/api/graphql/...`) を iOS から直接呼び出すためのPoCです。

## 重要注意
- この方式は非公式で、いつでも壊れる可能性があります。
- `queryId` やレスポンス形式は頻繁に変わります。
- アカウント制限・レート制限・規約面のリスクがあります。
- 本番運用向けではなく、検証用途向けです。

## できること
- WebViewでログイン後、`ct0` + Cookie + WebクライアントBearerを取得
- `UserByScreenName` で userId 解決
- `UserTweets` で投稿一覧を取得
- `nextCursor` でページング継続

## 使い方（SwiftUIの最小例）

```swift
import SwiftUI
import XGraphQLkit

@MainActor
final class VM: ObservableObject {
    @Published var auth: XAuthContext?
    @Published var posts: [XPost] = []
    @Published var cursor: String?
    @Published var errorMessage: String?

    func fetchFirstPage(screenName: String) async {
        do {
            guard let auth else { return }
            let client = XDirectClient(auth: auth)
            let page = try await client.listUserPosts(screenName: screenName, count: 20)
            posts = page.posts
            cursor = page.nextCursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchNext(screenName: String) async {
        do {
            guard let auth else { return }
            guard let cursor else { return }
            let client = XDirectClient(auth: auth)
            let page = try await client.listUserPosts(screenName: screenName, count: 20, cursor: cursor)
            posts.append(contentsOf: page.posts)
            self.cursor = page.nextCursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = VM()
    @State private var screenName = "XDevelopers"

    var body: some View {
        VStack {
            if vm.auth == nil {
                XLoginWebView { result in
                    if case .success(let auth) = result {
                        vm.auth = auth
                    }
                }
            } else {
                List(vm.posts) { post in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(post.text)
                        Text(post.url.absoluteString).font(.caption)
                    }
                }
                HStack {
                    Button("Load First") {
                        Task { await vm.fetchFirstPage(screenName: screenName) }
                    }
                    Button("Load Next") {
                        Task { await vm.fetchNext(screenName: screenName) }
                    }
                }
            }
        }
    }
}
```

## 実装メモ
- `XAuthCapture`:
  - `WKHTTPCookieStore` から Cookie/ct0 を抽出
  - `https://x.com` の `main.*.js` から Bearer を抽出
- `XDirectClient`:
  - `main.*.js` から `operationName -> queryId` を動的抽出
  - `UserByScreenName` と `UserTweets` をGETで実行
  - `tweet_results` から投稿を再帰的に抽出
