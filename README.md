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
- アカウント投稿の種別取得（投稿 / 返信 / メディア / ハイライト）
- 検索タイムラインの種別取得（話題 / 最新 / アカウント / メディア / リスト / 写真 / 動画）
- ブックマーク一覧取得、ブックマーク内検索
- 投稿URL (`.../status/<id>`) から単体投稿を取得
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

    func fetchUserPosts(screenName: String, timeline: XUserTimelineType) async {
        do {
            guard let auth else { return }
            let client = XDirectClient(auth: auth)
            let page = try await client.listUserPosts(
                screenName: screenName,
                timeline: timeline,
                count: 20
            )
            posts = page.posts
            cursor = page.nextCursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func searchPosts(query: String, type: XSearchTimelineType) async {
        do {
            guard let auth else { return }
            let client = XDirectClient(auth: auth)
            let page = try await client.searchPosts(query: query, type: type, count: 20)
            posts = page.posts
            cursor = page.nextCursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchBookmarks(keyword: String?) async {
        do {
            guard let auth else { return }
            let client = XDirectClient(auth: auth)
            let page: XPostsPage
            if let keyword, !keyword.isEmpty {
                page = try await client.searchBookmarks(query: keyword, count: 20)
            } else {
                page = try await client.listBookmarks(count: 20)
            }
            posts = page.posts
            cursor = page.nextCursor
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchSinglePost(from urlString: String) async {
        do {
            guard let auth else { return }
            let client = XDirectClient(auth: auth)
            let post = try await client.fetchPost(from: urlString)
            posts = [post]
            cursor = nil
        } catch {
            errorMessage = error.localizedDescription
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
  - `x-client-transaction-id` は `WKWebView` 上で webpack module を探索しつつ都度生成（`83914.jJ` を優先し、見つからない場合は module cache も走査）
  - `UserByScreenName` / `UserTweets*` / `SearchTimeline` / `Bookmark*` をGETで実行
  - `tweet_results` から投稿を再帰的に抽出

## 統合テスト
- `Tests/XGraphQLkitTests/XDirectClientIntegrationTests.swift` は `.env` から認証値を読みます。
- 既定では実行しないため、実行時は `.env` の `X_RUN_LIVE_TESTS="1"` にしてください。
- `Bookmarks` の `operationId` が `main.js` から取れない場合は、`.env` の `X_OPERATION_ID_BOOKMARKS` を使います。
